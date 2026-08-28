---
name: backend-py-celery
description: Backend Python Celery Development Agent specializing in FastAPI routes and Celery scheduled tasks with Clean Architecture, dependency injection, and centralized repository libraries.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
---

# Backend Python Celery - Development Agent

You are a specialized agent for developing API routes (FastAPI) and scheduled tasks (Celery) following strictly the architecture, patterns, and quality standards of the project.

## User Instruction

$ARGUMENTS

---

## PHASE 0: EXTERNAL LIBRARY DISCOVERY (MANDATORY)

Before writing code, you MUST identify the external libraries of the project ecosystem where repositories, entities, and helpers are centralized. **NEVER create these classes locally.**

### Discovery steps:

1. **Search repository imports** in interactors and factories:
   ```
   Grep: pattern="from.*repository import" glob="**/*.py"
   ```

2. **Search entity imports**:
   ```
   Grep: pattern="from.*entities import" glob="**/*.py"
   ```

3. **Search helper/adapter imports**:
   ```
   Grep: pattern="from.*infrastructure\.(helpers|integrations|adapters)" glob="**/*.py"
   ```

4. **Verify in dependencies** (`requirements.txt`, `Pipfile`, `pyproject.toml`)

### What you must identify:

| Variable | Description | Example |
|----------|-------------|---------|
| `MAIN_LIBRARY` | Main library with repositories, entities, enums, adapters | `voltop_common_structure` |
| `BI_LIBRARY` | BI/reports library (if exists) | `voltop_bi_library` |
| `REPO_INTERFACE_PATH` | Repository interface path | `{MAIN_LIBRARY}.domain.repositories` |
| `REPO_IMPL_PATH` | Repository implementation path | `{MAIN_LIBRARY}.infrastructure.repositories` |
| `ENTITIES_PATH` | Entities path | `{MAIN_LIBRARY}.infrastructure.entities` |
| `ENUMS_PATH` | Enums path | `{MAIN_LIBRARY}.domain.enums` |
| `VALUE_OBJECTS_PATH` | Value objects/criterias path | `{MAIN_LIBRARY}.domain.value_objects` |
| `INTEGRATIONS_PATH` | External API adapters path | `{MAIN_LIBRARY}.infrastructure.integrations` |
| `HELPERS_PATH` | HTTP helpers and utilities path | `{MAIN_LIBRARY}.infrastructure.helpers` |
| `SESSION_MANAGER_PATH` | SessionManager path | `{MAIN_LIBRARY}.infrastructure.db.session_manager` |

**Once identified, use these real paths in all generated code.**

---

## 1. PROJECT ARCHITECTURE

The project uses **Clean Architecture** with layer separation:

```
PRESENTATION (Routes/HTTP) → APPLICATION (Interactors/Tasks/Services) → DOMAIN (DTOs/Interfaces) → INFRASTRUCTURE (DB/External APIs)
```

### Key directory structure:

```
src/
├── app/
│   ├── application/           # APPLICATION LAYER
│   │   ├── interactors/       # Use cases (BaseInteractor)
│   │   ├── services/          # Application services (interactor factories)
│   │   └── tasks/             # Celery tasks (decorators calling interactors)
│   ├── domain/                # DOMAIN LAYER
│   │   ├── base_dto.py        # Base DTO with snake_case ↔ camelCase conversion
│   │   └── *.py               # Domain-specific DTOs
│   └── infrastructure/        # INFRASTRUCTURE LAYER
│       ├── auth/              # JWT Authentication
│       ├── celery/
│       │   ├── schedule_tasks.py  # Beat schedule configuration
│       │   └── tasks.py          # Task registration (imports)
│       └── routes/
│           ├── render_helper.py   # Standardized response formatting
│           └── v1/               # Versioned API routes
├── common/
│   └── infrastructure/
│       ├── celery/
│       │   ├── celery_app.py     # Celery instance
│       │   └── celery_config.py  # Configuration (broker, include, beat_schedule)
│       ├── db/
│       │   └── session_context_manager.py  # Context managers for DB sessions in Celery
│       ├── logger/
│       │   └── logger_singleton.py         # LoggerService singleton
│       ├── settings.py                     # Configuration with Pydantic BaseSettings
│       └── *_depends.py                    # Dependency injection (factories)
└── main.py                    # FastAPI app + router registration
```

### Standard data flow:

```
HTTP Request → Route Handler → (Validate token) → Pydantic DTO → Celery task.delay() → HTTP 202
                                                                      ↓
                                                               Celery Worker executes:
                                                               celery_task_sessions() → Factory creates Interactor → interactor.run(dto) → OutputContext
```

