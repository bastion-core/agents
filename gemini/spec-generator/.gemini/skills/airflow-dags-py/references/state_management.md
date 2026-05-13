# State Management - Airflow DAGs

Cómo se gestiona el estado y el flujo de información en pipelines construidos sobre el scaffold **`airflow-dags-scaffold`**. Hay **tres mecanismos** distintos, cada uno con su rol claro:

1. **`StepContext`** — estado intra-run del Pipeline framework (transferencia de datos entre Steps).
2. **XComs / Variables / Connections de Airflow** — metadata operacional y configuración.
3. **Persistencia en el DWH (`sql/`) y tablas internas (Alembic)** — estado de negocio que sobrevive al run.

## 1. StepContext (estado intra-run del Pipeline)

`StepContext` es el contenedor que viaja por todo el Pipeline. Reemplaza el patrón de pasar DataFrames por XCom (que está prohibido).

### Estructura

```python
from pipelines.core import StepContext

ctx = StepContext(logical_date="2026-05-13")
ctx.params = {"lookback_days": 7}     # parámetros opcionales del run
# ctx.artifacts                       # dict poblado por el Pipeline (output de cada Step)
# ctx.metrics                         # dict poblado por el Pipeline (ints retornados)
```

### Convención de artefactos

- Cada `Step.execute(ctx)` retorna su artefacto (típicamente un `pandas.DataFrame` para E/T, un `int` rowcount para L).
- El `Pipeline` lo guarda automáticamente en `ctx.artifacts[step.name]`.
- Si el output es `int`, también lo registra en `ctx.metrics[step.name]` (auto-métrica).
- El siguiente Step declara qué upstream necesita en `inputs = ["nombre_del_step_previo"]` y lo lee con `self.get_input(ctx, "nombre_del_step_previo")`.
- El `Pipeline` valida la presencia del artefacto **antes** de ejecutar el Step y falla con `MissingArtifactError` si falta.

### Helpers de `StepContext`

```python
ctx.set_artifact("extract_drivers", df)         # útil en tests para pre-poblar inputs
df = ctx.get_artifact("extract_drivers")        # lectura directa (equivalente a get_input)
ctx.metrics["custom_count"] = 42                # registrar una métrica manualmente
```

### Tamaño de los artefactos

Los artefactos viven **en memoria** durante el run. Para volúmenes grandes:
- Si el DataFrame cabe en RAM del worker → OK pasarlo por `ctx.artifacts`.
- Si no cabe → escribirlo a almacenamiento persistente (S3/GCS) en el Extractor y pasar la **ruta** como artefacto. El Transformer/Loader lo re-lee chunked.
- Para pipelines crónicamente grandes, considerar dividir en múltiples DAGs encadenados con `ExternalTaskSensor`.

## 2. XComs (Cross-Communication de Airflow)

XComs siguen siendo válidos, pero su uso queda **acotado**:

### Uso permitido
- Devolver el dict de **métricas finales** del Pipeline (`return result.metrics`) — es lo único que el `@task` retorna a Airflow para visibilidad en UI.
- Pasar metadatos pequeños entre tasks de Airflow cuando el pipeline está partido en múltiples `@task`s.
- IDs de carga, resultados de validaciones, flags de control.

### Uso prohibido
- ❌ DataFrames completos.
- ❌ Listas voluminosas (> ~1k elementos).
- ❌ Objetos serializados pesados.

> Para esos casos, usar `StepContext.artifacts` dentro de un mismo `@task` o storage persistente (S3/GCS/path en disco) entre `@task`s.

### TaskFlow API
El valor retornado por una función decorada con `@task` se guarda automáticamente en XCom — por eso conviene retornar solo `result.metrics` (dict de ints), no estructuras grandes.

## 3. Variables de Airflow

Para configuraciones globales que cambian poco:

- **Uso típico**: rutas base de APIs, flags de activación de funcionalidades, límites de reintentos globales, fechas de corte.
- **Acceso**:
  ```python
  from airflow.models import Variable
  config = Variable.get("my_pipeline_config", deserialize_json=True)
  ```
- **No usar** Variables como reemplazo de `Settings` (Pydantic). El scaffold ya tiene un sistema de configuración tipado en `pipelines/config/settings.py` cargado desde `.env`.

## 4. Connections de Airflow

