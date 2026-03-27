# State Management

This document describes testing strategy, layer separation, interface stability, and data flow patterns for internal Python libraries.

## State Pattern

### Interactor Pattern

Libraries use interactors to encapsulate use cases. Each interactor handles one business operation and produces an `OutputContext` result:

- `OutputSuccessContext` -- operation succeeded with data
- `OutputErrorContext` -- operation failed with error details

Interactors receive dependencies through constructor injection, typed with domain interfaces (ABC):

```python
class CreateDriverInteractor:
    def __init__(self, repository: DriverRepository):  # Interface, not concrete
        self.repository = repository

    def process(self, dto: CreateDriverDto) -> OutputContext:
        driver = self.repository.create_one(dto)
        return OutputSuccessContext(data=[driver])
```

### Repository Pattern

Repositories define abstract interfaces in the domain layer and provide concrete implementations in the infrastructure layer:

**Domain Layer (Port):**
```python
from abc import ABC, abstractmethod
from typing import Optional

class DriverRepository(ABC):
    @abstractmethod
    def find_one_by_email(self, email: str) -> Optional[DriverEntity]:
        """Find driver by email address."""
        pass

    @abstractmethod
    def create_one(self, dto: CreateDriverDto) -> DriverEntity:
        """Create a new driver record."""
        pass
```

**Infrastructure Layer (Adapter):**
```python
class PostgresDriverRepository(DriverRepository):
    def __init__(self, session: Session):
        self.session = session

    def find_one_by_email(self, email: str) -> Optional[DriverEntity]:
        return self.session.query(DriverEntity).filter(
            DriverEntity.email == email
        ).first()
```

## Data Flow

### Layer Separation

The data flow follows strict layer boundaries:

```
Consumer Code
    -> Interactor (application layer, depends on domain interfaces only)
        -> Repository interface (domain layer, ABC)
            -> Repository implementation (infrastructure layer, SQLAlchemy)
                -> Database
```

**Hard constraints:**
- The domain layer never imports from infrastructure
- The application layer never imports from infrastructure
- Dependencies always point inward
- No circular dependencies between modules

### Interface Stability

Changes to public interfaces are tracked carefully because libraries are consumed by multiple projects:

**Method Signature Stability:**
```python
# Adding optional parameter with default is safe (backwards compatible)
def create_driver(
    self,
    dto: CreateDriverDto,
    validate: bool = True  # Optional with default
) -> DriverEntity:
    pass

# Changing return type is a breaking change
# Before: List[DriverEntity]
# After: Dict[str, DriverEntity]  -- breaks existing consumers
```

**Exception Stability:**
- Throwing new exception types that consumers do not handle is a breaking change
- Documented exceptions (in Raises section) form part of the public contract

## Error Handling

### Custom Exceptions

Libraries define custom exception classes for domain-specific errors:

```python
class RepositoryError(Exception):
    """Base error for repository operations."""
    pass

class DuplicateDriverError(RepositoryError):
    """Raised when attempting to create a driver with a duplicate email."""
    pass
```

### Error Handling Patterns

```python
# CORRECT: Exception chaining, specific catches, logging
def create_one(self, dto: CreateDriverDto) -> DriverEntity:
    try:
        driver = DriverEntity(**dto.dict())
        self.session.add(driver)
        self.session.flush()
        return driver
    except IntegrityError as e:
        logger.error(f"Integrity error creating driver: {e}")
        raise DuplicateDriverError(f"Driver with email {dto.email} already exists") from e
    except SQLAlchemyError as e:
        logger.error(f"Database error creating driver: {e}")
        raise RepositoryError("Failed to create driver") from e

# INCORRECT: Silent failure, bare except
def create_one(self, dto):
    try:
        driver = DriverEntity(**dto.dict())
        self.session.add(driver)
        return driver
    except:
        return None  # Silent failure -- consumer has no idea what happened
```

## Dependency Injection

Libraries use constructor injection. The consumer of the library wires concrete implementations:

```python
# Consumer code (in the application that uses this library)
from your_library import CreateDriverInteractor, PostgresDriverRepository

session = get_db_session()
repository = PostgresDriverRepository(session)
interactor = CreateDriverInteractor(repository=repository)

result = interactor.process(dto)
```

Within the library itself, interactors and services declare dependencies on domain interfaces, never on concrete implementations.

## Testing Strategy

### Coverage Requirements

| Scope | Coverage Target |
|-------|----------------|
| Public API (modified components) | > 90% |
| Internal/private logic | Recommended but not strictly required |
| Complex internal logic with edge cases | Required |

### Unit Tests for Public API

Every public method and function requires unit tests covering success and failure scenarios:

