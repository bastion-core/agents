# Development Patterns - Airflow DAGs

Estándares de desarrollo y patrones recomendados para crear DAGs sobre el scaffold **`airflow-dags-scaffold`** con el Pipeline framework, Queries Module y migraciones SQL planas.

## 1. Thin DAG (regla obligatoria)

El DAG **no contiene lógica de negocio**. Su única responsabilidad es orquestar la ejecución de un Pipeline.

### Estructura canónica del DAG

```python
"""DAG: drivers_sync
Description: Sync drivers from source DB to warehouse.
Schedule: 0 7 * * *
Owner: bi-team
"""
from __future__ import annotations

from datetime import datetime, timedelta

from _bootstrap import default_on_failure_callback, setup_python_path

setup_python_path()

from airflow.decorators import dag, task                              # noqa: E402
import pipelines.utils.db.postgresql_connect                          # noqa: E402, F401
from pipelines.core import StepContext                                # noqa: E402
from pipelines.drivers.sync_pipeline import build_drivers_sync_pipeline  # noqa: E402


@dag(
    dag_id="drivers_sync",
    schedule="0 7 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args={
        "owner": "bi-team",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "on_failure_callback": default_on_failure_callback,
    },
    description="Sync drivers from source DB to warehouse",
    tags=["drivers", "framework"],
)
def drivers_sync_dag():
    @task
    def run(logical_date: str) -> dict[str, int]:
        ctx = StepContext(logical_date=logical_date)
        return build_drivers_sync_pipeline().run(ctx).metrics

    run(logical_date="{{ ds }}")


drivers_sync_dag()
```

### Reglas CI obligatorias por DAG (validadas automáticamente)

| Regla | Validación |
|---|---|
| No import errors | DagBag carga el DAG sin errores |
| snake_case ID | `dag_id` matchea `^[a-z][a-z0-9_]*$` |
| Owner explícito | `default_args["owner"]` ≠ `"airflow"` |
| Al menos un tag | `tags=[...]` no vacío |
| Sin catchup | `catchup=False` (no negociable) |
| Descripción | `description="..."` presente |
| Style | `ruff check` + `ruff format` limpios |

### Bootstrap compartido (`dags/_bootstrap.py`)

- `setup_python_path()` resuelve el repo root y agrega `<repo>/scripts/python` al `sys.path`. Indispensable para que `from pipelines.* import ...` funcione.
- `default_on_failure_callback(context)` loggea estructuradamente la falla. Si la org agrega Slack/PagerDuty, se hace acá una sola vez.

## 2. Pipeline Framework

### Crear un Step custom

Cada Step va en su propio archivo, una clase pública por archivo. Convención:
- `pipelines/extractors/<source>.py`
- `pipelines/transformations/<entity>.py`
- `pipelines/loaders/<entity>.py`

```python
# pipelines/transformations/drivers_transformer.py
import pandas as pd

from pipelines.core import StepContext, Transformer


class DriversTransformer(Transformer):
    name = "transform_drivers"
    inputs = ["extract_drivers"]   # validado antes de ejecutar

    def execute(self, ctx: StepContext) -> pd.DataFrame:
        raw: pd.DataFrame = self.get_input(ctx, "extract_drivers")
        return raw.assign(full_name=raw["full_name"].str.strip().str.title())
```

### Componer un Pipeline

Cada flujo expone **un único builder** `build_<flujo>_pipeline()`:

```python
# pipelines/drivers/sync_pipeline.py
from pipelines.core import Pipeline
from pipelines.extractors.drivers_extractor import DriversExtractor
from pipelines.loaders.drivers_loader import DriversLoader
from pipelines.transformations.drivers_transformer import DriversTransformer


def build_drivers_sync_pipeline() -> Pipeline:
    return Pipeline(
        name="drivers_sync",
        steps=[
            DriversExtractor(),
            DriversTransformer(),
            DriversLoader(),
        ],
    )
```

### Reusable Steps (preferidos cuando aplican)

