# API Patterns

This document describes the public API design, type hint requirements, documentation standards, error handling, and versioning practices for internal Python libraries.

## Endpoint Design

Internal Python libraries do not have HTTP endpoints. The "API" is the set of Python classes, methods, and functions exported for consumers to use. The public API surface is defined explicitly through `__init__.py` exports.

## DTOs (Data Transfer Objects)

DTOs handle data flow between layers. They are defined in the domain layer (`domain/*_dto.py`) and validated with Pydantic.

### DTO Categories

| Category | Purpose | Example |
|----------|---------|---------|
| **Input DTOs** | Data passed to interactors/repositories | `CreateDriverDto` |
| **Output DTOs** | Data returned from interactors | `DriverResponseDto` |
| **Criteria DTOs** | Filter/query parameters | `FindDriverCriteria` |

### Documentation for DTOs

Pydantic DTOs and data classes are self-documenting via type hints. A one-line class docstring is sufficient:

```python
# Sufficient -- fields are self-documenting
class CreateDriverDto(BaseDto):
    """DTO for driver creation."""
    email: str
    name: str
    phone: Optional[str] = None

# Also sufficient for criteria/filter classes
class FindDriverCriteria(BaseModel):
    """Criteria for searching drivers."""
    id: Optional[str] = None
    email: Optional[str] = None
    active: Optional[bool] = None
```

Comprehensive Args/Returns docstrings on data class fields are not required.

## Dependency Injection

Libraries use constructor injection for all dependencies. Interactors receive their dependencies (repositories, services) as constructor parameters typed with domain interfaces (ABC), not concrete implementations.

```python
# CORRECT: Depends on abstraction
class CreateDriverInteractor:
    def __init__(self, repository: DriverRepository):  # Interface
        self.repository = repository

# INCORRECT: Depends on concrete implementation
class CreateDriverInteractor:
    def __init__(self, repository: PostgresDriverRepository):  # Concrete
        self.repository = repository
```

The consumer of the library is responsible for wiring concrete implementations when instantiating interactors.

## Security (Authentication & Authorization)

### Library-Level Security

Libraries do not handle HTTP authentication or authorization (that is the responsibility of the consuming application). Library-level security concerns include:

**Input Validation:**
```python
# CORRECT: Validate inputs
def create_user(email: str) -> User:
    if not validate_email_format(email):
        raise ValueError("Invalid email format")
    if len(email) > 255:
        raise ValueError("Email too long")
    return User(email=sanitize_email(email))
```

**SQL Injection Prevention:**
```python
# CORRECT: Use SQLAlchemy ORM (parameterized queries)
query = session.query(Driver).filter(Driver.email == email)

# FORBIDDEN: String interpolation in SQL
query = f"SELECT * FROM drivers WHERE email = '{email}'"
```

**Credential Management:**
- Environment variables or `.env` files for configuration
- No hardcoded credentials in source code
- Sensitive data (passwords, tokens, PII) is never logged

**Logging:**
```python
# CORRECT: Use logging module
import logging
logger = logging.getLogger(__name__)
logger.info(f"User login: {username}")

# FORBIDDEN: print() for output in libraries
print(f"Error: {e}")

# FORBIDDEN: Logging sensitive data
logger.info(f"User login: {username} with password {password}")
```

## Database Patterns

### ORM

SQLAlchemy with PostgreSQL is the standard ORM. MongoEngine is used for MongoDB where applicable.

### Performance

```python
# CORRECT: Eager loading to prevent N+1 queries
def get_drivers_with_vehicles(self) -> List[DriverEntity]:
    return self.session.query(DriverEntity).options(
        joinedload(DriverEntity.vehicle)
    ).all()

# INCORRECT: N+1 query pattern
def get_drivers_with_vehicles(self) -> List[DriverEntity]:
    drivers = self.session.query(DriverEntity).all()
    for driver in drivers:
        vehicle = self.session.query(VehicleEntity).filter(
            VehicleEntity.driver_id == driver.id
        ).first()
        driver.vehicle = vehicle
    return drivers
```

```python
# CORRECT: Pagination/streaming for large datasets
def export_all_drivers(self, batch_size: int = 1000):
    offset = 0
    while True:
        batch = self.session.query(DriverEntity).offset(offset).limit(batch_size).all()
        if not batch:
            break
        for driver in batch:
            yield driver.dict()
        offset += batch_size

# INCORRECT: Loading all records into memory
def export_all_drivers(self) -> List[Dict]:
    drivers = self.session.query(DriverEntity).all()  # Could be millions
    return [driver.dict() for driver in drivers]
```

### Database Indexing

When defining entities or migrations that include indexes:

**Correct indexing:**
- UNIQUE index for business constraints (`idempotency_key`, `email`, `ticket_number`)
- Index on FK columns used in frequent WHERE/JOIN (only if not covered by a compound)
- Compound index for frequent multi-column queries, ordered by descending selectivity
- Compound index following leftmost prefix rule: `(A, B, C)` covers `A`, `A+B`, `A+B+C`

**Incorrect indexing:**
- Index on low cardinality column (`status` with 6 values, `boolean` flags)
- Redundant index covered by an existing compound index
- More than 3 indexes at table creation without justification
- Compound index with more than 4 columns

