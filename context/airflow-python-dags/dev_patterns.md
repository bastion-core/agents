# Development Patterns - Airflow DAGs

Este documento define los estándares de desarrollo para DAGs de Airflow construidos sobre el framework `Step` / `Pipeline` / `StepContext` del scaffold.

## DAG Delgado con TaskFlow API

Se usa la **TaskFlow API** (`@dag`, `@task`). El DAG expone una sola tarea que construye el contexto y ejecuta el pipeline:

```python
from __future__ import annotations

from datetime import datetime, timedelta

from _bootstrap import default_on_failure_callback, setup_python_path

setup_python_path()

from airflow.decorators import dag, task  # noqa: E402

import pipelines.utils.db.postgresql_connect  # noqa: E402, F401
from pipelines.core import StepContext  # noqa: E402
from pipelines.metrics.login_success_rate import build_login_success_rate_pipeline  # noqa: E402


@dag(
    dag_id="metrics_login_success_rate_dag",
    default_args={
        "owner": "data-team",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "execution_timeout": timedelta(minutes=30),
        "on_failure_callback": default_on_failure_callback,
    },
    description="Calcula la tasa diaria de logins exitosos",
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["metrics", "auth"],
)
def metrics_login_success_rate_dag():
    @task
    def run_pipeline(logical_date: str, window_start: str, window_end: str) -> dict[str, int]:
        ctx = StepContext(
            logical_date=logical_date,
            params={"window_start": window_start, "window_end": window_end},
        )
        return build_login_success_rate_pipeline().run(ctx).metrics

    run_pipeline(
        logical_date="{{ ds }}",
        window_start="{{ data_interval_start }}",
        window_end="{{ data_interval_end }}",
    )


metrics_login_success_rate_dag()
```

## Reglas de Confiabilidad

Estas reglas aplican a todo DAG y Step nuevo o modificado.

### Idempotencia
- Ejecutar dos veces el mismo DAG run (mismo `logical_date`) debe dejar el destino en el mismo estado, sin duplicados.
- Escrituras al DWH: upsert con `INSERT ... ON CONFLICT (<clave>) DO UPDATE | DO NOTHING`, con la clave por capa (`raw` → `record_hash`, `stg` → `_nk`, `core.dim_*` → id externo, `core.fact_*` → grano declarado en el `.sql`).
- Un `append` simple solo es aceptable si antes se borra la partición de la ventana (`DELETE ... WHERE <ts> >= :window_start AND <ts> < :window_end`) dentro de la misma transacción.
- Cargas grandes: preferir inserción por lotes (`execute_values`, `COPY` a tabla temporal + merge) sobre inserciones fila por fila.

### Ventanas de tiempo deterministas
- Los límites de extracción salen de `data_interval_start` / `data_interval_end` (o `ds`) pasados por `ctx.params`, como intervalo semiabierto `>= start AND < end`.
- Prohibido usar `datetime.now()`, `date.today()` o `CURRENT_TIMESTAMP` como límite de datos. Sí se permiten para columnas de auditoría (`created_at`, `updated_at`).

### Validación en el borde (Fail-Fast)
- Cada Transformer valida el contrato de columnas obligatorias de su input y lanza una excepción explícita si falta alguna, en vez de continuar con datos incompletos.
- Timestamps normalizados a UTC (`pd.to_datetime(..., utc=True)`); columnas `TIMESTAMPTZ` en el DWH.
- Deduplicar sobre la clave natural antes de cargar.
- Usar tipos nullable de pandas (`Int64`, `boolean`) para no convertir enteros a float por la presencia de NULL.

### Reintentos y tiempos límite
- Tareas con I/O externo (APIs, BigQuery, Postgres): `retries` ≥ 1 con `retry_delay` razonable; considerar `retry_exponential_backoff=True` para APIs con rate limit.
- Definir `execution_timeout` en DAGs que alimentan dashboards con horario de consumo.
- `on_failure_callback=default_on_failure_callback` siempre.

### SQL set-based cuando los datos ya están en el DWH
- Si los datos ya residen en el DWH y la transformación es un join o agregación, preferir SQL ejecutado en la base de datos sobre extraerlos a pandas y reinsertarlos.
- pandas sigue siendo la herramienta para normalizar fuentes externas (APIs, archivos, BigQuery) y para lógica que no se expresa bien en SQL.

## Operadores y Conexiones

- Fuera del framework (operadores nativos) se usa `PostgresHook(postgres_conn_id=...)` u operadores del provider.
- Dentro de `scripts/python/pipelines/` se usa `get_db("<conn_name>")` tras importar `pipelines.utils.db.postgresql_connect`.
- Nunca hardcodear credenciales: Airflow Connections o `Settings` (Pydantic) desde variables de entorno.

## Estándares de Nomenclatura

- **DAG IDs**: `{dominio}_{proceso}_dag`, snake_case. Ejemplo: `metrics_login_success_rate_dag`.
- **Archivos de DAG**: terminan en `_dag.py`.
- **Steps**: una clase pública por archivo en `extractors/`, `transformations/` o `loaders/`; `name` único en snake_case.
- **Builders**: `build_<flujo>_pipeline()`.
- **Owner**: distinto de `airflow`. Al menos un tag. `catchup=False`.

## Documentación

Cada DAG incluye un docstring con:
- Propósito del pipeline.
- Fuente y destino de los datos (tablas `schema.tabla`).
- Frecuencia esperada y comportamiento ante re-ejecución o backfill manual.
