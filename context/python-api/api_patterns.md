# API Patterns

This document describes the patterns for building REST API endpoints, handling data transfer, configuring security, and managing database schemas in the Python API project.

## Endpoint Design

All endpoints are implemented as FastAPI routes in `infrastructure/routes/v1/*_routes.py`. Each route delegates to an interactor for business logic and returns a standardized API response.

### Route Structure

```python
@router.post("/resource", dependencies=[
    Depends(validate_user_token_depends),
    Depends(user_has_permission(ModulesEnum.RESOURCE, UserPermissions.CREATE))
])
async def create_resource(
    dto: CreateResourceDto,
    interactor: CreateResourceInteractor = Depends(create_resource_depends)
):
    result = interactor.run(dto)
    return create_api_response(result)
```

Key characteristics:
- Routes are thin -- they validate authentication/authorization, parse input, invoke the interactor, and format the response
- Business logic is never placed in route handlers
- The `interactor.run(dto)` call triggers the inherited validate-then-process flow from `BaseInteractor`
- Responses are standardized via `create_api_response()`

### Async Operations

I/O-bound operations use `async def`:
- Database queries
- External API calls
- File operations

### Scalability Patterns

- **Eager loading** to prevent N+1 queries: `.options(joinedload())`
- **Pagination** for list endpoints
- **Redis caching** for frequently accessed data
- **Connection pooling** via SQLAlchemy pool configuration
- **Batch operations** for bulk processing

```python
# Efficient query with eager loading
def get_drivers_with_vehicles(self, driver_ids: list[uuid.UUID]) -> list[DriverEntity]:
    return self.db.query(DriverEntity)\
        .options(joinedload(DriverEntity.vehicles))\
        .filter(DriverEntity.id.in_(driver_ids))\
        .all()
```

## DTOs (Data Transfer Objects)

DTOs are used for data flow between layers. They are defined in the domain layer (`domain/*_dto.py`) and validated with Pydantic.

### DTO Categories

| Category | Purpose | Example |
|----------|---------|---------|
| **Request DTOs** | Input data from routes | `CreateDriverDto` |
| **Response DTOs** | Output data to routes | `DriverResponseDto` |
| **Entity DTOs** | Data for repository operations | `UpdateDriverFieldsDto` |

### Rules

- All input DTOs use Pydantic models for validation
- Entities are never returned directly from API endpoints -- DTOs are always used
- DTOs represent the data structure for one operation (Single Responsibility)

## Dependency Injection

Dependencies are configured in `*_depends.py` files in the infrastructure layer and injected through FastAPI's `Depends()` mechanism.

### Factory Pattern

The `*_depends.py` factory functions are the **only place** where concrete implementations are instantiated:

```python
def some_interactor_depends(db: Session = Depends(get_db)) -> SomeInteractor:
    return SomeInteractor(
        repository=PostgresSomeRepository(db),  # Concrete repo -> abstract SomeRepository
        file_storage=S3Client(),                # Concrete service -> abstract FileStorageService
        logger=LoggerService()
    )
```

Key principle: Interactors declare dependencies using domain interfaces (ABC). Factories wire the concrete implementations. The application layer has zero knowledge of infrastructure details.

### Infrastructure Service Interfaces

When an interactor depends on an infrastructure concern (file storage, email, Excel processing, external APIs), an ABC interface is defined in the domain layer:

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

## Security (Authentication & Authorization)

### Authentication

JWT tokens are validated in routes via `validate_user_token_depends`:

```python
@router.post("/resource", dependencies=[
    Depends(validate_user_token_depends),
])
```

Supported authentication mechanisms:
- JWT tokens
- OAuth 2.0
- Firebase Admin

### Authorization

Permission checks use the `user_has_permission` decorator with module and permission enums:

```python
@router.post("/resource", dependencies=[
    Depends(validate_user_token_depends),
    Depends(user_has_permission(ModulesEnum.RESOURCE, UserPermissions.CREATE))
])
```

### Input Validation

- All input DTOs are Pydantic models with validation rules
- SQL injection is prevented by using SQLAlchemy ORM exclusively (never raw SQL strings)
- Sensitive data (passwords, tokens, PII) is never logged
- CORS is configured in `main.py`

## Database Patterns

### ORM Technologies

- **SQLAlchemy 2.0+** for PostgreSQL (relational)
- **MongoEngine** for MongoDB (document-based NoSQL)

### Alembic Migrations

