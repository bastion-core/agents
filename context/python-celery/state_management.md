# State Management

This document describes how state flows through the Python Celery worker project: the interactor pattern applied to tasks, session and transaction management, dependency injection without HTTP request scope, error handling in async contexts, and testing strategies for Celery tasks.

## State Pattern

### Interactor Pattern in Celery Tasks

Interactors are identical to those in the API project. They are agnostic to whether they are invoked from an HTTP route or a Celery task. Each interactor handles one use case and follows the validate-then-process flow inherited from `BaseInteractor`.

```python
class ProcessDriverPaymentInteractor(BaseInteractor):
    def __init__(self, repository: PaymentRepository, logger: LoggerService):
        BaseInteractor.__init__(self)
        self.repository = repository        # Domain interface (ABC)
        self.logger = logger

    def validate(self, input_dto: ProcessPaymentDto) -> bool | OutputErrorContext:
        driver = self.repository.find_driver_by_id(input_dto.driver_id)
        if not driver:
            return OutputErrorContext(
                http_status=404,
                code="DRIVER_NOT_FOUND",
                message="Driver does not exist"
            )
        return True

    def process(self, input_dto: ProcessPaymentDto) -> OutputSuccessContext | OutputErrorContext:
        payment = self.repository.create_payment(input_dto)
        return OutputSuccessContext(data=[payment])
```

The `run()` method (inherited from `BaseInteractor`) orchestrates:
1. `validate(dto)` -- returns `True` or `OutputErrorContext`
2. If validation fails, returns `OutputErrorContext` immediately
3. If validation passes, calls `process(dto)` -- returns `OutputSuccessContext` or `OutputErrorContext`

### Constructor Rule

All constructor type hints in interactors use **domain abstractions** (ABC interfaces). This is identical to the API project. The interactor has no knowledge of whether it is invoked from an HTTP request or a Celery task.

## Data Flow

### Task Execution Lifecycle

```
Message Queue (Redis/RabbitMQ)
    -> Celery Worker picks up message
        -> Task function (infrastructure adapter)
            -> Create database session
            -> Wire dependencies (factory pattern)
            -> Interactor.run(dto) [inherited from BaseInteractor]
                -> validate(dto) -> True | OutputErrorContext
                -> process(dto)  -> OutputSuccessContext | OutputErrorContext
            -> Commit on success / Rollback on failure
            -> Close session
        -> Acknowledge message (acks_late)
    -> Next message
```

### Session Management (Per-Task Scoping)

The critical difference from the API project: there is no HTTP request scope. Database sessions are scoped to individual task executions.

```python
from sqlalchemy.orm import sessionmaker

TaskSession = sessionmaker(bind=engine)

def get_task_session() -> Session:
    """Create a new session scoped to the current task execution."""
    return TaskSession()
```

**Session lifecycle within a task:**
1. Create session at task start (`get_task_session()`)
2. Pass session to repository constructors
3. Commit on success (`db.commit()`)
4. Rollback on failure (`db.rollback()`)
5. Close session in `finally` block (`db.close()`)

This pattern prevents session leaks and ensures each task execution operates in an isolated transaction.

### Repository Pattern

Repositories follow the same port-and-adapter pattern as the API project:

**Domain Layer (Port):**
```python
from abc import ABC, abstractmethod

class PaymentRepository(ABC):
    @abstractmethod
    def find_driver_by_id(self, driver_id: uuid.UUID) -> DriverEntity | None:
        pass

    @abstractmethod
    def create_payment(self, dto: ProcessPaymentDto) -> PaymentEntity:
        pass
```

**Infrastructure Layer (Adapter):**
```python
class PostgresPaymentRepository(PaymentRepository):
    def __init__(self, db: Session):
        self.db = db

    def find_driver_by_id(self, driver_id: uuid.UUID) -> DriverEntity | None:
        return self.db.query(DriverEntity).filter(
            DriverEntity.id == driver_id
        ).first()

    def create_payment(self, dto: ProcessPaymentDto) -> PaymentEntity:
        payment = PaymentEntity(
            driver_id=dto.driver_id,
            amount=dto.amount
        )
        self.db.add(payment)
        self.db.flush()
        return payment
```