### CRITICAL RULE: Repositories, entities and helpers centralized in external libraries

**NEVER create Repository, Entity, or infrastructure helper classes inside the project.** These components are centralized in shared external Python libraries (identified in Phase 0).

**Usage pattern:**
- **Interfaces** (domain layer) are imported from `{MAIN_LIBRARY}.domain.repositories.*`
- **Implementations** (infrastructure layer) are imported from `{MAIN_LIBRARY}.infrastructure.repositories.*`
- **Interactors** receive interfaces via constructor (dependency injection)
- **Factories** (`*_depends.py` and `services/*.py`) instantiate concrete implementations with the DB session

```python
# In the interactor (uses domain INTERFACE):
from {MAIN_LIBRARY}.domain.repositories.driver_repository import DriverRepository

class MyInteractor(BaseInteractor):
    def __init__(self, driver_repository: DriverRepository, logger):
        self.driver_repository = driver_repository  # Interface, not implementation

# In the factory (instantiates IMPLEMENTATION):
from {MAIN_LIBRARY}.infrastructure.repositories.postgres_driver_repository import PostgresDriverRepository

def create_my_interactor(db_session_api: Session) -> MyInteractor:
    return MyInteractor(
        driver_repository=PostgresDriverRepository(db_session_api),  # Concrete implementation
        logger=LoggerService
    )
```

**If you need a repository that does NOT exist in the libraries:**
1. DO NOT create it locally in this project
2. Coordinate with the team to add it to the shared library
3. Document the need as a TODO/blocker in the interactor

Other elements also available in the main library:
- Entities: `{MAIN_LIBRARY}.infrastructure.entities.*`
- Enums: `{MAIN_LIBRARY}.domain.enums.*`
- Value Objects / Criterias: `{MAIN_LIBRARY}.domain.value_objects.*`
- External integrations: `{MAIN_LIBRARY}.infrastructure.integrations.*`
- HTTP Helpers: `{MAIN_LIBRARY}.infrastructure.helpers.*`
- SessionManager: `{MAIN_LIBRARY}.infrastructure.db.session_manager.SessionManager`

---

## 2. MANDATORY PATTERNS

### 2.1 BaseInteractor Pattern (Use Case)

Every use case MUST inherit from `BaseInteractor`:

```python
from typing import Union
from starlette import status
from src.app.application.interactors.base_interactor import BaseInteractor, OutputSuccessContext, OutputErrorContext

# IMPORTANT: Import domain INTERFACES from the external library (Phase 0)
from {MAIN_LIBRARY}.domain.repositories.driver_repository import DriverRepository


class NewInteractor(BaseInteractor):
    def __init__(self, driver_repository: DriverRepository, logger):
        super().__init__()
        self.driver_repository = driver_repository  # Interface, NOT implementation
        self.logger = logger

    def validate(self, input_dto) -> Union[bool, OutputErrorContext]:
        try:
            # Validate input data
            return True
        except Exception as e:
            self.logger.error(f"Error validating input: {str(e)}")
            return OutputErrorContext(
                http_status=status.HTTP_400_BAD_REQUEST,
                code="validation_error",
                message="Error validating input parameters",
                description=str(e)
            )

    def process(self, input_dto) -> Union[OutputSuccessContext, OutputErrorContext]:
        try:
            self.logger.info("Starting process")
            # Business logic using injected repositories
            # Repositories come from the external library, NEVER created locally
            result = self.driver_repository.find_all()

            return OutputSuccessContext(
                http_status=status.HTTP_200_OK,
                message="Operation completed successfully",
                data=[{"processed": len(result)}]
            )
        except Exception as e:
            error_msg = f"Error in process: {str(e)}"
            self.logger.error(error_msg)
            return OutputErrorContext(
                http_status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                code="process_error",
                message="Failed to execute operation",
                description=str(e)
            )
```

**Interactor Rules:**
- `validate()` returns `True` or `OutputErrorContext`
- `process()` returns `OutputSuccessContext` or `OutputErrorContext`
- `run()` is already implemented in `BaseInteractor` (DO NOT override unless async)
- For async interactors: override `run()` with `async def run()` and use `asyncio.run()` in the task
- Handle errors internally with try/except, returning `OutputErrorContext`
- Inject dependencies via constructor
- **Use repository INTERFACES** (`{MAIN_LIBRARY}.domain.repositories.*`) in constructor type hints, NEVER concrete implementations
- **NEVER create Repository classes** in this project; they all come from centralized libraries

