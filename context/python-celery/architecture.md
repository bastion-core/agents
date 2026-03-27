# Architecture Overview

This document describes the architectural foundation of the Python Celery worker project. The system is built on Hexagonal Architecture (Ports and Adapters) adapted for asynchronous task processing, using Celery as the task execution framework with Python 3.11+.

## Architectural Pattern

The project implements **Hexagonal Architecture** (Ports and Adapters) adapted for **Celery workers**. The core difference from the API project is the entry point: instead of HTTP routes, **Celery tasks** serve as input adapters. Business logic remains in interactors, and data access follows the same repository pattern.

The key architectural invariant is preserved: business logic (domain and application layers) is fully isolated from infrastructure concerns (message brokers, databases, external services) through abstract interfaces (ports) and their concrete implementations (adapters).

## Layer Structure

### Domain Layer (`domain/`)
The innermost layer containing business rules. This layer has **zero dependencies** on infrastructure, Celery, or any external framework.

Contents:
- **Repository interfaces** (`*_repository.py`) -- Abstract Base Classes (ABC) defining data access contracts (ports)
- **DTOs** (`*_dto.py`) -- Data Transfer Objects for inter-layer communication
- **Service interfaces** -- ABC interfaces for infrastructure services (file storage, email, Excel processing, external APIs)
- **Entities** (`entities/`) -- Pure Python domain entities with business behavior
- **Serialization helpers** (`*_serializers_helper.py`) -- Domain-level serialization logic

### Application Layer (`application/`)
Contains use case orchestration via interactors. Depends only on the domain layer.

Contents:
- **Interactors** (`*_interactor.py`) -- Each interactor encapsulates one use case
- **Base interactors** (`base_*_interactor.py`) -- Shared base classes providing template method flow (validate then process)

Interactors are identical to those in the API project. They are agnostic to whether they are invoked from an HTTP route or a Celery task.

### Infrastructure Layer (`infrastructure/`)
The outermost layer implementing domain interfaces and providing task definitions.

Contents:
- **Tasks** (`tasks/`) -- Celery task definitions (input adapters, replacing `routes/`)
- **Repositories** (`repositories/postgres_*.py`) -- SQLAlchemy implementations of domain repository interfaces (output adapters)
- **Dependency wiring** (`*_depends.py`) -- Factory functions that instantiate concrete implementations and wire them to interactors
- **Session management** -- Database session lifecycle scoped per task execution

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
          tasks/                         # Celery task definitions (Input Adapters)
              *_tasks.py                 # Task registration and execution
          *_depends.py                   # Dependency injection / factory wiring
          repositories/
              postgres_*.py              # Repository implementations (Output Adapters)
```

Notable difference from the API project: the `routes/` and `websockets/` directories are absent. Celery tasks in `tasks/` are the entry points.

## Dependency Flow

Dependencies point strictly **inward**:

```
Infrastructure --> Application --> Domain
     (outer)        (middle)       (inner)
```

- **Domain** depends on nothing (pure Python, ABCs, standard library)
- **Application** depends on domain interfaces only
- **Infrastructure** depends on domain interfaces and implements them; also depends on Celery for task registration

The **Dependency Inversion Principle** is enforced at all boundaries:
- Interactors declare dependencies using domain interfaces (ABC), never concrete infrastructure classes
- Factory functions in `*_depends.py` are the only place where concrete implementations are instantiated
- Celery tasks call interactors through the same dependency injection pattern used by API routes

## Key Architectural Decisions

### Worker Process Lifecycle

Celery workers run as long-lived processes that execute tasks from a message queue. Key lifecycle considerations:

- **Session scoping** -- Database sessions are scoped per task execution, not per HTTP request. Each task creates its own session and closes it upon completion (success or failure).
- **Connection pooling** -- SQLAlchemy connection pools are shared across tasks within a worker process. Pool size is configured to match worker concurrency.
- **Task registration** -- Tasks are registered with the Celery app during worker startup. Each task function is a thin adapter that wires dependencies and delegates to an interactor.
- **Beat scheduler** -- Periodic tasks are defined in the Celery beat schedule configuration, triggering the same task functions on a cron-like schedule.

### Task as Input Adapter

A Celery task serves the same role as an HTTP route in the API project -- it is a thin infrastructure adapter:

```python
from celery import shared_task

@shared_task(
    bind=True,
    name="process_driver_payment",
    max_retries=3,
    default_retry_delay=60,
)
def process_driver_payment_task(self, driver_id: str, amount: float):
    """Celery task adapter -- thin wrapper that delegates to interactor."""
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
    except TaskProcessingError:
        db.rollback()
        raise self.retry(exc=exc)
    except Exception as exc:
        db.rollback()
        raise self.retry(exc=exc)
    finally:
        db.close()