```python
class TestCreateDriverInteractor:
    """Tests for CreateDriverInteractor with mocked dependencies."""

    @pytest.fixture
    def repository_mock(self):
        """Mock repository to isolate interactor logic."""
        mock = MagicMock(spec=DriverRepository)
        mock.find_one_by_email.return_value = None
        return mock

    @pytest.fixture
    def interactor(self, repository_mock):
        """Interactor with injected mocks."""
        return CreateDriverInteractor(repository=repository_mock)

    def test_should_create_driver_when_email_not_exists(
        self, interactor, repository_mock
    ):
        # Arrange
        dto = CreateDriverDto(email="new@example.com", name="Test")
        expected_driver = DriverEntity(id=uuid.uuid4(), **dto.dict())
        repository_mock.create_one.return_value = expected_driver

        # Act
        result = interactor.process(dto)

        # Assert
        assert isinstance(result, OutputSuccessContext)
        assert result.http_status == 201
        assert len(result.data) == 1
        repository_mock.find_one_by_email.assert_called_once_with("new@example.com")
        repository_mock.create_one.assert_called_once()

    def test_should_return_error_when_email_exists(
        self, interactor, repository_mock
    ):
        # Arrange
        dto = CreateDriverDto(email="existing@example.com", name="Test")
        repository_mock.find_one_by_email.return_value = MagicMock()

        # Act
        result = interactor.process(dto)

        # Assert
        assert isinstance(result, OutputErrorContext)
        assert result.http_status == 409
        repository_mock.create_one.assert_not_called()
```

### Repository Tests

```python
class TestPostgresDriverRepository:
    """Tests for PostgresDriverRepository."""

    @pytest.fixture
    def repository(self, db_session):
        return PostgresDriverRepository(db_session)

    @pytest.fixture
    def valid_dto(self):
        return CreateDriverDto(
            email="test@example.com",
            name="Test Driver",
            cellphone="+573001234567"
        )

    def test_should_create_driver_successfully_when_valid_dto(
        self, repository, valid_dto
    ):
        result = repository.create_one(valid_dto)
        assert result.id is not None
        assert result.email == valid_dto.email

    def test_should_raise_error_when_duplicate_email(
        self, repository, valid_dto
    ):
        repository.create_one(valid_dto)
        with pytest.raises(DuplicateDriverError) as exc_info:
            repository.create_one(valid_dto)
        assert "already exists" in str(exc_info.value)

    def test_should_return_none_when_driver_not_found(self, repository):
        result = repository.find_one_by_email("nonexistent@example.com")
        assert result is None

    def test_should_handle_database_error_gracefully(
        self, repository, valid_dto, mocker
    ):
        mocker.patch.object(
            repository.session, 'add',
            side_effect=SQLAlchemyError("Database error")
        )
        with pytest.raises(RepositoryError) as exc_info:
            repository.create_one(valid_dto)
        assert "Failed to create" in str(exc_info.value)
```

### Test Naming Convention

Pattern: `test_should_{expected}_when_{condition}`

```
test_should_return_none_when_driver_not_found
test_should_raise_error_when_invalid_email
test_should_create_successfully_when_valid_dto
```

Avoid vague names like `test_driver_creation` or `test_find`.

### Test Directory Structure

Tests mirror the source structure:

```
tests/
    domain/
        test_driver_entity.py
        test_create_driver_dto.py
        test_driver_repository_interface.py
    application/
        test_create_driver_interactor.py
    infrastructure/
        test_postgres_driver_repository.py
        test_driver_mapper.py
```

### Test Isolation

Tests are independent and can run in any order:

```python
class TestDriverRepository:
    @pytest.fixture(autouse=True)
    def setup(self, db_session):
        """Clean up before each test."""
        db_session.query(DriverEntity).delete()
        db_session.commit()

    def test_create_driver(self, repository):
        dto = CreateDriverDto(email="test1@example.com")
        result = repository.create_one(dto)
        assert result.email == "test1@example.com"

    def test_find_driver(self, repository):
        # Independent of test_create_driver
        dto = CreateDriverDto(email="test2@example.com")
        repository.create_one(dto)
        result = repository.find_one_by_email("test2@example.com")
        assert result is not None
```

### Mocking Strategy

External dependencies (databases, APIs, services) are mocked in unit tests. Integration tests use a real test database.

```python
# Unit test: Mock repository to isolate interactor
@pytest.fixture
def repository_mock(self):
    mock = MagicMock(spec=DriverRepository)
    mock.find_one_by_email.return_value = None
    return mock

# Integration test: Use real repository against test database
@pytest.fixture
def repository(self, db_session):
    return PostgresDriverRepository(db_session)
```

### What NOT to Test

- HTTP integration tests (libraries have no routes)
- End-to-end tests (that is for consumers of the library)
- Performance tests (unless performance is a critical requirement)
- Trivial property getters, simple DTOs, and obvious logic