```python
# CORRECT indexing
class PaymentEntity(Base):
    __tablename__ = 'payments'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    idempotency_key = Column(String(255), unique=True, nullable=False)  # UNIQUE business constraint
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    status = Column(String(50), nullable=False)  # No index -- low cardinality

# INCORRECT: index on low cardinality column
status = Column(String(50), nullable=False, index=True)  # Only 6 values
```

## Public API Surface

### Explicit Exports

All public classes and functions are exported in `__init__.py` with an explicit `__all__` list:

```python
# your_library_name/__init__.py
from .domain.driver_repository import DriverRepository
from .domain.driver_dto import CreateDriverDto, UpdateDriverDto
from .infrastructure.repositories.postgres_driver_repository import PostgresDriverRepository

__all__ = [
    "DriverRepository",
    "CreateDriverDto",
    "UpdateDriverDto",
    "PostgresDriverRepository",
]
```

Rules:
- All public classes/functions are exported in `__init__.py`
- Internal modules are prefixed with `_` if not meant to be public
- Clear separation between public API and internal implementation
- Avoid exporting too much (polluting namespace)

### Type Hints on Public API

All public methods require complete type hints and docstrings with Args/Returns/Raises:

```python
from typing import Optional, List
from uuid import UUID

class DriverRepository(ABC):
    @abstractmethod
    def find_by_email(self, email: str) -> Optional[DriverEntity]:
        """
        Find driver by email address.

        Args:
            email: Driver's email address

        Returns:
            DriverEntity if found, None otherwise
        """
        pass

    @abstractmethod
    def find_many_by_status(
        self,
        status: str,
        limit: int = 100
    ) -> List[DriverEntity]:
        """
        Find drivers by status with optional limit.

        Args:
            status: Driver status to filter by
            limit: Maximum number of results (default: 100)

        Returns:
            List of DriverEntity matching the status
        """
        pass
```

### Documentation Requirements

**Required (complete docstrings with Args/Returns/Raises):**
- Abstract methods in domain ports/interfaces
- Public methods with business logic in interactors
- Public repository interface methods

**Not required (one-line class docstring sufficient):**
- Pydantic DTOs/Entities (self-documenting via type hints)
- Value Objects / Criteria classes
- MongoEngine/SQLAlchemy Documents/Models
- Mapper stub methods that return None

### Backwards Compatibility

Public API changes follow strict backwards compatibility rules:

```python
# CORRECT: Maintaining backwards compatibility with deprecation
class DriverRepository(ABC):
    @deprecated("Use find_one_by_email instead. Will be removed in v9.0.0")
    def find_by_email(self, email: str) -> Optional[DriverEntity]:
        return self.find_one_by_email(email)

    def find_one_by_email(self, email: str) -> Optional[DriverEntity]:
        pass

# INCORRECT: Breaking change without deprecation
class DriverRepository(ABC):
    # Removed old method, added new with different name
    def find_by_email_address(self, email: str, validate: bool = True):
        pass
```

Rules:
- Breaking changes are documented in PR description
- Deprecated methods use `@deprecated` decorator with removal version
- New major version required for breaking changes (e.g., v8.x -> v9.0.0)
- Migration guide provided for breaking changes
- Breaking public API in minor/patch versions is prohibited
- Backwards compatibility aliases (e.g., `OldName = NewName`) are not breaking changes and require only a minor version bump

### Interface Stability

Changes to public interfaces are validated for:
- **Method signature changes** -- Adding required parameters is a breaking change; adding optional parameters with defaults is not
- **Return type changes** -- Changing return types is a breaking change
- **Exception changes** -- Throwing new exception types is a breaking change for existing exception handling

## Naming Conventions

| Component | File Pattern | Example |
|-----------|-------------|---------|
| Interactor | `*_interactor.py` | `create_driver_interactor.py` |
| Repository interface | `*_repository.py` | `driver_repository.py` |
| Repository implementation | `postgres_*_repository.py` | `postgres_driver_repository.py` |
| DTO | `*_dto.py` | `driver_dto.py` |
| Entity (domain) | `*_entity.py` or in `entities/` | `driver_entity.py` |

## Error Handling

### Library-Specific Error Handling

```python
# CORRECT: Proper error handling with custom exceptions and chaining
class PostgresDriverRepository:
    def find_one_by_email(self, email: str) -> Optional[DriverEntity]:
        """Find driver by email, returns None if not found."""
        try:
            return self.session.query(DriverEntity).filter(
                DriverEntity.email == email
            ).first()
        except SQLAlchemyError as e:
            logger.error(f"Database error finding driver by email: {e}")
            raise RepositoryError(f"Failed to find driver: {email}") from e

    def create_one(self, dto: CreateDriverDto) -> DriverEntity:
        """Create driver, raises RepositoryError on failure."""
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
```

Requirements:
- Custom exception classes defined for each library
- Exception chaining with `raise ... from e`
- Errors logged with context using the `logging` module
- Exceptions documented in docstrings (Raises section)
- Unexpected errors allowed to bubble up (no blind `except Exception`)
- Bare `except:` clauses are prohibited
- Silent error suppression is prohibited
- `print()` is prohibited for error output (use `logging`)
