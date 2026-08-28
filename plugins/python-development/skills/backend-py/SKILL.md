---
name: backend-py
description: General Python backend standards for Clean/Hexagonal Architecture projects — layering, SOLID, dependency injection, typing, error handling, configuration, security and performance criteria, framework-agnostic.
---

# Backend Python Standards Skill

Framework-agnostic quality standards for Python backend codebases (APIs, workers, jobs, CLIs)
built with **Clean Architecture / Hexagonal Architecture (Ports & Adapters)**.

Use this skill as the shared baseline for **writing** and **reviewing** Python backend code
under `src/`. Framework-specific rules live in dedicated skills:

| Concern | Skill |
|---|---|
| FastAPI routes + Celery tasks | `backend-py-celery` |
| Reusable internal libraries | `backend-py-library` |
| Alembic migration jobs | `backend-py-alembic` |
| Testing and coverage | `qa-backend-py` |

---

## 1. Technology Baseline

- **Python**: 3.11+
- **ORM**: SQLAlchemy 2.0+ (PostgreSQL), MongoEngine (MongoDB)
- **Validation**: Pydantic v2
- **Migrations**: Alembic 1.14.0+
- **Testing**: pytest, pytest-mock, coverage
- **Config**: environment variables loaded through a single settings object

---

## 2. Layering Rules

### 2.1 — Canonical Structure

```
src/
├── domain/                  # Business rules. ZERO infrastructure imports.
│   ├── entities/            # Domain entities (pure Python / Pydantic)
│   ├── *_dto.py             # Data Transfer Objects
│   ├── *_repository.py      # Ports (ABC interfaces)
│   └── *_service.py         # Ports for non-DB infrastructure (storage, email, HTTP)
├── application/             # Use cases
│   └── *_interactor.py      # One interactor = one use case
└── infrastructure/          # Adapters
    ├── repositories/        # Port implementations (SQLAlchemy, Mongo, HTTP)
    ├── db/                  # Session/engine management, seeds
    ├── settings.py          # Configuration object
    └── routes/ | tasks/     # Delivery mechanisms (optional per project type)
```

For multi-domain projects the same three layers are repeated per bounded context
(`src/{domain}/domain|application|infrastructure`).

### 2.2 — Dependency Direction (NON-NEGOTIABLE)

```
infrastructure ──▶ application ──▶ domain
                                   ▲
                   infrastructure ─┘   (implements domain ports)
```

**Hard rules:**

- ❌ `src/domain/**` MUST NOT import from `src/infrastructure/**` or from any driver/ORM/SDK
  (`sqlalchemy.orm.Session`, `boto3`, `requests`, `fastapi`, `celery`).
- ❌ `src/application/**` MUST NOT import concrete adapters. It receives them injected,
  typed as domain ABCs.
- ✅ `src/infrastructure/**` may import from `domain` and `application`.
- ✅ Composition/wiring (the only place concrete classes are instantiated) lives in a
  factory/`*_depends.py`/entrypoint module.

```python
# ❌ Layer violation — domain knows about the ORM
# src/domain/user_repository.py
from sqlalchemy.orm import Session

# ✅ Port in domain, adapter in infrastructure
# src/domain/user_repository.py
from abc import ABC, abstractmethod

class UserRepository(ABC):
    @abstractmethod
    def find_one_by_id(self, user_id: uuid.UUID) -> UserEntity | None: ...

# src/infrastructure/repositories/postgres_user_repository.py
from sqlalchemy.orm import Session

class PostgresUserRepository(UserRepository):
    def __init__(self, session: Session) -> None:
        self.session = session
```

### 2.3 — Shared Structure Library

When the ecosystem provides a shared library (entities, base repositories, mappers, criterias),
**always check it before creating a local class**. Duplicating an entity or repository that already
exists in the shared library is a blocking defect: the two copies drift and break the schema
contract with other services.

---

## 3. Interactor Pattern (Use Cases)

```python
class ExecuteSeedsInteractor(BaseInteractor):
    def __init__(self, repository: SeedRepository, logger: LoggerService) -> None:
        BaseInteractor.__init__(self)
        self.repository = repository   # domain ABC, never a concrete class
        self.logger = logger

    def validate(self, input_dto: SeedDto | None) -> bool | OutputErrorContext:
        ...

    def process(self, input_dto: SeedDto | None) -> OutputSuccessContext | OutputErrorContext:
        ...
```

**Rules:**

1. One interactor = one use case. Split when a class starts handling two reasons to change.
2. Constructor type hints use **domain abstractions only**.
3. `validate()` returns `True` or an error context — it never raises for expected business errors.
4. `process()` never returns raw ORM entities; it returns DTOs/domain entities or output contexts.
5. Orchestration only: SQL, HTTP calls, and file I/O belong in adapters.

**Exception for logger:** cross-cutting logger singletons may be used concretely.

---

## 4. Dependency Injection

```python
def execute_seeds_interactor() -> ExecuteSeedsInteractor:
    db = next(get_db())
    return ExecuteSeedsInteractor(
        repository=PostgresSeedRepository(db),   # concrete → abstract
        logger=LoggerService(),
    )
```

- Factories are the single composition root.
- ❌ No Service Locator, no global singletons holding a DB session, no `import` inside a method
  purely to dodge a circular dependency (that circular import is an architecture smell).
- ✅ Session lifecycle is explicit: open → use → `commit()`/`rollback()` → `close()` in `finally`.

---

## 5. Typing and Documentation

```python
def calculate_debt(user_id: uuid.UUID, amount: Decimal, discount: Decimal | None = None) -> DebtResult:
    """
    Calculate outstanding debt applying an optional discount.

    Args:
        user_id: Owner of the debt.
        amount: Base amount in COP.
        discount: Optional discount percentage (0-100).

    Returns:
        DebtResult with the final amount.

    Raises:
        ValueError: If amount is negative or discount > 100.
    """
```