```python
from pipelines.core import Pipeline
from pipelines.extractors import SqlExtractor, BigQueryExtractor
from pipelines.loaders import PostgresLoader, CsvLoader

def build_daily_active_drivers() -> Pipeline:
    return Pipeline(
        name="daily_active_drivers",
        steps=[
            SqlExtractor(
                name="extract_active_drivers",
                query="SELECT id, full_name FROM public.driver WHERE last_trip_at >= CURRENT_DATE - INTERVAL '1 day'",
                db_name="org_dwh_core",
            ),
            PostgresLoader(
                name="load_active_drivers",
                inputs=["extract_active_drivers"],
                db_name="org_dwh_core",
                schema="app_metrics",
                table="kpi_active_drivers_daily",
                mode="append",
            ),
        ],
    )
```

### Escape hatch: `@as_step`

Para Steps puntuales NO reutilizables (lógica que solo aplica a este pipeline), evitar declarar una clase y usar el decorador:

```python
import pandas as pd
from pipelines.core import as_step

@as_step(name="filter_top_drivers", inputs=["extract_drivers"], kind="transformer")
def filter_top_drivers(ctx) -> pd.DataFrame:
    df = ctx.get_artifact("extract_drivers")
    return df.nlargest(50, "revenue")
```

- La función debe recibir un único argumento `ctx: StepContext`.
- `kind ∈ {"extractor", "transformer", "loader", "step"}` — solo afecta la clase base semántica.
- La función original queda accesible en `.fn` para tests: `filter_top_drivers.fn(StepContext(...))`.
- Si la lógica se repite en otro pipeline o crece, **promoverla a clase** en `transformations/`.

## 3. Queries Module

### Regla de oro

> **Una tabla del DWH = un archivo en `pipelines/queries/`. Una consulta = una función plana cuyo primer argumento es `Session`.**

```
pipelines/queries/
├── dim_driver.py
├── dim_city.py
├── dim_fleet.py
├── raw_batch_payments.py
└── ...
```

### Forma canónica

```python
# pipelines/queries/dim_driver.py
"""Consultas a core.dim_driver."""

from sqlalchemy import text
from sqlalchemy.orm import Session


def get_uber_id_map(session: Session) -> dict[str, int]:
    """{uber_driver_id (lowercase): driver_sk} para conductores activos."""
    rows = session.execute(text("""
        SELECT LOWER(uber_driver_id::text), driver_sk
        FROM core.dim_driver
        WHERE uber_driver_id IS NOT NULL AND is_current = true
    """)).fetchall()
    return dict(rows)
```

### Cómo un Step consume una query

```python
from pipelines.core import StepContext, Transformer
from pipelines.queries import dim_driver
from pipelines.utils.db import get_db


class ResolveDriverIdentity(Transformer):
    name = "resolve_driver_identity"
    inputs = ["transform_uber_activity"]

    def execute(self, ctx: StepContext):
        df = self.get_input(ctx, "transform_uber_activity")
        with get_db("org_dwh_core") as session:
            mapping = dim_driver.get_uber_id_map(session)
        df["driver_sk"] = df["uber_driver_id"].astype(str).map(mapping)
        return df
```

### Lo que NO va en `queries/`

| Caso | Donde va | Razón |
|---|---|---|
| `SELECT a, b, c FROM source.tabla` (extracción full-table de la fuente) | Dentro del **Extractor Step** que la posee | Materia prima de un solo pipeline; no se reusa |
| Bulk INSERT/UPSERT parametrizado | `pipelines/utils/db.upsert_df` | Helper transversal, no SQL específico de tabla |
| Lookups con muchas variantes + invariantes (SCD2, transactional writes) | El **Loader Step** orquesta llamando funciones granulares de `queries/<tabla>.py` | Mantiene queries planas; promover a clase solo si crece |

### Cuándo promover a clase

Cuando aparezca alguno de estos olores:

- Una misma consulta se quiere **cachear** dentro del run y reusar en multiples Steps.
- Hay **lógica de negocio** además del SQL (validaciones, reglas previas a un INSERT).
- Múltiples consultas comparten **estado mutable** (ej. SCD2 multi-dim que requiere la misma sesión transaccional).

En ese momento, `queries/dim_driver.py` se transforma en `repositories/dim_driver_repository.py` con clase. Migración lineal: las funciones se vuelven métodos. **No empezar por ahí.**

## 4. DWH Naming Conventions

### Esquemas = capas

