# API Patterns

This document describes the patterns for defining Celery tasks, handling input/output, configuring retry policies, managing errors, and naming conventions in the Python Celery worker project.

## Endpoint Design

In the Celery context, **tasks replace HTTP endpoints** as the entry points into the system. Each task is a thin infrastructure adapter that wires dependencies, delegates to an interactor, and manages the task lifecycle (session, transactions, retries).

### Task Definition Pattern

```python
from celery import shared_task

@shared_task(
    bind=True,
    name="process_driver_payment",
    max_retries=3,
    default_retry_delay=60,
    acks_late=True,
)
def process_driver_payment_task(self, driver_id: str, amount: float):
    """
    Process a driver payment.

    Args:
        driver_id: UUID of the driver as string
        amount: Payment amount
    """
    db = get_task_session()
    try:
        interactor = ProcessDriverPaymentInteractor(
            repository=PostgresPaymentRepository(db),
            logger=LoggerService()
        )
        dto = ProcessPaymentDto(driver_id=driver_id, amount=amount)
        result = interactor.run(dto)

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

### Key Task Configuration Options

| Option | Purpose | Typical Value |
|--------|---------|---------------|
| `bind=True` | Provides access to `self` for retry/state management | Always `True` |
| `name` | Explicit task name for queue routing | `"action_entity"` |
| `max_retries` | Maximum number of retry attempts | 3-5 |
| `default_retry_delay` | Seconds between retries (base) | 60 |
| `acks_late` | Acknowledge after execution (not before) | `True` for reliability |
| `time_limit` | Hard timeout in seconds | Depends on task complexity |
| `soft_time_limit` | Soft timeout (raises `SoftTimeLimitExceeded`) | Slightly less than `time_limit` |

### Periodic Tasks (Beat Scheduler)

Periodic tasks use the Celery beat scheduler for cron-like scheduling:

```python
from celery.schedules import crontab

app.conf.beat_schedule = {
    'generate-daily-reports': {
        'task': 'generate_daily_reports',
        'schedule': crontab(hour=2, minute=0),  # Every day at 2:00 AM
        'args': (),
    },
    'sync-vehicle-telemetry': {
        'task': 'sync_vehicle_telemetry',
        'schedule': crontab(minute='*/15'),  # Every 15 minutes
        'args': (),
    },
}
```

### Task Invocation

Tasks are invoked asynchronously from the API or other tasks:

```python
# From an API route or another service
process_driver_payment_task.delay(driver_id=str(driver.id), amount=150.00)

