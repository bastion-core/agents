# Architecture - Airflow DAGs

Este documento describe la arquitectura y organización del scaffold **`airflow-dags-scaffold`**, base para los repositorios de DAGs de Apache Airflow del equipo BI/BA.

## Filosofía

- El DAG es **delgado**: solo orquesta, no contiene lógica de negocio.
- La lógica vive en **Steps** componibles dentro del Pipeline framework (`scripts/python/pipelines/core/`).
- El SQL reutilizable contra el DWH vive en **`scripts/python/pipelines/queries/`** (un archivo por tabla).
- El DDL del data lake (`raw`, `stg`, `core`) vive en **`sql/`** versionado, plano e idempotente.
- **Alembic** queda exclusivamente para tablas internas de aplicación (audit, runs, `app_metrics` interno).

## Estructura del Repositorio

```text
/
├── dags/                                  # Directorio raíz de DAGs de Airflow
│   ├── _bootstrap.py                      # sys.path setup + on_failure_callback compartidos
│   ├── _templates/                        # Plantillas de referencia (ignoradas por Airflow)
│   │   ├── _template_dag.py.example
│   │   ├── _template_pipeline.py.example
│   │   ├── _template_transformer.py.example
│   │   └── _template_query.py.example
│   └── <dag_id>.py                        # DAG file (thin wrapper sobre un pipeline builder)
├── sql/                                   # DDL del data lake — SQL plano versionado
│   ├── README.md                          # Convenciones de naming + idempotencia + drift policy
│   ├── raw/                               # Landing layer (un archivo .sql por tabla)
│   ├── stg/                               # Staging (limpio, FKs resueltas)
│   └── core/                              # Modelo dimensional (dim_/fact_/bridge_)
├── scripts/
│   └── python/
│       └── pipelines/
│           ├── core/                      # Framework: Step, Pipeline, StepContext, exceptions
│           ├── queries/                   # SQL reutilizable al DWH (un archivo por tabla)
│           ├── extractors/                # Steps específicos de extracción del dominio
│           ├── transformations/           # Steps específicos de transformación del dominio
│           ├── loaders/                   # Steps específicos de carga del dominio
│           ├── examples/                  # Pipelines builders runnables de referencia
│           ├── config/
│           │   └── settings.py            # Pydantic settings cargados desde .env
│           └── utils/
│               ├── db/                    # DatabaseManager + get_db / SessionManager
│               └── migrate.py             # SQL migrations runner (sql/ → DWH)
├── alembic/                               # Migraciones SOLO de tablas internas de aplicación
│   ├── env.py
│   └── versions/                          # Definiciones de tablas internas (audit, app_metrics)
├── tests/                                 # pytest suite
│   ├── dags/                              # Integration tests (DagBag, metadatos del DAG)
│   └── scripts/python/                    # Unit tests de la lógica por capa
├── .env.example                           # Variables esperadas (incluye AIRFLOW_CONN_*)
├── pyproject.toml                         # Configuración de Ruff y pytest
├── requirements.txt                       # Dependencias del entorno de Airflow (rebuild on merge)
└── setup_local_env.sh                     # Validación + alembic upgrade head
```

## Pipeline Framework

Marco de trabajo en `scripts/python/pipelines/core/` que estandariza ETLs. Resuelve los tres problemas más comunes de DAGs hechos a mano:

- **Cero boilerplate de orquestación en el DAG**: el DAG solo arma `StepContext`, invoca `pipeline.run(ctx)` y devuelve métricas.
- **Contrato uniforme entre Extractor / Transformer / Loader**: cualquier nuevo flujo se compone declarativamente sin tocar el DAG.
- **Logging estructurado y manejo de errores consistente** por cada paso del pipeline.

| Componente | Archivo | Responsabilidad |
|---|---|---|
| `Step` (ABC) | `core/step.py` | Unidad de trabajo. Define `name`, `inputs` opcional, y `execute(ctx) -> Any`. |
| `Extractor` / `Transformer` / `Loader` | `core/step.py` | Subclases semánticas de `Step` que documentan el rol. |
| `StepContext` | `core/context.py` | Estado del run: `run_id`, `logical_date`, `params`, `artifacts`, `metrics`. |
| `Pipeline` | `core/pipeline.py` | Compone Steps en orden. Valida `inputs`, guarda outputs en `ctx.artifacts[step.name]`, registra ints como métricas, envuelve fallos en `StepError`. |
| Excepciones | `core/exceptions.py` | `PipelineError`, `StepError`, `MissingArtifactError`. |

