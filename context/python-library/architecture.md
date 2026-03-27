# Architecture Overview

This document describes the architectural standards for internal Python libraries. All libraries are created from the company's standardized template and follow Hexagonal Architecture (Clean Architecture) as a mandatory requirement.

## Architectural Pattern

The project implements **Hexagonal Architecture** (Ports and Adapters) with **Clean Architecture** principles. Libraries are distributed as reusable Python packages consumed by multiple projects across the organization.

Key distinction from API projects: libraries have no HTTP routes. They expose a public API through Python interfaces and implementations, not REST endpoints.

## Layer Structure

### Domain Layer (`domain/`)
The innermost layer containing business rules. This layer has **zero dependencies** on infrastructure or external frameworks.

Contents:
- **Entities** (`entities/`) -- Domain entities with business behavior
- **DTOs** (`*_dto.py`) -- Data Transfer Objects for inter-layer communication, validated with Pydantic
- **Repository interfaces** (`*_repository.py`) -- Abstract Base Classes (ABC) defining data access contracts (ports)

### Application Layer (`application/`)
Contains use case orchestration via interactors. Depends only on the domain layer.

Contents:
- **Interactors** (`*_interactor.py`) -- Each interactor encapsulates one use case
- Output is expressed through `OutputContext`, `OutputSuccessContext`, and `OutputErrorContext`

### Infrastructure Layer (`infrastructure/`)
The outermost layer implementing domain interfaces with concrete technologies.

Contents:
- **Repositories** (`repositories/`) -- Concrete implementations of domain repository interfaces (e.g., PostgreSQL via SQLAlchemy)
- **Entities** (`entities/`) -- ORM entity definitions (SQLAlchemy models)
- **Mappers** (`mappers/`) -- DTO-to-Entity and Entity-to-DTO conversion logic

## Folder Structure

```
{library_name}/
    domain/                    # Business rules (no dependencies)
        entities/
        *_dto.py
        *_repository.py        # Interface (port)
    application/               # Use cases
        *_interactor.py
    infrastructure/            # Adapters
        repositories/          # Implementations
        entities/              # ORM entities
        mappers/               # DTO <-> Entity conversion
tests/
    domain/
    application/
    infrastructure/
```

### Required Files

Every library created from the company template includes:
- `setup.py` or `pyproject.toml` with semantic versioning
- `README.md` with installation and usage instructions
- `CHANGELOG.md` for version history
- `.gitignore` with Python and virtual environment exclusions
- `Pipfile` and `Pipfile.lock` (company standard package manager)
- `tests/` directory mirroring the source structure

### Required Dependencies (minimum)

- SQLAlchemy >= 1.4.0 (if the library uses database access)
- Pydantic >= 1.8.0 (for DTO validation)
- Alembic (if the library manages database migrations)

## Dependency Flow

Dependencies point strictly **inward**:

```
Infrastructure --> Application --> Domain
     (outer)        (middle)       (inner)
```

- **Domain** depends on nothing (pure Python, ABCs, standard library)
- **Application** depends on domain interfaces only
- **Infrastructure** depends on domain interfaces and implements them

The domain layer never imports from infrastructure. This is a hard constraint enforced through code review.

## Key Architectural Decisions

### Clean Architecture Compliance

```python
# CORRECT: Domain layer has no infrastructure imports
# domain/driver_repository.py
from abc import ABC, abstractmethod
from typing import Optional

class DriverRepository(ABC):
    @abstractmethod
    def find_one_by_email(self, email: str) -> Optional[DriverEntity]:
        pass

# VIOLATION: Domain importing infrastructure
from your_library_name.infrastructure.database import Session  # Forbidden in domain layer
```

Compliance checklist:
- Domain layer has no infrastructure imports
- Dependencies point inward (Dependency Inversion)
- Interactors orchestrate business logic
- Repositories implement port interfaces
- DTOs are used for data transfer between layers
- No circular dependencies between modules

### SOLID Principles

