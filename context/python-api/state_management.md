# State Management

This document describes how state flows through the Python API project: the interactor pattern for use case orchestration, the repository pattern for data access, entity management, error handling, and testing strategies.

## State Pattern

### Interactor Pattern (Use Cases)

All business logic is implemented through interactors that follow a strict validate-then-process flow. Each interactor handles exactly one use case.

#### Structure

```python
class SomeInteractor(BaseInteractor):
    def __init__(self, repository: SomeRepository, file_storage: FileStorageService, logger: LoggerService):
        BaseInteractor.__init__(self)
        self.repository = repository        # Domain interface (ABC), NOT concrete implementation
        self.file_storage = file_storage    # Domain interface (ABC), NOT concrete implementation
        self.logger = logger

    def validate(self, input_dto: SomeDto) -> bool | OutputErrorContext:
        # Validation logic
        # Return True if valid, OutputErrorContext if invalid
        pass

    def process(self, input_dto: SomeDto) -> OutputSuccessContext | OutputErrorContext:
        # Business logic implementation
        # Return OutputSuccessContext on success, OutputErrorContext on error
        pass
```

#### BaseInteractor

The `run()` and `run_async()` methods are inherited from `BaseInteractor` and orchestrate the flow:

1. Call `validate(input_dto)` -- returns `True` or `OutputErrorContext`
2. If validation fails, return the `OutputErrorContext` immediately
3. If validation passes, call `process(input_dto)` -- returns `OutputSuccessContext` or `OutputErrorContext`

This is the **Template Method** pattern: the base class defines the algorithm skeleton, and subclasses provide the specific validation and processing logic.

#### Constructor Rule

All constructor type hints in interactors use **domain abstractions** (ABC interfaces). Concrete infrastructure classes are never referenced. This applies to:
- Repositories
- File storage services
- Email services
- Excel processors
- External API clients
- Any other infrastructure concern

## Data Flow

### Request Lifecycle

```
HTTP Request
    -> Route (authentication, authorization, input parsing)
        -> Interactor.run(dto) [inherited from BaseInteractor]
            -> validate(dto) -> True | OutputErrorContext
            -> process(dto)  -> OutputSuccessContext | OutputErrorContext
        -> create_api_response(result)
    -> HTTP Response
```

### Repository Pattern (Ports and Adapters)

Repositories define abstract interfaces in the domain layer (ports) and implement them in the infrastructure layer (adapters).

**Domain Layer (Port):**
```python
from abc import ABC, abstractmethod

class SomeRepository(ABC):
    @abstractmethod
    def find_one_by_id(self, entity_id: uuid.UUID) -> SomeEntity | None:
        pass

    @abstractmethod
    def create(self, dto: SomeDto) -> SomeEntity:
        pass
```

**Infrastructure Layer (Adapter):**
```python
class PostgresSomeRepository(SomeRepository):
    def find_one_by_id(self, entity_id: uuid.UUID) -> SomeEntity | None:
        # SQLAlchemy implementation
        pass

    def create(self, dto: SomeDto) -> SomeEntity:
        # SQLAlchemy implementation
        pass
```

### Infrastructure Service Interfaces

Beyond data access, infrastructure services (file storage, email, Excel processing, external APIs) follow the same port-and-adapter pattern:

**Domain Layer (Port):**
```python
from abc import ABC, abstractmethod

class FileStorageService(ABC):
    """Interface for file storage operations."""

    @abstractmethod
    def upload_file(self, content: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
        pass

    @abstractmethod
    def download_file(self, key: str) -> bytes:
        pass

    @abstractmethod
    def delete_file(self, key: str) -> None:
        pass
```

**Infrastructure Layer (Adapter):**
```python
class S3Client(FileStorageService):
    """AWS S3 implementation of FileStorageService."""

    def upload_file(self, content: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
        # boto3 implementation
        pass
```

### Entity Management

The project uses a shared library `voltop-common-structure` that provides two types of entities:

| Entity Type | Location | Purpose |
|-------------|----------|---------|
| **Domain Entities** | `voltop-common-structure` | Pure Python classes for business logic (e.g., `DriverDomainEntity`) |
| **Infrastructure Entities** | `voltop-common-structure` | SQLAlchemy models with relationships (e.g., `DriverEntity`) |

Additional shared resources from `voltop-common-structure`:
- Base repositories with common CRUD operations
- Shared DTOs and enums

New entities and repositories should be checked against `voltop-common-structure` before being created locally.

## Error Handling

### OutputContext Pattern

Interactors return one of two context types:

- `OutputSuccessContext` -- success with data
- `OutputErrorContext` -- error with HTTP status, code, message, and description

Error messages use i18n (internationalization) via the translate service:

```python
def validate(self, input_dto: CreateDriverDto) -> bool | OutputErrorContext:
    existing_driver = self.repository.find_one_by_email(input_dto.email)
    if existing_driver:
        return OutputErrorContext(
            http_status=status.HTTP_409_CONFLICT,
            code=self.translate.text('api.errors.duplicate_entity.code'),
            message=self.translate.text('api.errors.duplicate_entity.message', entity='driver'),
            description=self.translate.text('api.errors.duplicate_entity.description')
        )
    return True
```

### Error Handling Rules

- All exceptions are caught and returned as `OutputErrorContext`
- Multiple DB operations are wrapped in transactions
- Errors are logged via `LoggerService`
- Sensitive data (passwords, tokens, PII) is never included in error messages or logs

## Dependency Injection

Dependencies are configured in `*_depends.py` factory functions and injected through FastAPI's `Depends()` mechanism.

```python
def some_interactor_depends(db: Session = Depends(get_db)) -> SomeInteractor:
    return SomeInteractor(
        repository=PostgresSomeRepository(db),  # Concrete repo -> abstract SomeRepository
        file_storage=S3Client(),                # Concrete service -> abstract FileStorageService
        logger=LoggerService()
    )
```

The factory function is the only place where concrete implementations are instantiated. Interactors declare all dependencies using domain interfaces (ABC), ensuring zero knowledge of infrastructure details.

## Testing Strategy

### Test Structure

Tests mirror the `src/` folder structure in a `tests/` directory.

### Unit Tests

Unit tests verify interactors in isolation with mocked repositories and services:

```python
@pytest.fixture
def mock_repository(mocker):
    return mocker.Mock(spec=DriverRepository)

def test_create_driver_success(mock_repository):
    # Arrange
    dto = CreateDriverDto(email="test@example.com", name="Test Driver")
    mock_repository.find_one_by_email.return_value = None
    mock_repository.create.return_value = DriverEntity(id=uuid.uuid4(), **dto.dict())

    interactor = CreateDriverInteractor(mock_repository, TranslateService(), LoggerService())

    # Act
    result = interactor.run(dto)

    # Assert
    assert isinstance(result, OutputSuccessContext)
    assert result.http_status == status.HTTP_201_CREATED
    mock_repository.create.assert_called_once()
```

### Integration Tests

Integration tests verify repository implementations against a test database.

### Test Tools

| Tool | Purpose |
|------|---------|
| **pytest** | Test framework with async support |
| **pytest-mock** | Mocking library for external dependencies |
| **faker** | Test data generation |

### Coverage Target

The project targets **>80% code coverage** across all layers.

### Testing Principles

- Test interactors in isolation with mocked dependencies
- Test repositories against a test database
- Use pytest fixtures for common test data setup
- Mock all external dependencies (databases, APIs, file storage)
- Test both success and error scenarios
- Verify that mocked methods are called with expected arguments