### Reusable Steps disponibles

| Step | Módulo | Uso |
|---|---|---|
| `SqlExtractor` | `pipelines.extractors` | SELECT contra Postgres registrado → DataFrame |
| `BigQueryExtractor` | `pipelines.extractors` | Query a BigQuery → DataFrame |
| `PostgresLoader` | `pipelines.loaders` | DataFrame → tabla Postgres (`append` / `replace`) |
| `CsvLoader` | `pipelines.loaders` | DataFrame → archivo CSV |

## Organización de DAGs

Los DAGs viven en `dags/`. Convenciones:

1. **Thin DAG**: cada archivo es un wrapper mínimo sobre `build_<flujo>_pipeline()`.
2. **Bootstrap obligatorio**: cada DAG llama `setup_python_path()` antes de importar `pipelines.*`, e importa `pipelines.utils.db.postgresql_connect` para registrar conexiones.
3. **Sub-dominios opcionales**: para repos grandes, agrupar DAGs por dominio (`dags/<dominio>/<flujo>_dag.py`).
4. **Templates**: `dags/_templates/` contiene los esqueletos de referencia, ignorados por Airflow vía `.airflowignore`.

## Capas del DWH y separación con Alembic

| Carpeta / Herramienta | Dominio | Para qué sirve |
|---|---|---|
| `sql/raw/` | Esquema `raw` del DWH | Landing literal del archivo o DB fuente. Tipos crudos, sin FKs. |
| `sql/stg/` | Esquema `stg` del DWH | Limpio, tipos correctos, FKs del DWH resueltas (`driver_sk`, etc.). |
| `sql/core/` | Esquema `core` del DWH | Modelo dimensional consumible (dim_, fact_, bridge_). |
| `alembic/versions/` | Tablas internas de aplicación | Audit, runs, registros internos (`app_metrics` interno). **NUNCA** tocar `raw/stg/core`. |

El runner `scripts/python/pipelines/utils/migrate.py` aplica los archivos `sql/` por capa, con tracking interno en `_migrations.applied_files` (file_path, checksum SHA-256, applied_at). Si un archivo aplicado cambia, el runner falla con `MigrationDriftError`.

## Conexiones por capa

Las URIs viven en `.env` y se validan al arranque mediante Pydantic en `scripts/python/pipelines/config/settings.py`:

| Nombre interno | Variable de entorno | Notas |
|---|---|---|
| `org_dwh_raw` | `AIRFLOW_CONN_ORG_DWH_RAW` | Capa RAW del Data Warehouse. |
| `org_dwh_stg` | `AIRFLOW_CONN_ORG_DWH_STG` | Capa STG del Data Warehouse. |
| `org_dwh_core` | `AIRFLOW_CONN_ORG_DWH_CORE` | Capa CORE del Data Warehouse. También usada por Alembic. |

Las sesiones se obtienen siempre desde el singleton `DatabaseManager` (`pipelines.utils.db`):

```python
import pipelines.utils.db.postgresql_connect  # noqa: F401  -> registra todas las DBs
from pipelines.utils.db import get_db

with get_db("org_dwh_core") as session:
    ...
```

## CI/CD del scaffold

| Workflow | Trigger | Acción |
|---|---|---|
| `lint-test.yml` | PR / push a `main`, `develop` | Ruff lint + DAG validation (DagBag) + pytest |
| `deploy.yml` | Push a `main` (cambios en DAG/script) | Actualiza la revisión git-sync en el manifiesto k8s |
| `rebuild-image.yml` | Push a `main` (cambios en `requirements.txt`) | Dispara rebuild del Docker image (~10-15 min) |

Antes del deploy de DAGs es recomendable correr `python -m pipelines.utils.migrate` para aplicar pendientes del `sql/` y bloquear el merge si hay drift.