```

### Design Patterns in Use

**Creational Patterns**:
- **Factory Pattern** -- Dependency wiring in `*_depends.py` and within task functions
- **Singleton Pattern** -- `LoggerService`, Celery app instance, connection pools

**Structural Patterns**:
- **Adapter Pattern** -- Repository implementations adapt infrastructure (SQLAlchemy) to domain interfaces; Celery tasks adapt message queue to interactors
- **Facade Pattern** -- Interactors simplify complex multi-step operations behind a single interface

**Behavioral Patterns**:
- **Strategy Pattern** -- Different repository implementations (Postgres, Mongo) behind the same interface
- **Template Method** -- `BaseInteractor` defines the validate-then-process algorithm
- **Chain of Responsibility** -- Celery middleware (signal handlers) for logging, error handling, session management

### Infrastructure Service Interfaces

When an interactor depends on an infrastructure concern (file storage, email, external APIs), an ABC interface is defined in the domain layer, identical to the API project pattern:

```python
# Domain Layer (Port)
from abc import ABC, abstractmethod

class FileStorageService(ABC):
    @abstractmethod
    def upload_file(self, content: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
        pass

# Infrastructure Layer (Adapter)
class S3Client(FileStorageService):
    def upload_file(self, content: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
        # boto3 implementation
        pass
```

### Entity Management

The project uses the shared library `voltop-common-structure` that provides:
- **Domain Entities** (e.g., `DriverDomainEntity`) -- pure Python classes for business logic
- **Infrastructure Entities** (e.g., `DriverEntity`) -- SQLAlchemy models with relationships
- **Base repositories** with common CRUD operations
- **Shared DTOs and enums**

### SOLID Principles Application

The same SOLID principles from the API project apply in the Celery context:

**Single Responsibility (SRP)**:
- Each interactor handles one use case
- Each task function wraps one interactor invocation
- Repositories manage data access for one entity

**Open/Closed (OCP)**:
- Base classes (`BaseInteractor`, `BaseRepository`) provide extension points
- New task types are added without modifying existing tasks

**Liskov Substitution (LSP)**:
- All repository implementations honor their interface contracts
- Interactors are substitutable regardless of the calling context (HTTP or Celery)

**Interface Segregation (ISP)**:
- Repository interfaces are specific to client needs
- Task-specific DTOs are separate from API-specific DTOs when inputs differ

**Dependency Inversion (DIP)**:
- Interactors depend on abstractions (all infrastructure interfaces), not implementations
- Task functions wire concrete implementations into interactors

## Anti-Patterns (Forbidden)

1. **Fat Tasks** -- Putting business logic directly in Celery task functions. Tasks are thin adapters; logic belongs in interactors.
2. **Shared Mutable State** -- Storing state in module-level variables or worker globals between task executions. Each task execution is isolated.
3. **Leaky Abstractions** -- Exposing Celery-specific concepts (task IDs, retries, queues) in the domain or application layers.
4. **Unscoped Sessions** -- Using a single database session across multiple task executions. Sessions are scoped per task.
5. **Tight Coupling** -- Importing infrastructure implementations in the domain layer.
6. **Over-Engineering** -- Adding unnecessary abstractions, patterns, or complexity beyond current requirements.
7. **Missing Transactions** -- Performing multiple database operations without explicit commit/rollback boundaries.
8. **Unbounded Retries** -- Retrying indefinitely without a max retry limit or dead letter strategy.

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Interactor | `{Action}{Entity}Interactor` | `ProcessDriverPaymentInteractor` |
| Task function | `{action}_{entity}_task` | `process_driver_payment_task` |
| Task file | `*_tasks.py` | `payment_tasks.py` |
| DTO | `{Entity}{Purpose}Dto` | `ProcessPaymentDto` |
| Repository interface | `{Entity}Repository` | `PaymentRepository` |
| Repository implementation | `Postgres{Entity}Repository` | `PostgresPaymentRepository` |
| Dependency factory | `*_depends.py` | `payment_depends.py` |

## Development Principles

### Pragmatic Development

The same pragmatic principles from the API project apply:

**Implement:**
- Hexagonal Architecture adapted for Celery workers
- SOLID principles where they add clear value
- Proper session and transaction management per task
- Retry policies with bounded retries and exponential backoff

**Avoid:**
- Abstractions for hypothetical future needs
- Over-configurable task frameworks when simple task functions suffice
- Complex orchestration patterns when sequential task execution works
- "Future-proofing" not justified by actual requirements

### Implementation Order

When building a new Celery task:

1. **Domain Layer** -- DTOs, repository interfaces, domain logic
2. **Infrastructure Layer** -- Repository implementations, dependency wiring
3. **Application Layer** -- Interactor with validation and business logic
4. **Infrastructure Layer** -- Celery task definition with retry policy and session management
5. **Tests** -- Unit tests for interactor, integration tests for task execution