| Esquema | Rol | Contenido | Idempotencia |
|---|---|---|---|
| `raw` | Landing literal | Tipos crudos, sin FKs del DWH | `record_hash` (SHA-256 sobre row estable) |
| `stg` | Limpio + FKs resueltas | Mismo dominio que `raw`, listo para enriquecer hechos | NK compuesta del dominio fuente |
| `core` | Modelo dimensional | `dim_*`, `fact_*`, `bridge_*` | SK + grano temporal |

### Nombres de tabla

```
raw.<source>_<entity>            # raw.uber_trips,  raw.hunter_distance,  raw.batch_driver_payments
stg.<source>_<entity>            # stg.uber_trips  (mismo nombre que raw — SOLO cambia el esquema)
core.dim_<entity>                # core.dim_driver,  core.dim_city,  core.dim_vehicle
core.fact_<entity>[_<grain>]     # core.fact_uber_trips,  core.fact_driver_payments_weekly
core.bridge_<e1>_<e2>            # core.bridge_vehicle_driver
```

**Reglas:**

- El nombre del dominio **persiste a través de las capas** raw → stg. Solo el salto a `core` antepone `dim_` / `fact_` / `bridge_`.
- El prefijo `<source>_` (`uber_`, `hunter_`) se incluye cuando la fuente importa para el lector. Si el dominio es propio, se omite (`batch_driver_payments`, `energy_sessions`).
- El sufijo `_<grain>` solo aparece en `fact_*` agregados (`_weekly`, `_daily`). Si el fact es transaccional (un row = un evento), no se sufija.

### Columnas estándar

| Tipo | Patrón | Ejemplos |
|---|---|---|
| Surrogate key | `<entity>_sk` | `driver_sk`, `city_sk` |
| Natural key | `<entity>_nk` | `city_nk='bogota'`, `fleet_nk='yo_quiero'` |
| External ID por sistema fuente | `<system>_<entity>_id` | `grinest_driver_id`, `uber_driver_id` |
| Hash de idempotencia | `record_hash` | obligatorio en `raw.*` |
| SCD Type 2 metadata | `valid_from`, `valid_to`, `is_current` | exclusivo de `core.dim_*` con histórico |
| Trazabilidad de archivo | `source_file` | en raw + stg + core de fuentes archivo |
| Match driver→DWH | `match_status ∈ {matched, unmatched}` | en `stg.*` que resuelven FK |
| Timestamps operacionales | `created_at`, `updated_at` | crudo de la fuente |
| Timestamps de negocio | `activity_date`, `payment_date`, `week_start`, `week_end`, `started_at`, `ended_at` | semántica del evento |

### Conflict targets de upsert (regla por capa)

| Capa | Conflict target | Por qué |
|---|---|---|
| `raw.*` | `[record_hash]` | Dedup pura por contenido — re-procesar el mismo archivo no duplica |
| `stg.*` | NK compuesta del dominio | Permite re-correr el pipeline y refrescar columnas derivadas |
| `core.dim_*` | External ID del sistema fuente (ej. `grinest_vehicle_id`) | Una fila por entidad de negocio |
| `core.fact_*` | SK + grano temporal (ej. `driver_sk + activity_date + supplier_nk`) | Idempotencia por evento |
| `core.bridge_*` | SK1 + SK2 + timestamp inicio | Soporta histórico de la relación |

### Anti-patterns a evitar

- **Renombrar la misma columna entre capas** (ej. `supplier_account` en `raw` y `supplier_nk` en `stg`/`core`). Decidir un nombre y mantenerlo.
- **Propagar typos de la fuente** (ej. `refound_tolls` en lugar de `refund_tolls`). Renombrar al limpiar en `stg`.
- **Mezclar centinelas y NULL** para "ausencia". Elegir uno (preferir `NULL`).
- **Hardcodear columnas a valores fijos en el loader** (ej. `df['refund_account_confirmation'] = 0`). Si la columna siempre vale lo mismo, no debería existir.

## 5. DWH Schema Migrations (`sql/`)

DDL versionada del data lake en SQL plano. Reglas de oro:

