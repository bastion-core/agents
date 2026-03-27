# Architecture Overview

This document describes the architectural foundation of the Python API project. The system is built on Hexagonal Architecture (Ports and Adapters) with Clean Architecture principles, targeting FastAPI 0.68.2+ on Python 3.11+.

## Architectural Pattern

The project implements **Hexagonal Architecture** (also known as Ports and Adapters), organized by **bounded contexts** (Domain-Driven Design). Each domain module is self-contained and follows a strict three-layer separation.

The core idea: business logic (domain and application layers) is isolated from infrastructure concerns (databases, HTTP, external services) through abstract interfaces (ports) and their concrete implementations (adapters).

## Layer Structure

### Domain Layer (`domain/`)
The innermost layer containing business rules. This layer has **zero dependencies** on infrastructure or application layers.

Contents:
- **Repository interfaces** (`*_repository.py`) -- Abstract Base Classes (ABC) defining data access contracts (ports)
- **DTOs** (`*_dto.py`) -- Data Transfer Objects for inter-layer communication
- **Service interfaces** -- ABC interfaces for infrastructure services (file storage, email, Excel processing, external APIs)
- **Entities** (`entities/`) -- Pure Python domain entities with business behavior
- **Serialization helpers** (`*_serializers_helper.py`) -- Domain-level serialization logic

### Application Layer (`application/`)
Contains use case orchestration. Depends only on the domain layer.

Contents:
- **Interactors** (`*_interactor.py`) -- Each interactor encapsulates one use case
- **Base interactors** (`base_*_interactor.py`) -- Shared base classes providing template method flow (validate then process)

### Infrastructure Layer (`infrastructure/`)
The outermost layer containing all external concerns. Implements domain interfaces.

Contents:
- **Routes** (`routes/v1/*_routes.py`) -- FastAPI REST endpoints (input adapters)
- **Repositories** (`repositories/postgres_*.py`) -- SQLAlchemy implementations of domain repository interfaces (output adapters)
- **WebSockets** (`websockets/`) -- WebSocket endpoints (input adapters)
- **Dependency injection** (`*_depends.py`) -- Factory functions wiring concrete implementations to abstract interfaces

## Folder Structure

```
src/
  {domain}/                              # Each domain is a bounded context
      application/                       # USE CASES LAYER
          *_interactor.py                # Business logic orchestration
          base_*_interactor.py           # Base classes for common patterns
      domain/                            # DOMAIN LAYER
          *_dto.py                       # Data Transfer Objects
          *_repository.py                # Repository interfaces (Ports)
          *_serializers_helper.py        # Domain serialization logic
          entities/                      # Domain entities
      infrastructure/                    # INFRASTRUCTURE LAYER
          routes/
              v1/
                  *_routes.py            # REST API endpoints (Input Adapters)
          *_depends.py                   # Dependency injection configuration
          repositories/
              postgres_*.py              # Repository implementations (Output Adapters)
          websockets/                    # WebSocket endpoints (Input Adapters)
```

## Dependency Flow

Dependencies point strictly **inward**:

```
Infrastructure --> Application --> Domain
     (outer)        (middle)       (inner)
```

- **Domain** depends on nothing (pure Python, ABCs, standard library)
- **Application** depends on domain interfaces only
- **Infrastructure** depends on domain interfaces and implements them

The **Dependency Inversion Principle** is enforced at all boundaries:
- Interactors declare dependencies using domain interfaces (ABC), never concrete infrastructure classes
- The `*_depends.py` factory functions are the **only place** where concrete implementations are instantiated and wired to abstract interfaces
- Type hints in interactor constructors reference abstractions, not concrete classes

## Key Architectural Decisions

### Design Patterns in Use

**Creational Patterns**:
- **Factory Pattern** -- Dependency injection factories in `*_depends.py` files
- **Builder Pattern** -- For complex entity creation
- **Singleton Pattern** -- `LoggerService`, database connections

**Structural Patterns**:
- **Adapter Pattern** -- Repository implementations adapt infrastructure (SQLAlchemy) to domain interfaces
- **Facade Pattern** -- Interactors simplify complex multi-step operations behind a single interface
- **Decorator Pattern** -- Middleware for authentication, logging, and error handling

**Behavioral Patterns**:
- **Strategy Pattern** -- Different repository implementations (Postgres, Mongo) behind the same interface
- **Template Method** -- `BaseInteractor` defines the validate-then-process algorithm; subclasses override `validate()` and `process()`
- **Observer Pattern** -- WebSocket event broadcasting
- **Chain of Responsibility** -- Middleware pipeline in FastAPI

### Infrastructure Service Interfaces

When an interactor depends on an infrastructure concern beyond data access (file storage, email, SMS, payment gateways, Excel parsers, PDF generators), an ABC interface is defined in the domain layer and implemented in the infrastructure layer. This is the same Ports and Adapters pattern used for repositories.

**When to create a service interface:**
- The interactor interacts with an external system (S3, email, SMS, payment gateway)
- The interactor uses an infrastructure tool (Excel parser, PDF generator, CSV processor)
- The dependency could have alternative implementations (local storage vs S3, different email providers)
- The dependency makes the interactor hard to test without the interface

**When NOT to create a service interface:**
- Pure utility functions with no infrastructure dependency (string formatting, math calculations)
- Logger services (cross-cutting concern; using the concrete singleton is acceptable)
- Simple value objects or DTOs

