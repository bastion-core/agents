# Convenciones Backend Python/FastAPI

Resumen de convenciones arquitectonicas para generacion de especificaciones tecnicas de proyectos Python/FastAPI.

## Stack Tecnologico

- **Framework**: FastAPI 0.68.2+ con async/await
- **ORM**: SQLAlchemy 2.0+ (PostgreSQL), MongoEngine (MongoDB)
- **Migraciones**: Alembic 1.14.0+
- **Python**: 3.11+
- **Validacion**: Pydantic
- **Autenticacion**: JWT tokens, OAuth 2.0, Firebase Admin
- **Caching**: Redis
- **Testing**: Pytest con async support, pytest-mock, faker
- **Observabilidad**: Prometheus, Grafana, structured logging

## Arquitectura: Hexagonal (3 Capas)

El proyecto sigue Clean Architecture con Hexagonal Architecture (Ports and Adapters):

```
src/
  {domain}/
    application/           # CAPA DE APLICACION (Casos de Uso)
      *_interactor.py      # Orquestacion de logica de negocio
      base_*_interactor.py # Clases base para patrones comunes
    domain/                # CAPA DE DOMINIO (Reglas de Negocio)
      *_dto.py             # Data Transfer Objects
      *_repository.py      # Interfaces de repositorio (Ports)
      entities/            # Entidades de dominio
    infrastructure/        # CAPA DE INFRAESTRUCTURA (Adaptadores)
      routes/v1/           # Endpoints REST (Input Adapters)
      *_depends.py         # Inyeccion de dependencias
      repositories/        # Implementaciones de repositorio (Output Adapters)
      websockets/          # WebSocket endpoints
```

## Interactor Pattern (Casos de Uso)

Toda la logica de negocio se implementa a traves de Interactors:

- Heredan de `BaseInteractor`
- Constructor recibe dependencias como **interfaces ABC del dominio** (NUNCA clases concretas)
- Metodo `validate()` retorna `True` o `OutputErrorContext`
- Metodo `process()` retorna `OutputSuccessContext` o `OutputErrorContext`
- Los metodos `run()` / `run_async()` se heredan de `BaseInteractor` y orquestan validate -> process

## Repository Pattern (Ports and Adapters)

- **Port (Dominio)**: Interfaz abstracta ABC en `domain/*_repository.py`
- **Adapter (Infraestructura)**: Implementacion concreta en `infrastructure/repositories/postgres_*.py`
- Las interfaces definen metodos como `find_one_by_id()`, `create()`, `find_all()`
- Las implementaciones usan SQLAlchemy para la persistencia

## Infrastructure Service Interfaces (DIP)

Cuando un interactor depende de un servicio de infraestructura (file storage, email, Excel, APIs externas), se DEBE crear una **interfaz ABC en el dominio** y la implementacion concreta en infraestructura.

- **Port (Dominio)**: `domain/file_storage_service.py` (ABC)
- **Adapter (Infraestructura)**: `infrastructure/s3_client.py` (implementacion)
- Los type hints en el constructor del interactor SIEMPRE usan la interfaz ABC, nunca la clase concreta

**Cuando crear interfaz de servicio:**
- Interaccion con sistema externo (S3, email, SMS, payment gateway)
- Uso de herramienta de infraestructura (Excel parser, PDF generator)
- La dependencia podria tener implementaciones alternativas

**Cuando NO crear interfaz:**
- Funciones utilitarias puras (string formatting, math)
- Logger (cross-cutting concern, singleton aceptable)
- Value objects o DTOs simples

## DTOs (Data Transfer Objects)

Usados para el flujo de datos entre capas:
- **Request DTOs**: datos de entrada desde las rutas
- **Response DTOs**: datos de salida hacia las rutas
- **Entity DTOs**: datos para operaciones de repositorio
- Se definen con Pydantic para validacion automatica

## Inyeccion de Dependencias

Las dependencias se configuran en archivos `*_depends.py`:
- Son factories que instancian Interactors con sus dependencias concretas
- El factory es el UNICO lugar donde se instancian implementaciones concretas
- Los Interactors declaran dependencias usando interfaces del dominio (ABC)
- Las factories conectan las implementaciones concretas

## Gestion de Entidades

El proyecto usa una libreria compartida `voltop-common-structure` que provee:
- Entidades de Dominio (clases Python puras)
- Entidades de Infraestructura (modelos SQLAlchemy)
- Repositorios base con operaciones CRUD comunes
- DTOs y enums compartidos

## Patron de Respuesta

- **Exito**: `OutputSuccessContext` con `http_status`, `data`, `message`
- **Error**: `OutputErrorContext` con `http_status`, `code`, `message`, `description`
- Los mensajes de error usan i18n via `TranslateService`

## Rutas y Seguridad

- Endpoints definidos con `APIRouter` de FastAPI
- Autenticacion via `validate_user_token_depends` (JWT)
- Autorizacion via decorador `user_has_permission(ModulesEnum, UserPermissions)`
- Respuestas envueltas en `create_api_response(result)`

## Naming Conventions

| Tipo | Convencion | Ejemplo |
|------|-----------|---------|
| Interactor | `{Action}{Entity}Interactor` | `CreateDriverInteractor` |
| DTO | `{Entity}{Purpose}Dto` | `CreateDriverDto`, `DriverResponseDto` |
| Repository (interfaz) | `{Entity}Repository` | `DriverRepository` |
| Repository (impl) | `Postgres{Entity}Repository` | `PostgresDriverRepository` |
| Routes | `{entity}_routes.py` | `driver_routes.py` |
| Depends | `{entity}_depends.py` | `driver_depends.py` |

## Migraciones (Alembic)

- Una migracion por cambio logico
- Siempre implementar `downgrade()`
- Maximo 3 indexes al crear tabla (incluyendo UNIQUE)
- Indexes solo cuando se justifican: UNIQUE constraints, FKs frecuentes, columnas con alta cardinalidad
- No crear indexes preventivamente; crearlos cuando hay evidencia (pg_stat_statements, EXPLAIN ANALYZE)

## Testing

- **Unit Tests**: Interactors en aislamiento con repositorios mockeados
- **Integration Tests**: Repositorios contra base de datos de test
- **Estructura**: mirror de `src/` en `tests/`
- **Fixtures**: pytest fixtures para datos comunes
- **Mocking**: pytest-mock para dependencias externas
- **Cobertura**: objetivo >80%

## Anti-Patterns (PROHIBIDOS)

| Anti-Pattern | Alternativa Correcta |
|-------------|---------------------|
| Fat Interactors (toda la logica en uno) | Un interactor por caso de uso |
| Anemic Domain Model (entidades sin logica) | Entidades con comportamiento de negocio |
| Leaky Abstractions (infraestructura en dominio) | Interfaces ABC en dominio |
| God Objects (repositorios con demasiadas responsabilidades) | Repositorios enfocados |
| Tight Coupling (importar infra en dominio) | Dependency Inversion Principle |
| Over-Engineering (abstracciones innecesarias) | Solo lo que se necesita ahora |
| Tipos concretos de infra en Interactors | Usar interfaces ABC del dominio |
| N+1 Queries | Usar eager loading (joinedload) |
| Missing Validation | Validar en DTO + reglas de negocio en interactor |
| Hardcoded Values | Usar configuracion o constantes |