### Entity Management

The project uses the shared library `voltop-common-structure` providing:

| Entity Type | Purpose |
|-------------|---------|
| **Domain Entities** | Pure Python classes for business logic (e.g., `DriverDomainEntity`) |
| **Infrastructure Entities** | SQLAlchemy models with relationships (e.g., `DriverEntity`, `PaymentEntity`) |

## Error Handling

### OutputContext in Task Context

Interactors return `OutputSuccessContext` or `OutputErrorContext`. In the task adapter, an `OutputErrorContext` is translated into a task retry or failure:

```python
@shared_task(bind=True, name="process_payment", max_retries=3)
def process_payment_task(self, driver_id: str, amount: float):
    db = get_task_session()
    try:
        interactor = ProcessPaymentInteractor(
            repository=PostgresPaymentRepository(db),
            logger=LoggerService()
        )
        result = interactor.run(ProcessPaymentDto(driver_id=driver_id, amount=amount))

        if isinstance(result, OutputErrorContext):
            raise TaskProcessingError(result.message)

        db.commit()
    except TaskProcessingError as exc:
        db.rollback()
        raise self.retry(exc=exc)
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### Retry with Exponential Backoff

Failed tasks are retried with exponential backoff to avoid overwhelming downstream services:

```python
@shared_task(
    bind=True,
    name="sync_external_data",
    max_retries=5,
    default_retry_delay=30,
)
def sync_external_data_task(self, source_id: str):
    db = get_task_session()
    try:
        # ... interactor invocation ...
        db.commit()
    except Exception as exc:
        db.rollback()
        # Exponential backoff: 30s, 60s, 120s, 240s, 480s
        retry_delay = self.default_retry_delay * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    finally:
        db.close()
```

### Dead Letter Handling

When a task exhausts all retries, it is logged and optionally stored for manual review:

```python
except self.MaxRetriesExceededError:
    db.rollback()
    logger.critical(
        f"Task permanently failed for payment_id={payment_id}. "
        "Moving to dead letter queue."
    )
    # Optionally store in a failed_tasks table
```

### Transaction Management

Transactions are explicit and bounded per task:

- A single `commit()` at the end of successful processing
- `rollback()` on any error before retrying
- `close()` in `finally` to release the session

For batch operations within a single task, the entire batch is committed atomically:

```python
@shared_task(bind=True, name="batch_process")
def batch_process_task(self, items: list[dict]):
    db = get_task_session()
    try:
        interactor = BatchProcessInteractor(
            repository=PostgresBatchRepository(db),
            logger=LoggerService()
        )
        for item in items:
            result = interactor.run(BatchItemDto(**item))
            if isinstance(result, OutputErrorContext):
                db.rollback()
                raise TaskProcessingError(result.message)

        db.commit()  # Atomic commit for entire batch
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

## Dependency Injection

In the Celery context, there is no FastAPI `Depends()` mechanism. Dependencies are wired either directly in the task function or through factory functions in `*_depends.py`.

### Direct Wiring in Task

```python
@shared_task(bind=True, name="process_payment")
def process_payment_task(self, driver_id: str, amount: float):
    db = get_task_session()
    try:
        interactor = ProcessPaymentInteractor(
            repository=PostgresPaymentRepository(db),
            notification_service=EmailNotificationService(),
            logger=LoggerService()
        )
        result = interactor.run(ProcessPaymentDto(driver_id=driver_id, amount=amount))
        db.commit()
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### Factory Function Pattern

For reusable wiring, factory functions centralize dependency construction:

```python
# infrastructure/payment_depends.py
def process_payment_interactor_factory(db: Session) -> ProcessPaymentInteractor:
    return ProcessPaymentInteractor(
        repository=PostgresPaymentRepository(db),
        notification_service=EmailNotificationService(),
        logger=LoggerService()
    )

# infrastructure/tasks/payment_tasks.py
@shared_task(bind=True, name="process_payment")
def process_payment_task(self, driver_id: str, amount: float):
    db = get_task_session()
    try:
        interactor = process_payment_interactor_factory(db)
        result = interactor.run(ProcessPaymentDto(driver_id=driver_id, amount=amount))
        db.commit()
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

