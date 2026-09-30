# Pipeline Scaffold & Mirror Testing: Airflow + pandas + dbt

Este documento define la arquitectura de scaffold del repositorio y la estrategia de **testing espejo** para certificar la fiabilidad, idempotencia y cobertura de pipelines de datos.

---

## 1. Arquitectura de Scaffold y Organización Espejo

El repositorio organiza el código fuente y sus pruebas en una jerarquía simétrica:

```text
/
├── dags/                               # Definición de DAGs de Airflow
│   └── ecommerce_orders_dag.py
├── pipelines/                          # Lógica desacoplada de extracción, limpieza y carga
│   ├── extractors/                     # Conectores y clientes de APIs / fuentes
│   │   └── customer_api_extractor.py
│   ├── transformers/                   # Transformadores de borde en pandas (Fail-Fast)
│   │   └── clean_customers.py
│   ├── loaders/                        # Carga masiva e idempotente a PostgreSQL / DWH
│   │   └── postgres_customer_loader.py
│   └── core/                           # Clases base: Step, StepContext, excepciones
├── dbt_project/                        # Proyecto dbt in-warehouse
│   ├── dbt_project.yml
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── marts/
│   └── tests/                          # Tests singulares en SQL
└── tests/                              # Pruebas automatizadas (Espejo estricto)
    ├── dags/
    │   └── test_dag_integrity.py       # Validación de DAGBag sin ciclos ni errores de sintaxis
    ├── pipelines/
    │   ├── extractors/
    │   │   └── test_customer_api_extractor.py
    │   ├── transformers/
    │   │   └── test_clean_customers.py
    │   └── loaders/
    │       └── test_postgres_customer_loader.py
    └── dbt/
        └── test_dbt_compilation.py     # dbt parse y compilación sintáctica
```

---

## 2. Testing Unitario de Transformadores Pandas (Fail-Fast)

Las pruebas unitarias de los pasos de transformación deben ejecutarse aisladas sin depender de la base de datos ni del scheduler de Airflow.

```python
import pytest
import pandas as pd
from datetime import datetime, timezone
from pipelines.core import StepContext
from pipelines.transformers.clean_customers import CleanCustomerDataTransformer, DataValidationError

@pytest.fixture
def base_context():
    return StepContext(
        dag_id="test_dag",
        run_id="test_run_123",
        logical_date=datetime(2024, 1, 1, 12, 0, tzinfo=timezone.utc),
    )

def test_clean_customer_transformer_success(base_context):
    # Arrange
    raw_payload = [
        {"customer_id": " 101 ", "email": " ALICE@EXAMPLE.COM ", "registration_date": "2024-01-01", "status": "active"},
        {"customer_id": "102", "email": "bob@example.com", "registration_date": "2024-01-02", "status": "INACTIVE"},
    ]
    base_context.set_artifact("raw_records", raw_payload)
    transformer = CleanCustomerDataTransformer()

    # Act
    transformer.execute(base_context)
    cleaned_df: pd.DataFrame = base_context.get_artifact("cleaned_customers_df")

    # Assert
    assert cleaned_df is not None
    assert len(cleaned_df) == 2
    assert cleaned_df.loc[0, "customer_nk"] == "101"
    assert cleaned_df.loc[0, "email"] == "alice@example.com"
    assert cleaned_df.loc[0, "status"] == "ACTIVE"
    assert cleaned_df.loc[0, "registration_at"].tzinfo is not None  # Verificación UTC
    assert base_context.metrics["transformed_rows"] == 2

def test_clean_customer_transformer_missing_mandatory_column_raises_error(base_context):
    # Arrange: payload sin columna 'status'
    raw_payload = [{"customer_id": "101", "email": "alice@example.com", "registration_date": "2024-01-01"}]
    base_context.set_artifact("raw_records", raw_payload)
    transformer = CleanCustomerDataTransformer()

    # Act & Assert (Fail-Fast)
    with pytest.raises(DataValidationError, match="Faltan columnas requeridas"):
        transformer.execute(base_context)

def test_clean_customer_transformer_duplicate_nk_raises_error(base_context):
    # Arrange: dos filas con la misma Natural Key
    raw_payload = [
        {"customer_id": "101", "email": "a@ex.com", "registration_date": "2024-01-01", "status": "ACTIVE"},
        {"customer_id": "101", "email": "b@ex.com", "registration_date": "2024-01-02", "status": "ACTIVE"},
    ]
    base_context.set_artifact("raw_records", raw_payload)
    transformer = CleanCustomerDataTransformer()

    # Act & Assert
    with pytest.raises(DataValidationError, match="Violación de unicidad de Natural Key"):
        transformer.execute(base_context)
```

---

## 3. Testing de Integridad de DAGs de Airflow

Garantiza que ningún DAG tenga ciclos, errores de sintaxis, variables faltantes en tiempo de carga o tiempos excesivos de parseo:

```python
import pytest
from airflow.models import DagBag

@pytest.fixture(scope="session")
def dag_bag():
    return DagBag(dag_folder="dags/", include_examples=False)

def test_no_import_errors(dag_bag):
    """Verifica que ningún archivo de DAG contenga SyntaxError o ImportError."""
    assert len(dag_bag.import_errors) == 0, f"Errores al cargar DAGs: {dag_bag.import_errors}"

def test_dag_tags_and_owners(dag_bag):
    """Garantiza que todos los DAGs tengan un owner y tags asignados."""
    for dag_id, dag in dag_bag.dags.items():
        assert dag.default_args.get("owner") is not None, f"DAG {dag_id} no tiene 'owner' configurado."
        assert len(dag.tags) > 0, f"DAG {dag_id} debe tener al menos un tag para categorización."
        assert dag.catchup is False, f"DAG {dag_id} debe tener catchup=False a menos que se justifique."
```

---

## 4. Testing de Modelos dbt en CI

En el pipeline de Integración Continua (CI), se valida que el proyecto dbt compile y no rompa relaciones referenciales:

```bash
# 1. Validar sintaxis y Jinja
dbt parse --project-dir dbt_project

# 2. Compilar modelos y linaje
dbt compile --project-dir dbt_project --target test

# 3. Ejecutar pruebas sobre entorno efímero / staging
dbt test --project-dir dbt_project --target test --select state:modified+
```

---

## 5. Auditoría y Métricas de Calidad

Todo paso de pipeline (`Step`) debe emitir métricas mediante `context.record_metric(key, value)`. Al finalizar el run:
- Las métricas se vuelcan en `audit.pipeline_runs` en PostgreSQL.
- Se alerta inmediatamente vía canal operativo (Slack/PagerDuty) si `transformed_rows == 0` habiendo `extracted_rows > 0` o si ocurrió un error de contrato.