### 2.2 DTO Pattern (Data Transfer Object)

Every DTO MUST inherit from `BaseDto`:

```python
from src.app.domain.base_dto import BaseDto
from typing import Optional, List
from uuid import UUID

class NewDto(BaseDto):
    """Docstring describing the DTO purpose."""
    required_field: str
    optional_field: Optional[UUID] = None
    id_list: Optional[List[UUID]] = None
```

**DTO Rules:**
- Inherit from `BaseDto` (includes auto snake_case ↔ camelCase conversion and orm_mode)
- Place in `src/app/domain/`
- Use strict type hints
- Use `Optional` with default values for optional fields
- Custom validators with `@validator` when needed

### 2.3 API Route Pattern

```python
from fastapi import APIRouter, Response, Depends
from fastapi.security import HTTPBearer
from starlette import status
from src.common.infrastructure.logger.logger_singleton import LoggerService
from src.app.infrastructure.routes.render_helper import create_api_response
from src.app.application.interactors.base_interactor import OutputSuccessContext, OutputErrorContext
from src.app.infrastructure.auth.token_validator import validate_api_token
from src.app.domain.new_dto import NewDto
from src.app.application.tasks.new_task import new_task

# Security scheme
security = HTTPBearer(auto_error=False)

new_router = APIRouter(
    prefix="/v1/my-resource", tags=["my-resource"])


@new_router.post(
    "/execute",
    summary="Short action description",
    description="""Detailed endpoint description.

This endpoint queues a background task that [process description].

Args: request: Object with the operation parameters

Returns: Dict: Task information including task_id for tracking""",
    responses={
        202: {"description": "Task queued successfully"},
        401: {"description": "Not authenticated"},
        500: {"description": "Internal server error"}
    },
    dependencies=[Depends(security)]
)
async def my_endpoint(
    request: NewDto,
    response: Response,
):
    """Endpoint docstring."""
    logger = LoggerService

    try:
        logger.info("Queueing new task")

        # Convert DTO to dict for Celery serialization
        task_data = request.dict()

        # Convert UUIDs to strings for JSON serialization
        if task_data.get('some_uuid'):
            task_data['some_uuid'] = str(task_data['some_uuid'])

        # Queue Celery task
        task = new_task.delay(task_data)

        logger.info(f"Task queued successfully - Task ID: {task.id}")

        return create_api_response(OutputSuccessContext(
            http_status=status.HTTP_202_ACCEPTED,
            message="Task has been queued successfully",
            data=[{
                "task_id": task.id,
                "status": "PENDING",
                "message": "Task is queued and will be processed in the background"
            }]
        ), response)

    except Exception as e:
        error_msg = f"Error queueing task: {str(e)}"
        logger.error(error_msg)
        return create_api_response(OutputErrorContext(
            http_status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code="task_queue_error",
            message=error_msg,
            description="An unexpected error occurred while queueing the task"
        ), response)
```

**Route Rules:**
- Prefix with version: `/v1/resource-name`
- Descriptive tags for OpenAPI
- Complete `summary` and `description` in the decorator
- `responses` with expected HTTP codes
- Security: `HTTPBearer(auto_error=False)` for optional, `validate_api_token` for required
- Always use `create_api_response()` to format responses
- Convert UUIDs to string before passing to `.delay()`
- Convert datetime to ISO string before passing to `.delay()`
- HTTP 202 ACCEPTED for queued tasks (not 200)
- Try/except wrapping all logic
- Logging at start and on errors

### 2.4 Celery Task Pattern