The key principle remains: interactors declare dependencies using domain interfaces (ABC). The task function or factory wires concrete implementations. The application layer has zero knowledge of Celery or infrastructure details.

## Testing Strategy

### Unit Tests for Interactors

Interactors are tested in isolation with mocked repositories, identical to the API project:

```python
@pytest.fixture
def mock_repository(mocker):
    return mocker.Mock(spec=PaymentRepository)

def test_process_payment_success(mock_repository):
    # Arrange
    dto = ProcessPaymentDto(driver_id=uuid.uuid4(), amount=150.00)
    mock_repository.find_driver_by_id.return_value = MagicMock()
    mock_repository.create_payment.return_value = PaymentEntity(
        id=uuid.uuid4(), driver_id=dto.driver_id, amount=dto.amount
    )

    interactor = ProcessPaymentInteractor(mock_repository, LoggerService())

    # Act
    result = interactor.run(dto)

    # Assert
    assert isinstance(result, OutputSuccessContext)
    mock_repository.create_payment.assert_called_once()

def test_process_payment_driver_not_found(mock_repository):
    # Arrange
    dto = ProcessPaymentDto(driver_id=uuid.uuid4(), amount=150.00)
    mock_repository.find_driver_by_id.return_value = None

    interactor = ProcessPaymentInteractor(mock_repository, LoggerService())

    # Act
    result = interactor.run(dto)

    # Assert
    assert isinstance(result, OutputErrorContext)
    mock_repository.create_payment.assert_not_called()
```

### Unit Tests for Task Functions

Task functions are tested by mocking the interactor and verifying the session lifecycle:

```python
@pytest.fixture
def mock_session(mocker):
    session = mocker.MagicMock()
    mocker.patch('src.payments.infrastructure.tasks.payment_tasks.get_task_session', return_value=session)
    return session

def test_task_commits_on_success(mock_session, mocker):
    # Arrange
    mock_interactor = mocker.MagicMock()
    mock_interactor.run.return_value = OutputSuccessContext(data=[])
    mocker.patch(
        'src.payments.infrastructure.tasks.payment_tasks.ProcessPaymentInteractor',
        return_value=mock_interactor
    )

    # Act
    process_payment_task(driver_id=str(uuid.uuid4()), amount=100.00)

    # Assert
    mock_session.commit.assert_called_once()
    mock_session.rollback.assert_not_called()
    mock_session.close.assert_called_once()

def test_task_rollbacks_on_error(mock_session, mocker):
    # Arrange
    mock_interactor = mocker.MagicMock()
    mock_interactor.run.side_effect = Exception("DB error")
    mocker.patch(
        'src.payments.infrastructure.tasks.payment_tasks.ProcessPaymentInteractor',
        return_value=mock_interactor
    )

    # Act & Assert
    with pytest.raises(Exception):
        process_payment_task(driver_id=str(uuid.uuid4()), amount=100.00)

    mock_session.rollback.assert_called_once()
    mock_session.close.assert_called_once()
```

### Integration Tests

Integration tests verify task execution against a real test database and a test Celery worker:

- Use `celery.contrib.pytest` fixtures for worker setup
- Test with `CELERY_ALWAYS_EAGER=True` for synchronous execution in tests
- Verify database state changes after task completion

### Test Structure

Tests mirror the `src/` folder structure:

```
tests/
    {domain}/
        application/
            test_process_payment_interactor.py
        infrastructure/
            tasks/
                test_payment_tasks.py
            repositories/
                test_postgres_payment_repository.py
```

### Coverage Target

The project targets **>80% code coverage** across all layers:
- Interactor unit tests with mocked dependencies
- Task function tests verifying session lifecycle (commit/rollback/close)
- Repository integration tests against a test database

### Testing Principles

- Interactors are tested identically whether invoked from HTTP or Celery context
- Task functions are tested for session management (commit, rollback, close) and retry behavior
- External dependencies (databases, message brokers, APIs) are mocked in unit tests
- Use pytest fixtures for common test data setup
- Test both success and error/retry scenarios