**Rules:**

- Type hints on every public function/method parameter and return value.
- `Decimal` for money — **never** `float`.
- Timezone-aware `datetime` for anything persisted; UTC at rest.
- Docstrings for public/complex functions. Trivial private helpers do not need them.
- `Any` requires justification; prefer a protocol, union, or generic.

---

## 6. Error Handling

```python
# ✅ Explicit, typed, logged with context
try:
    result = self.repository.create(dto)
except IntegrityError as exc:
    self.logger.error(f"Integrity error creating user {dto.email}: {exc}")
    return OutputErrorContext(http_status=409, code="USER_EXISTS", message=...)
except Exception as exc:
    self.logger.error(f"Unexpected error creating user: {exc}")
    return OutputErrorContext(http_status=500, code="INTERNAL_ERROR", message=...)
```

**Rules:**

- ❌ Never `except:` or `except Exception: pass`. Silent failure is a blocking defect.
- ❌ Never swallow an exception and return `None` as an error channel for a use case.
- ✅ Catch the specific exception first, generic last.
- ✅ Always log with enough context to identify the failing record (IDs, not secrets).
- ✅ Any code path that writes to the DB must `rollback()` on failure and `close()` in `finally`.
- ✅ Long-running jobs must exit with a non-zero status code on failure so the orchestrator
  (Kubernetes Job, Cloud Run Job, ECS task) marks the run as failed.

---

## 7. Configuration and Secrets

```python
# src/infrastructure/settings.py
class Settings:
    db_url: str = os.getenv("DB_URL", "")
    environment: str = os.getenv("ENVIRONMENT", "local")
```

- All configuration comes from environment variables, read in **one** settings module.
- ❌ No hardcoded credentials, tokens, hostnames, or connection strings anywhere in `src/`.
- ✅ Required variables are validated at startup with a clear error message; fail fast.
- ✅ `.env.example` documents every variable the project needs (no real values).
- ✅ Sanitize values that come from `.env` files when the deployment pipeline may inject quotes.
- ❌ Never log a full connection string, token, password, or PII.

---

## 8. Persistence and Performance

- ✅ Parameterized queries only: `session.execute(text("... :id"), {"id": id})` or ORM filters.
  String interpolation into SQL is a **critical** security defect.
- ✅ Eager load related entities (`joinedload`/`selectinload`) instead of iterating (N+1).
- ✅ Bulk operations for large datasets (`execute_batch`, `bulk_save_objects`, batched commits) —
  never one `commit()` per row inside a loop over thousands of rows.
- ✅ Explicit transaction boundaries; one logical unit of work = one transaction.
- ✅ Pagination for unbounded reads.
- ✅ Close sessions/connections deterministically.

---

## 9. Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Module | `snake_case.py` | `postgres_user_repository.py` |
| Class | `PascalCase` | `PostgresUserRepository` |
| Function/variable | `snake_case` | `find_one_by_id` |
| Constant | `UPPER_SNAKE_CASE` | `DEFAULT_CURRENCY` |
| Interactor | `{Action}{Entity}Interactor` | `CreateUserInteractor` |
| Port (repo) | `{Entity}Repository` | `UserRepository` |
| Adapter (repo) | `{Tech}{Entity}Repository` | `PostgresUserRepository` |
| DTO | `{Action}{Entity}Dto` | `CreateUserDto` |
| Private helper | `_leading_underscore` | `_execute_seeds` |

Code, comments, docstrings and log messages in `src/` are written in **English**.

---

## 10. Code Smells to Flag

1. Function longer than 30 lines or class longer than 300 lines.
2. More than 5 positional parameters (use a DTO).
3. Magic numbers/strings (extract to a named constant or enum).
4. Duplicated logic across layers or modules.
5. Commented-out code, dead code, unreachable branches.
6. `print()` used as application logging in `src/` (acceptable only in `scripts/`).
7. `TODO`/`FIXME` left in a merged change without a tracking reference.
8. Anemic domain: entities that are pure bags of attributes while all rules live elsewhere.
9. God object: one class orchestrating persistence, transport and business rules.
10. Circular imports between modules of the same layer.

---

## 11. Pragmatism Guardrails

**Implement what is needed now.** Do not add caching layers, event publishers, metrics collectors,
strategy hierarchies, or generic abstractions for hypothetical future needs.

**Do:**
- Follow the established architecture of the repository.
- Apply SOLID where it removes real coupling.
- Keep the simplest solution that satisfies the requirement and the layering rules.

**Do not:**
- Introduce new layers or patterns beyond the ones already in the project.
- Refactor working code that already complies with the established patterns.
- Demand abstractions for one-off administrative scripts.

---

## 12. Quality Checklist

**Architecture**
- [ ] No `domain → infrastructure` imports
- [ ] Interactors depend on ABCs, not concrete classes
- [ ] Concrete implementations instantiated only in factories/composition root
- [ ] No duplication of shared-library entities/repositories
- [ ] No circular dependencies

**Code Quality**
- [ ] Type hints on all public signatures
- [ ] Specific exception handling, always logged, never silent
- [ ] `Decimal` for money, timezone-aware UTC datetimes
- [ ] No hardcoded secrets or connection strings
- [ ] Parameterized SQL only
- [ ] No N+1 queries, bulk operations for large datasets
- [ ] Naming conventions respected, English identifiers
- [ ] No dead/commented-out code

**Operational**
- [ ] Required env vars validated at startup, fail fast with clear message
- [ ] Sessions/connections closed in `finally`; rollback on error
- [ ] Non-zero exit code on failure for jobs/workers
- [ ] Logs carry context but never secrets or PII