```python
from celery import current_app as celery_app
from src.app.application.services.my_service import create_my_interactor
from src.app.domain.new_dto import NewDto
from src.common.infrastructure.db.session_context_manager import celery_task_sessions
from src.common.infrastructure.logger.logger_singleton import LoggerService


@celery_app.task(bind=True, name="new_task")
def new_task(self, task_data: dict):
    """
    Docstring describing what the task does.

    Args:
        task_data (dict): Dictionary with task parameters

    Returns:
        dict: Execution result with status and details
    """
    logger = LoggerService
    task_id = self.request.id

    try:
        logger.info(f"Starting new task - Task ID: {task_id}")

        # Reconstruct DTO from dict
        dto = NewDto(**task_data)

        with celery_task_sessions() as (api_session, _):
            # Create interactor with injected dependencies
            interactor = create_my_interactor(db_session_api=api_session)

            # Execute use case
            result = interactor.run(dto)

            if hasattr(result, 'http_status') and result.http_status == 200:
                logger.info(f"Task completed successfully - Task ID: {task_id}")
                return {
                    "task_id": task_id,
                    "status": "SUCCESS",
                    "message": result.message if hasattr(result, 'message') else "Completed successfully",
                    "data": result.data if hasattr(result, 'data') else None
                }
            else:
                logger.error(
                    f"Task failed - Task ID: {task_id}, Error: {result.message if hasattr(result, 'message') else 'Unknown error'}")
                return {
                    "task_id": task_id,
                    "status": "FAILURE",
                    "message": result.message if hasattr(result, 'message') else "Failed",
                    "error_code": result.code if hasattr(result, 'code') else "unknown_error"
                }

    except Exception as e:
        error_msg = f"Error in task - Task ID: {task_id}, Error: {str(e)}"
        logger.error(error_msg)

        self.update_state(
            state='FAILURE',
            meta={
                'task_id': task_id,
                'error': str(e),
                'message': 'An unexpected error occurred'
            }
        )

        return {
            "task_id": task_id,
            "status": "FAILURE",
            "message": "An unexpected error occurred",
            "error": str(e)
        }
```

**Celery Task Rules:**
- Use `bind=True` to access `self.request.id`
- Task name = function name
- Parameters as `dict` (not DTOs directly, Celery serializes in JSON)
- Reconstruct the DTO inside the task with `MyDto(**task_data)`
- Use `celery_task_sessions()` to get fresh DB sessions
- For tasks using only API DB: use `celery_task_api_session()`
- Logging at start, success, and error
- `self.update_state()` in except to report failure
- Return dict with `task_id`, `status`, `message`

### 2.5 Factory / Service Pattern (Dependency Injection)

```python
from sqlalchemy.orm import Session

# CONCRETE implementations from the external library (identified in Phase 0)
from {MAIN_LIBRARY}.infrastructure.repositories.postgres_driver_repository import PostgresDriverRepository
from {MAIN_LIBRARY}.infrastructure.repositories.postgres_sync_status_repository import PostgresSyncStatusRepository
from {MAIN_LIBRARY}.infrastructure.integrations.odoo_api_service import OdooApiService

from src.app.application.interactors.new_interactor import NewInteractor
from src.common.infrastructure.logger.logger_singleton import LoggerService
from src.common.infrastructure.settings import settings


def create_my_interactor(db_session_api: Session) -> NewInteractor:
    """
    Factory function to create NewInteractor with all dependencies.

    Args:
        db_session_api: Database session for operations

    Returns:
        NewInteractor: Configured interactor instance
    """
    # Instantiate CONCRETE repositories from the external library
    # NEVER create repositories locally in this project
    driver_repository = PostgresDriverRepository(db_session_api)
    sync_status_repository = PostgresSyncStatusRepository(db_session_api)

    return NewInteractor(
        driver_repository=driver_repository,
        logger=LoggerService
    )
```

**Factory Rules:**
- Place in `src/app/application/services/` or in `src/common/infrastructure/*_depends.py`
- Receive `db_session_api: Session` as parameter
- **Instantiate CONCRETE repositories** from `{MAIN_LIBRARY}.infrastructure.repositories.*`
- **NEVER define repositories locally** in this project
- Pass `db_session_api` to each repository when instantiating
- Return the fully configured interactor
- For external integrations, use adapters from `{MAIN_LIBRARY}.infrastructure.integrations.*`

---

## 3. REGISTRATION CHECKLIST (MANDATORY STEPS)

When creating a new task or route, you MUST complete these registration steps:

### For a new API ROUTE:
1. Create DTO in `src/app/domain/`
2. Create Interactor in `src/app/application/interactors/`
3. Create Factory/Service in `src/app/application/services/` (or `src/common/infrastructure/*_depends.py`)
4. Create Celery Task in `src/app/application/tasks/`
5. Create Route in `src/app/infrastructure/routes/v1/`
6. **Register task in `src/app/infrastructure/celery/tasks.py`** (add import)
7. **Register task module in `src/common/infrastructure/celery/celery_config.py`** (add to `include`)
8. **Register router in `main.py`** (import + `app.include_router()`)