1. **Naming**: `NNN_<tabla>.sql` (creación, secuencial dentro del esquema) o `NNN_<tabla>_<descripcion>.sql` (cambio posterior).
2. **Idempotencia obligatoria**: usar siempre `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
3. **Nunca editar un archivo aplicado** — el runner detecta drift por SHA-256 y rechaza el run. Para cambios, agregar un nuevo archivo con el `ALTER`.
4. **Header obligatorio**:
   ```sql
   -- core/003_dim_driver.sql
   -- Owner: bi-team
   -- Purpose: Dimension SCD2 de conductores con identidad multi-sistema.
   ```
5. **Orden de aplicación**: `raw → stg → core`. `core.fact_*` referencia `core.dim_*`.
6. **Cada archivo en su propia transacción** (Postgres soporta DDL transaccional).
7. **Alembic** queda solo para tablas internas de aplicación. Si una migración Alembic toca `raw/stg/core`, mover a `sql/<schema>/`.

### Uso del runner

```bash
python -m pipelines.utils.migrate              # aplica pendientes
python -m pipelines.utils.migrate --dry-run    # ver pendientes sin aplicar
python -m pipelines.utils.migrate --mark-applied  # bootstrap: registrar sin ejecutar
```

## 6. Conexiones a Base de Datos

```python
# Bootstrap UNA sola vez por proceso (en el DAG)
import pipelines.utils.db.postgresql_connect  # noqa: F401

# Sesión efímera (preferida)
from pipelines.utils.db import get_db
with get_db("org_dwh_core") as session:
    result = session.execute(text("SELECT count(*) FROM ..."))

# Sesión "owned" (cuando el repositorio gestiona la sesión)
from pipelines.utils.db import SessionManager
manager = SessionManager("org_dwh_core")
try:
    repo = SomeRepository(manager.session)
    repo.do_work()
    manager.commit()
finally:
    manager.close()
```

Conexiones esperadas: `org_dwh_raw`, `org_dwh_stg`, `org_dwh_core` (más las propias del proyecto).

Nuevas conexiones siguen 4 pasos:
1. Añadir URI a `.env.example` (y al `.env` local).
2. Declarar campo en `Settings` (`scripts/python/pipelines/config/settings.py`).
3. Registrar en `scripts/python/pipelines/utils/db/postgresql_connect.py` con `configure_database(...)`.
4. Consumir vía `get_db("<name>")` o `SessionManager("<name>")`.

## 7. Manejo de Errores y Logging

- `Pipeline(stop_on_error=True)` (default): primer Step que falla aborta el run y propaga `StepError(step_name, pipeline_name, original)`. Airflow muestra el stack y aplica `retries`.
- `Pipeline(stop_on_error=False)`: solo cuando los Steps son genuinamente independientes.
- `MissingArtifactError`: el `Pipeline` valida `step.inputs` antes de ejecutar; indica qué artefacto falta.
- Eventos automáticos vía `pipelines.core.logging_utils.log_event`:

| Evento | Cuándo |
|---|---|
| `pipeline_started` / `pipeline_completed` | Inicio y fin del run, incluye `step_count` y `metrics` |
| `step_started` / `step_completed` | Por cada Step, incluye `output_type` y `metric` (si aplica) |
| `step_failed` | Step lanzó excepción, incluye `error` |

Cualquier agregador (Loki, Datadog, ELK) puede correlacionar por `run_id` y `pipeline`.

## 8. Estándares de Nomenclatura

- **DAG IDs**: snake_case, descriptivos. Patrón habitual: `<dominio>_<proceso>` (ej. `drivers_sync`, `daily_active_drivers`).
- **Pipeline names**: snake_case, idem al `dag_id` cuando 1:1.
- **Step names**: snake_case con verbo + objeto (`extract_drivers`, `transform_sales`, `load_active_drivers`).
- **Task IDs**: en TaskFlow API, el nombre de la función es el ID por defecto.
- **Archivos**:
  - DAG: `dags/<dag_id>.py` (sin sufijo `_dag.py` obligatorio; el scaffold acepta ambos).
  - Pipeline builder: `pipelines/<dominio>/<flujo>_pipeline.py` o `pipelines/examples/<flujo>.py`.
  - Step: `pipelines/{extractors,transformations,loaders}/<entity>.py`.
  - Query: `pipelines/queries/<tabla>.py` (nombre exacto de la tabla del DWH).

## 9. Documentación

Cada DAG debe incluir un docstring detallado:

```python
"""DAG: <dag_id>
Description: <una línea explicando qué hace el pipeline>
Schedule: <cron o None>
Owner: <equipo>
"""
```

Cada Pipeline builder y Step deben tener docstring breve explicando su propósito. Las queries en `queries/` deben tener una línea que indique qué retornan y para qué sirven.
