# Pipelines de Reentrenamiento Automatizado y Feature Store (Feast)

Este documento define la arquitectura técnica para reentrenar modelos de forma desatendida y garantizar la coherencia de variables predictoras entre entrenamiento e inferencia.

---

## 1. Feature Store: Arquitectura y Point-in-Time Correctness

Un **Feature Store** (ej: Feast) resuelve dos problemas críticos en MLOps:
1. **Consistencia Train-Serve**: Garantiza que el código que calcula una variable para entrenar sea exactamente el mismo que alimenta la API en tiempo real.
2. **Point-in-Time Correctness**: Asocia a cada evento de entrenamiento el estado exacto de las features en el momento histórico en que ocurrió (`event_timestamp`), eliminando data leakage hacia el futuro.

```yaml
# feature_store/features.yaml
project: credit_scoring
registry: data/registry.db
provider: local
offline_store:
  type: file
online_store:
  type: redis
  connection_string: localhost:6379

entities:
  - name: user_id
    value_type: INT64
    join_key: user_id

features:
  - name: user_30d_transaction_count
    type: INT64
  - name: user_avg_order_value_usd
    type: FLOAT
```

---

## 2. DAG de Reentrenamiento Automatizado (Airflow + MLflow)

El pipeline de reentrenamiento se implementa como un DAG en Airflow orquestado con las siguientes etapas:

```python
"""dags/ml_retraining_dag.py"""

from datetime import datetime, timedelta

from airflow.decorators import dag, task


@dag(
    dag_id="credit_model_retraining_pipeline",
    start_date=datetime(2026, 1, 1),
    schedule="@weekly",
    catchup=False,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=5)},
)
def credit_model_retraining():
    @task
    def fetch_historical_features():
        """Extrae features point-in-time desde el Feature Store / Marts."""
        # Llamada a Feast / dbt marts para construir el training dataset
        return "data/processed/train_dataset.parquet"

    @task
    def train_and_evaluate_candidate(dataset_path: str):
        """Entrena candidato, evalúa en blind test y loguea a MLflow."""
        # Ejecuta script hermético de entrenamiento
        return "runs:/abc12345/model"

    @task
    def evaluate_promotion_gate(model_uri: str):
        """Compara candidato contra el champion activo en el Model Registry."""
        # Ejecuta promote_model_to_champion(...)
        pass

    dataset = fetch_historical_features()
    model = train_and_evaluate_candidate(dataset)
    evaluate_promotion_gate(model)


credit_model_retraining()
```