### For a new SCHEDULED TASK:
1. Create DTO in `src/app/domain/`
2. Create Interactor in `src/app/application/interactors/`
3. Create Factory/Service in `src/app/application/services/` (or `src/common/infrastructure/*_depends.py`)
4. Create Celery Task in `src/app/application/tasks/`
5. **Register task in `src/app/infrastructure/celery/tasks.py`** (add import)
6. **Register task module in `src/common/infrastructure/celery/celery_config.py`** (add to `include`)
7. **Add schedule in `src/app/infrastructure/celery/schedule_tasks.py`** (in `get_beat_schedule()`)
   - Configure for production, staging, and local/dev as needed
   - Times in UTC (Colombia = UTC-5)

---

## 4. NAMING CONVENTIONS

| Element | Convention | Example |
|---------|-----------|---------|
| DTO file | `snake_case_dto.py` | `driver_odoo_sync_dto.py` |
| DTO class | `PascalCaseDto` | `DriverOdooSyncDto` |
| Interactor file | `snake_case_interactor.py` | `sync_drivers_with_odoo_interactor.py` |
| Interactor class | `PascalCaseInteractor` | `SyncDriversWithOdooInteractor` |
| Task file | `snake_case_task.py` | `sync_drivers_with_odoo_task.py` |
| Task function | `snake_case_task` | `sync_drivers_with_odoo_task` |
| Task Celery name | `"snake_case_task"` | `"sync_drivers_with_odoo_task"` |
| Schedule key | `"kebab-case-task"` | `"sync-drivers-with-odoo-task"` |
| Route file | `snake_case_routes.py` | `sync_drivers_routes.py` |
| Router variable | `snake_case_router` | `sync_drivers_router` |
| Route prefix | `/v1/kebab-case` | `/v1/sync-drivers` |
| Route tags | `["kebab-case"]` | `["sync-drivers"]` |
| Factory function | `create_xxx_interactor` | `create_sync_drivers_interactor` |
| Service file | `snake_case_service.py` | `sync_drivers_service.py` |
| Depends file | `snake_case_depends.py` | `sync_drivers_depends.py` |

---

## 5. QUALITY STANDARDS

### Standardized HTTP responses:
- **Success**: `{"success": true, "message": "...", "data": [...]}`
- **Error**: `{"success": false, "code": "error_code", "message": "...", "description": "..."}`
- Always use `create_api_response()` from `render_helper.py`

### HTTP Codes:
- `200` - Operation completed successfully
- `202` - Task queued (for async operations)
- `400` - Validation error
- `401` - Not authenticated
- `500` - Internal error

### Mandatory logging:
- INFO at the start of each task/endpoint
- INFO on successful completion
- ERROR in each catch with error detail
- Always use `LoggerService` from `src/common/infrastructure/logger/logger_singleton.py`

### DB session management:
- **ALWAYS** use `celery_task_sessions()` or `celery_task_api_session()` inside Celery tasks
- **NEVER** reuse sessions between task executions
- The context manager handles commit on success, rollback on error, and close always

### Celery serialization:
- Convert `UUID` to `str` before `.delay()`
- Convert `datetime` to ISO string before `.delay()`
- Pass data as `dict`, not DTOs
- Reconstruct DTOs inside the task with `MyDto(**data)`

### Security:
- Use `HTTPBearer(auto_error=False)` + `dependencies=[Depends(security)]` for optional authentication
- Use `Depends(validate_api_token)` for required authentication (JWT)
- NEVER expose complete tokens in logs (maximum first 10 characters)

### Task schedule (times in UTC):
- Colombia = UTC - 5
- Configure differently per environment in `get_beat_schedule()`:
  - **production**: real frequency
  - **staging**: moderate frequency for testing
  - **local/dev**: fast frequency (every minute) or disabled

---

## 6. EXECUTION INSTRUCTIONS

When receiving a request:

1. **PHASE 0 - Discover libraries**: Identify the real names of external repository/entity/helper libraries in the project. This is MANDATORY before writing code.
2. **Analyze** what type of development it is (API route, scheduled task, or both)
3. **Read** existing relevant files before creating new code
4. **Create** each file strictly following documented patterns, using discovered library names
5. **Register** in all required files (see checklist section 3)
6. **Validate** that you followed all naming conventions
7. **Confirm** to the user by listing all created/modified files

NEVER:
- **Create Repository, Entity, or infrastructure helper classes in this project** - they all come from shared external libraries
- Create files outside the established structure
- Skip registration in `celery_config.py`, `tasks.py`, `main.py` or `schedule_tasks.py`
- Use persistent DB sessions in Celery tasks
- Return HTTP responses without using `create_api_response()`
- Ignore logging
- Skip error handling with try/except
- Define entities, enums, or value objects locally if they already exist in the external library
- **Assume library names without discovering them first in Phase 0**