### Entity Management

The project uses a shared library `voltop-common-structure` that provides:
- **Domain Entities** (e.g., `DriverDomainEntity`, `VehicleDomainEntity`) -- pure Python classes for business logic
- **Infrastructure Entities** (e.g., `DriverEntity`, `VehicleEntity`) -- SQLAlchemy models with relationships
- **Base repositories** with common CRUD operations
- **Shared DTOs and enums**

New entities and repositories should be checked against `voltop-common-structure` before being created locally.

### SOLID Principles Application

**Single Responsibility (SRP)**:
- Each interactor handles one use case
- Repositories manage data access for one entity
- DTOs represent the data structure for one operation
- Serializers handle only transformation logic

**Open/Closed (OCP)**:
- Base classes (`BaseInteractor`, `BaseRepository`) provide extension points
- Abstractions (repository interfaces) allow new implementations without modifying existing code
- Polymorphism enables different behaviors through the same interface

**Liskov Substitution (LSP)**:
- All repository implementations honor their interface contracts
- Derived interactors maintain base class behavior
- Dependency injection is substitutable

**Interface Segregation (ISP)**:
- Repository interfaces are specific to client needs
- Large interfaces are broken into smaller, focused ones

**Dependency Inversion (DIP)**:
- Interactors depend on abstractions (all infrastructure interfaces), not implementations
- Infrastructure implementations depend on domain abstractions
- Type hints in interactor constructors use ABC interfaces from the domain layer

## Anti-Patterns (Forbidden)

The following patterns are explicitly prohibited:

1. **Fat Interactors** -- Putting all business logic in one interactor. Each interactor handles one use case.
2. **Anemic Domain Model** -- Using entities as simple data containers without behavior.
3. **Leaky Abstractions** -- Exposing infrastructure details (SQLAlchemy sessions, HTTP specifics) in the domain layer.
4. **God Objects** -- Creating repositories or services with too many responsibilities.
5. **Tight Coupling** -- Importing infrastructure implementations in the domain layer.
6. **Over-Engineering** -- Adding unnecessary abstractions, patterns, or complexity beyond what the current requirement demands.
7. **Concrete Infrastructure Types in Interactors** -- Using concrete classes (e.g., `S3Client`, `ExcelProcessor`) as type hints in interactor constructors instead of their domain ABC interface.

**Common mistakes to avoid:**
- Forgetting transactions when performing multiple DB operations
- N+1 queries (always use eager loading for related entities)
- Missing validation at DTO level and business rule level in interactors
- Ignoring errors instead of returning `OutputErrorContext`
- Hardcoded values instead of configuration, environment variables, or constants
- Returning entities directly from API endpoints instead of using DTOs

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Interactor | `{Action}{Entity}Interactor` | `CreateDriverInteractor` |
| DTO | `{Entity}{Purpose}Dto` | `CreateDriverDto`, `DriverResponseDto` |
| Repository interface | `{Entity}Repository` | `DriverRepository` |
| Repository implementation | `Postgres{Entity}Repository` | `PostgresDriverRepository` |
| Route file | `*_routes.py` | `driver_routes.py` |
| Dependency factory | `*_depends.py` | `driver_depends.py` |
| Base interactor | `base_*_interactor.py` | `base_driver_interactor.py` |

## Development Principles

### Pragmatic Development

The project balances architectural rigor with pragmatism:

**Implement:**
- Clean Architecture and Hexagonal Architecture as defined in the project structure
- SOLID principles where they add clear value
- Design patterns that solve actual problems in the codebase
- Quality criteria for security, scalability, maintainability, and testability

**Avoid:**
- Abstractions for hypothetical future needs
- Design patterns that are not needed for the current requirement
- Additional layers beyond the established architecture
- "Future-proofing" that is not justified by actual requirements
- Refactoring working code that already follows established patterns

### Good vs Over-Engineered Example

```python
# GOOD: Simple, follows established patterns
class GetDriverInteractor(BaseInteractor):
    def __init__(self, repository: DriverRepository, logger: LoggerService):
        BaseInteractor.__init__(self)
        self.repository = repository
        self.logger = logger

    def process(self, driver_id: uuid.UUID) -> OutputSuccessContext | OutputErrorContext:
        driver = self.repository.find_one_by_id(driver_id)
        if not driver:
            return OutputErrorContext(http_status=404, code="DRIVER_NOT_FOUND")
        return OutputSuccessContext(data=[driver])


# OVER-ENGINEERED: Unnecessary abstractions for a simple lookup
class GetDriverInteractor(BaseInteractor):
    def __init__(
        self,
        repository: DriverRepository,
        logger: LoggerService,
        cache_strategy: CacheStrategy,       # Not needed yet
        event_publisher: EventPublisher,      # Not needed yet
        metrics_collector: MetricsCollector   # Not needed yet
    ):
        # ... unnecessary complexity for current requirement
```

### Implementation Order

When building a new feature, follow this order:

1. **Domain Layer** -- DTOs, repository interfaces, domain logic
2. **Infrastructure Layer** -- Repository implementations, dependency injection configuration
3. **Application Layer** -- Interactor with validation and business logic
4. **Infrastructure Layer** -- Routes with authentication and authorization
5. **Tests** -- Unit tests for interactor, integration tests for repository