Connection objects de Airflow se usan **solo** dentro de operadores nativos:

```python
from airflow.providers.postgres.hooks.postgres import PostgresHook
hook = PostgresHook(postgres_conn_id="org_dwh_core")
```

Pero dentro del Pipeline framework (`scripts/python/pipelines/`), preferir siempre el `DatabaseManager` singleton:

```python
import pipelines.utils.db.postgresql_connect  # noqa: F401
from pipelines.utils.db import get_db

with get_db("org_dwh_core") as session:
    ...
```

El bootstrap registra todas las conexiones desde las URIs declaradas en `Settings` (`AIRFLOW_CONN_ORG_DWH_RAW`, `AIRFLOW_CONN_ORG_DWH_STG`, `AIRFLOW_CONN_ORG_DWH_CORE`).

## 5. Persistencia en Base de Datos

### Punto de verdad: el DWH

El estado de negocio (KPIs, facts, dimensiones) **siempre vive en el DWH**, no en metadata de Airflow. Si tenés que reconstruir el estado, debe ser posible re-ejecutando los DAGs contra los `sql/` aplicados.

### Separación clara: `sql/` vs Alembic

| Mecanismo | Qué tablas gestiona | Quién las consume |
|---|---|---|
| **`sql/raw/`, `sql/stg/`, `sql/core/`** | Esquemas del data lake (`raw`, `stg`, `core`) | Pipelines del scaffold (Steps, queries) |
| **`alembic/versions/`** | Tablas internas de aplicación (audit, runs, `app_metrics` interno) | Lógica operacional, dashboards internos |

> Si una nueva tabla representa datos del data lake (ingesta, staging, modelo dimensional, KPI persistente) → va en `sql/`. Si representa estado interno del propio repo (qué runs corrieron, qué archivos se procesaron, qué configs activas hay) → va en Alembic.

### Patrones de persistencia comunes

- **Tablas de auditoría**: registrar qué lotes/archivos han sido procesados (`raw.<source>_processed_files` con `record_hash` y `processed_at`). Soporta resume después de fallos.
- **Tablas de KPI/métrica final**: `core.fact_*` o `app_metrics.kpi_*` con conflict target idempotente (SK + grano temporal). Las pueden consumir dashboards externos (Metabase, Grafana, Looker).
- **Registros de ejecución del Pipeline**: si la org necesita histórico de runs (rowcount por Step, duración, errores), modelar una tabla `app_metrics.pipeline_runs` vía Alembic y poblarla desde un Loader final del Pipeline.

### Idempotencia obligatoria

Toda escritura debe ser idempotente. Re-ejecutar el mismo run debe converger al mismo estado:

| Capa | Mecanismo |
|---|---|
| `raw.*` | `ON CONFLICT (record_hash) DO NOTHING` |
| `stg.*` | `ON CONFLICT (<NK_compuesta>) DO UPDATE SET ...` |
| `core.dim_*` | `ON CONFLICT (<external_id>) DO UPDATE SET ...` (con SCD2 si aplica) |
| `core.fact_*` | `ON CONFLICT (<SK + grano>) DO UPDATE SET ...` |
| `core.bridge_*` | `ON CONFLICT (<SK1 + SK2 + timestamp_inicio>) DO NOTHING` |

El helper `pipelines.utils.db.upsert_df` ya implementa este patrón — preferirlo en lugar de armar el SQL a mano.

## 6. Logging estructurado del Pipeline

El framework emite eventos automáticos via `pipelines.core.logging_utils.log_event`, que adjunta un payload estructurado (`pipeline_event`) en `record.extra`:

| Evento | Cuándo |
|---|---|
| `pipeline_started` / `pipeline_completed` | Inicio y fin del run, incluye `step_count` y `metrics` |
| `step_started` / `step_completed` | Por cada Step, incluye `output_type` y `metric` (si aplica) |
| `step_failed` | Step lanzó excepción, incluye `error` |

Cualquier agregador (Loki, Datadog, ELK) puede correlacionar por `run_id` (UUID generado en `StepContext`) y `pipeline` (nombre del Pipeline).

Adicionalmente, `default_on_failure_callback` del bootstrap loggea CRITICAL para cualquier task que falle, con `task_id`, `dag_id` y `error`. Acá se enchufa Slack/PagerDuty cuando la org lo necesita.