**Single Responsibility:**
```python
# CORRECT: One responsibility per class
class CreateDriverInteractor:
    def process(self, dto: CreateDriverDto) -> OutputContext:
        # Only handles driver creation logic
        pass

# VIOLATION: Multiple responsibilities in one class
class DriverManager:
    def create_driver(self, dto): pass
    def send_email(self, driver): pass
    def generate_report(self): pass
    def calculate_payments(self): pass
```

**Dependency Inversion:**
```python
# CORRECT: Depends on abstraction
class CreateDriverInteractor:
    def __init__(self, repository: DriverRepository):  # Interface
        self.repository = repository

# VIOLATION: Depends on concrete implementation
class CreateDriverInteractor:
    def __init__(self, repository: PostgresDriverRepository):  # Concrete
        self.repository = repository
```

**Open/Closed:**
```python
# CORRECT: Open for extension, closed for modification
class PaymentStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: Decimal) -> Decimal:
        pass

class PercentagePaymentStrategy(PaymentStrategy):
    def calculate(self, amount: Decimal) -> Decimal:
        return amount * Decimal("0.9")

# VIOLATION: Must modify class to add new behavior
class PaymentCalculator:
    def calculate(self, amount: Decimal, type: str) -> Decimal:
        if type == "percentage":
            return amount * 0.9
        elif type == "fixed":
            return amount - 100
        # Must add elif for each new type
```

### Domain-Driven Design (DDD)

Libraries are organized as bounded contexts. Each library represents a cohesive domain with clear boundaries, expressed through its public API.

### Design Patterns in Use

| Pattern | Purpose |
|---------|---------|
| **Repository Pattern** | Data access abstraction |
| **Interactor Pattern** | Use case encapsulation |
| **DTO Pattern** | Data transfer objects |
| **Factory Pattern** | Object creation |
| **Strategy Pattern** | Different repository implementations |
| **Unit of Work Pattern** | Transaction management |

## Anti-Patterns (Forbidden)

1. **God Objects** -- Classes with too many responsibilities
2. **Anemic Domain Model** -- DTOs with no behavior in domain layer
3. **Service Locator** -- Use Dependency Injection instead
4. **Circular Dependencies** -- Between modules or layers
5. **Layer Violations** -- Domain importing infrastructure
6. **Premature Abstractions** -- Creating abstractions used in only one place
7. **Unnecessary Layers** -- Adding pass-through service layers between interactor and repository
8. **Excessive Configuration** -- Making everything configurable when simple defaults suffice
9. **Speculative Generality** -- Planning for hypothetical future needs ("What if we need MongoDB?")

## Naming Conventions

| Component | File Pattern | Example |
|-----------|-------------|---------|
| Interactor | `*_interactor.py` | `create_driver_interactor.py` |
| Repository interface | `*_repository.py` | `driver_repository.py` |
| DTO | `*_dto.py` | `driver_dto.py` |
| Entity (domain) | `*_entity.py` or in `entities/` | `driver_entity.py` |
| Output contexts | -- | `OutputContext`, `OutputSuccessContext`, `OutputErrorContext` |

## Development Principles

### Pragmatic Development

The project balances architectural rigor with pragmatism:

**Implement:**
- Clean Architecture and Hexagonal Architecture as mandated by the template
- SOLID principles where they add clear value
- Design patterns that solve actual problems
- Quality criteria for security, maintainability, and testability

**Avoid:**
- Premature abstractions for hypothetical future needs
- Unnecessary layers that just pass through to the next layer
- Excessive configuration options when simple defaults work
- Builder patterns for simple DTOs (direct instantiation is preferred)
- Over-testing trivial property getters and data classes

### Semantic Versioning

All libraries follow semantic versioning (`MAJOR.MINOR.PATCH`):

| Version Change | When |
|---------------|------|
| **MAJOR** (v8.x -> v9.0.0) | Breaking changes to public API |
| **MINOR** (v8.150.x -> v8.151.0) | New features, backwards compatible |
| **PATCH** (v8.150.0 -> v8.150.1) | Bug fixes, backwards compatible |

Breaking changes in minor or patch versions are prohibited.

### CI/CD

Libraries include:
- `.github/workflows/` with testing workflows
- Linting configuration (flake8, pylint, or similar)
- Type checking configuration (mypy or similar)