# With explicit options
process_driver_payment_task.apply_async(
    args=[str(driver.id), 150.00],
    countdown=30,           # Delay execution by 30 seconds
    queue='payments',       # Route to specific queue
    priority=5,             # Task priority (0-9, lower = higher priority)
)
```

## DTOs (Data Transfer Objects)

DTOs are used for data flow between the task adapter and the interactor. They are defined in the domain layer (`domain/*_dto.py`) and validated with Pydantic.

### Task Input Serialization

Celery task arguments must be JSON-serializable. Complex objects are passed as primitive types (strings, numbers, dicts) and reconstructed into DTOs inside the task function:

```python
@shared_task(bind=True, name="create_driver_report")
def create_driver_report_task(self, driver_id: str, report_type: str, date_from: str, date_to: str):
    """Task receives primitives, constructs DTO internally."""
    db = get_task_session()
    try:
        dto = CreateReportDto(
            driver_id=uuid.UUID(driver_id),
            report_type=report_type,
            date_from=datetime.fromisoformat(date_from),
            date_to=datetime.fromisoformat(date_to),
        )
        interactor = CreateDriverReportInteractor(
            repository=PostgresReportRepository(db),
            file_storage=S3Client(),
            logger=LoggerService()
        )
        result = interactor.run(dto)

        if isinstance(result, OutputErrorContext):
            raise TaskProcessingError(result.message)

        db.commit()
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### DTO Categories

| Category | Purpose | Example |
|----------|---------|---------|
| **Task Input DTOs** | Data passed to interactors from tasks | `ProcessPaymentDto` |
| **Task Output DTOs** | Data returned or stored by interactors | `PaymentResultDto` |
| **Entity DTOs** | Data for repository operations | `UpdatePaymentStatusDto` |

Task-specific DTOs may differ from API-specific DTOs when the input shape differs between HTTP and async task contexts.

## Dependency Injection

In the Celery context, there is no HTTP request scope. Dependencies are wired inside the task function itself, following the same factory pattern as the API project:

```python
@shared_task(bind=True, name="process_payment")
def process_payment_task(self, driver_id: str, amount: float):
    db = get_task_session()  # Session scoped to this task execution
    try:
        # Wire concrete implementations to abstract interfaces
        interactor = ProcessPaymentInteractor(
            repository=PostgresPaymentRepository(db),   # Concrete -> abstract
            notification_service=EmailNotificationService(),  # Concrete -> abstract
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

Alternatively, factory functions in `*_depends.py` can centralize wiring:

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

## Security (Authentication & Authorization)

Celery tasks do not handle HTTP authentication or authorization directly. Security concerns in the worker context include:

- **Input validation** -- All task arguments are validated through Pydantic DTOs before processing
- **SQL injection prevention** -- SQLAlchemy ORM is used exclusively; raw SQL string interpolation is prohibited
- **Credential management** -- Database URLs, API keys, and secrets are loaded from environment variables, never hardcoded
- **Sensitive data in logs** -- Passwords, tokens, and PII are never logged; task arguments containing sensitive data are masked
- **Message integrity** -- The message broker (Redis/RabbitMQ) connection is secured with authentication and TLS where applicable

## Database Patterns

### Session Management (Per-Task Scoping)

Database sessions are scoped to individual task executions, not shared across tasks:

```python
from sqlalchemy.orm import sessionmaker, scoped_session

TaskSession = sessionmaker(bind=engine)

def get_task_session() -> Session:
    """Create a new session scoped to the current task execution."""
    return TaskSession()
```

Each task function follows this lifecycle:
1. Create session at task start
2. Pass session to repository constructors
3. Commit on success
4. Rollback on failure
5. Close session in `finally` block (always)

### Transaction Management

Transactions are explicitly managed within task functions:

```python
@shared_task(bind=True, name="batch_update_drivers")
def batch_update_drivers_task(self, driver_updates: list[dict]):
    db = get_task_session()
    try:
        interactor = BatchUpdateDriversInteractor(
            repository=PostgresDriverRepository(db),
            logger=LoggerService()
        )
        result = interactor.run(BatchUpdateDto(updates=driver_updates))

        if isinstance(result, OutputErrorContext):
            db.rollback()
            raise TaskProcessingError(result.message)

        db.commit()  # Commit only on success
    except TaskProcessingError as exc:
        db.rollback()
        raise self.retry(exc=exc)
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### Error Handling in Async Tasks

#### Retry with Exponential Backoff

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
        interactor = SyncExternalDataInteractor(
            repository=PostgresDataRepository(db),
            external_client=ExternalApiClient(),
            logger=LoggerService()
        )
        result = interactor.run(SyncDataDto(source_id=source_id))

        if isinstance(result, OutputErrorContext):
            raise TaskProcessingError(result.message)

        db.commit()
    except TaskProcessingError as exc:
        db.rollback()
        # Exponential backoff: 30s, 60s, 120s, 240s, 480s
        retry_delay = self.default_retry_delay * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    except Exception as exc:
        db.rollback()
        retry_delay = self.default_retry_delay * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    finally:
        db.close()
```

#### Dead Letter Handling

When a task exhausts all retries (`MaxRetriesExceededError`), it should be logged and optionally routed to a dead letter queue for manual inspection:

```python
@shared_task(
    bind=True,
    name="process_critical_payment",
    max_retries=3,
)
def process_critical_payment_task(self, payment_id: str):
    db = get_task_session()
    try:
        # ... interactor logic ...
        db.commit()
    except self.MaxRetriesExceededError:
        db.rollback()
        logger.critical(
            f"Task process_critical_payment permanently failed for payment_id={payment_id}. "
            "Moving to dead letter queue."
        )
        # Optionally store in a failed_tasks table for manual review
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### Alembic Migrations

Database schema changes follow the same Alembic migration patterns as the API project:

```bash
alembic revision --autogenerate -m "description"
alembic revision -m "description"
```

Migration best practices:
- One logical change per migration
- Always implement `downgrade()` for reversibility
- Use transactions and backup data before destructive changes

### Database Indexing

The same indexing guidelines from the API project apply. Key points:
- Maximum 3 indexes when creating a table (including UNIQUE constraints)
- Index only columns with high cardinality that are frequently filtered
- Compound indexes follow the leftmost prefix rule
- Do not index low-cardinality columns (`status`, `boolean` flags)
- Add indexes later based on evidence from slow query logs

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Task function | `{action}_{entity}_task` | `process_driver_payment_task` |
| Task file | `*_tasks.py` | `payment_tasks.py` |
| Interactor | `{Action}{Entity}Interactor` | `ProcessDriverPaymentInteractor` |
| DTO | `{Entity}{Purpose}Dto` | `ProcessPaymentDto` |
| Repository interface | `{Entity}Repository` | `PaymentRepository` |
| Repository implementation | `Postgres{Entity}Repository` | `PostgresPaymentRepository` |
| Dependency factory | `*_depends.py` | `payment_depends.py` |
| Celery task name (string) | `"action_entity"` | `"process_driver_payment"` |
