# Cosmos & Airflow Orchestration: Integrating dbt into DAGs

Este documento define los estándares para orquestar proyectos de **dbt** dentro de **Apache Airflow** utilizando **Astronomer Cosmos**.

---

## 1. Filosofía de Integración Híbrida: TaskFlow + Cosmos

En la arquitectura moderna de datos:
1. **Extracción y Carga (Edges)**: Se orquestan con tareas decoradas con `@task` (TaskFlow API) en Python/pandas, ejecutando la validación fail-fast y la carga masiva idempotente hacia tablas de staging en PostgreSQL/Warehouse.
2. **Transformación in-Warehouse**: Se delega inmediatamente a **Astronomer Cosmos** mediante un `DbtTaskGroup`, el cual renderiza el proyecto dbt como un subgrafo de tareas nativas de Airflow.
3. **Granularidad de Fallos por Modelo**: Cada modelo dbt (`.sql`) y cada test dbt se ejecutan como un nodo independiente de Airflow. Si un modelo falla, Airflow permite reintentar **únicamente ese modelo**, evitando reprocesar todo el almacén o re-ejecutar la extracción.

---

## 2. Configuración Canónica de Astronomer Cosmos

Astronomer Cosmos desacopla la definición del proyecto dbt de la infraestructura de ejecución mediante 4 componentes de configuración:

```python
from pathlib import Path
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, RenderConfig, ExecutionConfig
from cosmos.profiles import PostgresUserPasswordProfileMapping

# 1. Ruta del proyecto dbt
DBT_PROJECT_PATH = Path("/opt/airflow/dbt_project")

# 2. ProjectConfig: Localización del código y manifests
project_config = ProjectConfig(
    dbt_project_path=DBT_PROJECT_PATH,
)

# 3. ProfileConfig: Resolución dinámica de credenciales desde Airflow Connections
profile_config = ProfileConfig(
    profile_name="ecommerce_dwh",
    target_name="prod",
    profile_mapping=PostgresUserPasswordProfileMapping(
        conn_id="postgres_dwh",
        profile_args={"schema": "public"},
    ),
)

# 4. RenderConfig: Filtros de selección dbt (equivalente a --select)
render_config = RenderConfig(
    select=["path:models/staging/ecommerce", "path:models/marts/core"],
    exclude=["tag:deprecated"],
)

# 5. ExecutionConfig: Ruta al binario de dbt en entorno aislado
execution_config = ExecutionConfig(
    dbt_executable_path="/home/airflow/.local/bin/dbt",
)
```

---

## 3. DAG Canónico Híbrido (TaskFlow + Cosmos)

A continuación se presenta el patrón canónico para un pipeline completo de ingesta de borde, carga idempotente y transformación dbt:

```python
from datetime import datetime, timedelta
from airflow.decorators import dag, task
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, RenderConfig
from cosmos.profiles import PostgresUserPasswordProfileMapping

from pipelines.extractors.customer_api_extractor import extract_raw_customers
from pipelines.transformers.clean_customers import clean_and_validate_customers
from pipelines.loaders.postgres_customer_loader import bulk_load_staging_customers
from pipelines.audit.audit_manager import record_pipeline_metrics

DEFAULT_ARGS = {
    "owner": "data_engineering",
    "retries": 2,
    "retry_delay": timedelta(minutes=3),
}

@dag(
    dag_id="ecommerce_customers_ingestion_and_dbt_dag",
    default_args=DEFAULT_ARGS,
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["ecommerce", "pandas", "dbt", "cosmos"],
)
def customer_pipeline():

    @task
    def extract_edge_data() -> dict:
        """Extrae datos crudos desde la API externa preservando JSON/payloads."""
        return extract_raw_customers()

    @task
    def transform_edge_data(raw_payload: dict) -> dict:
        """Limpia y valida tipos, unicidad y UTC con pandas bajo Fail-Fast."""
        return clean_and_validate_customers(raw_payload)

    @task
    def load_staging(cleaned_data: dict) -> dict:
        """Carga masiva idempotente a PostgreSQL usando COPY y temp table upsert."""
        return bulk_load_staging_customers(cleaned_data)

    # 4. Subgrafo de transformación dbt orquestado por Cosmos
    dbt_transformations = DbtTaskGroup(
        group_id="dbt_customer_transformations",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt_project"),
        profile_config=ProfileConfig(
            profile_name="ecommerce_dwh",
            target_name="prod",
            profile_mapping=PostgresUserPasswordProfileMapping(
                conn_id="postgres_dwh",
                profile_args={"schema": "public"},
            ),
        ),
        render_config=RenderConfig(
            select=["tag:customers"],
        ),
    )

    @task
    def finalize_pipeline(load_summary: dict):
        """Registra métricas y confirma observabilidad en audit.pipeline_runs."""
        record_pipeline_metrics(load_summary)

    # Definición de dependencias
    raw = extract_edge_data()
    cleaned = transform_edge_data(raw)
    load_summary = load_staging(cleaned)

    # El DbtTaskGroup espera a que la carga de staging termine
    load_summary >> dbt_transformations >> finalize_pipeline(load_summary)

customer_pipeline()
```

---

## 4. Alternativa Fallback: BashOperator / KubernetesPodOperator

Si el entorno no cuenta con `astronomer-cosmos` instalado o se requiere un runner desacoplado en Kubernetes:

```python
from airflow.operators.bash import BashOperator

dbt_run = BashOperator(
    task_id="dbt_run_marts",
    bash_command="""
        set -e
        cd /opt/airflow/dbt_project
        dbt run --profiles-dir . --target prod --select tag:customers
        dbt test --profiles-dir . --target prod --select tag:customers
    """,
    env={"DBT_ENV_SECRET_PASSWORD": "{{ conn.postgres_dwh.password }}"},
)
```

---

## 5. Guardarraíles de Orquestación

- **Prohibido enviar DataFrames por XCom**: XCom solo transmite metadatos, URIs de almacenamiento (S3/GCS) o recuentos de filas.
- **Mapeo Seguro de Conexiones**: Nunca hardcodear credenciales en `profiles.yml`; utilizar siempre `profile_mapping` de Cosmos para enlazar con `Airflow Connection`.
- **Aislamiento de Dependencias**: Si pandas o dbt requieren versiones conflictivas de paquetes, usar `VirtualenvOperator` o `KubernetesPodOperator`.