```bash
# Auto-generate migration from model changes
alembic revision --autogenerate -m "description"

# Create empty migration for manual changes
alembic revision -m "description"
```

**Migration best practices:**
- One logical change per migration
- Always implement `downgrade()` for reversibility
- Use transactions and backup data before destructive changes
- Use PostgreSQL ENUMs or string columns with constraints for enums

### Database Indexing Guidelines

Each index accelerates reads but penalizes writes (INSERT/UPDATE/DELETE). Indexes are only created when justified by real and frequent queries.

#### When to Create an Index

| Criterion | Example |
|-----------|---------|
| UNIQUE business constraint | `idempotency_key`, `email`, `ticket_number` |
| Foreign key used in JOINs or WHERE | `user_id` in tables always filtered by user |
| Frequent WHERE query with high selectivity | Column with many distinct values (UUID, email, timestamps) |
| Compound index for frequent multi-column query | `(user_id, created_at)` for "my recent payments" |
| Column in ORDER BY of paginated queries | `created_at DESC` with `LIMIT/OFFSET` |

#### When NOT to Create an Index

| Criterion | Example |
|-----------|---------|
| Low cardinality | `status` with 6 values, `boolean` flags |
| Small table (< 10K rows) | Seq scan is equal or faster |
| Rarely filtered column | `metadata` JSONB that is only read |
| Redundant with a compound | `(user_id)` when `(user_id, status)` exists |
| Write-heavy table with few reads | Logs, audit trails, event sourcing |

#### Compound Index Rules

1. **Leftmost prefix rule**: `(A, B, C)` works for `A`, `A+B`, and `A+B+C`, but NOT for `B` alone or `C` alone
2. **Order by descending selectivity**: Most selective column first
3. **Maximum 3-4 columns** per compound index

#### Index Decision Process

```
Is it a UNIQUE constraint?
  -> YES: Create UNIQUE index

Is it a FK used in frequent WHERE/JOIN?
  -> YES: Check if a compound covers it
    -> YES: Don't create individual
    -> NO: Create individual

Does the column have high cardinality? (> 100 distinct values)
  -> NO: Don't create index (e.g., status, country, type)
  -> YES: Is it frequently filtered?
    -> YES: Create index
    -> NO: Don't create

Does a compound index already cover this query?
  -> YES: Don't duplicate
```

#### Limit per Table

- Maximum 3 indexes when creating the table (including UNIQUE constraints)
- Additional indexes require justification with a real query and EXPLAIN ANALYZE
- Small lookup/config tables: 1-2 indexes maximum
- High-write tables (logs, events): 0-1 indexes preferred

#### Indexes Added Later

Indexes are added after table creation when:
- A slow query appears in logs (`pg_stat_statements`)
- EXPLAIN ANALYZE shows sequential scan on a large table

Preventive optimization is avoided; indexes are created when there is evidence.

### Migration Example with Correct Indexing

```python
def upgrade() -> None:
    op.create_table(
        'payments',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
        sa.Column('idempotency_key', sa.String(255), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('status', sa.String(50), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )
    # UNIQUE business constraint -- frequent lookup
    op.create_unique_constraint('uq_payments_idempotency_key', 'payments', ['idempotency_key'])
    # Compound for "my payments filtered by status" -- covers user_id alone too
    op.create_index('idx_payments_user_id_status', 'payments', ['user_id', 'status'])
    # NOT needed: individual idx on user_id (redundant with compound)
    # NOT needed: idx on status alone (low cardinality)

def downgrade() -> None:
    op.drop_index('idx_payments_user_id_status', table_name='payments')
    op.drop_constraint('uq_payments_idempotency_key', 'payments', type_='unique')
    op.drop_table('payments')
```

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Interactor | `{Action}{Entity}Interactor` | `CreateDriverInteractor` |
| DTO | `{Entity}{Purpose}Dto` | `CreateDriverDto`, `DriverResponseDto` |
| Repository interface | `{Entity}Repository` | `DriverRepository` |
| Repository implementation | `Postgres{Entity}Repository` | `PostgresDriverRepository` |
| Route file | `*_routes.py` | `driver_routes.py` |
| Dependency factory | `*_depends.py` | `driver_depends.py` |
| Interactor file | `*_interactor.py` | `create_driver_interactor.py` |
| DTO file | `*_dto.py` | `driver_dto.py` |
| Repository file | `*_repository.py` | `driver_repository.py` |
