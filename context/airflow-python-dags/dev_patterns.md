# Development Patterns - Airflow DAGs

Este documento define los estándares de desarrollo y patrones recomendados para la creación de DAGs de Airflow en Python.

## TaskFlow API

Se prefiere el uso de la **TaskFlow API** (`@dag`, `@task`) sobre el uso manual de operadores tradicionales siempre que sea posible.

### Ejemplo Recomendado
```python
from airflow.decorators import dag, task
from datetime import datetime

@dag(start_date=datetime(2024, 1, 1), schedule="@daily", catchup=False)
def example_etl():
    @task
    def extract():
        return {"data": "raw_data"}

    @task
    def transform(data: dict):
        return data["data"].upper()

    @task
    def load(processed_data: str):
        print(f"Loading: {processed_data}")

    load(transform(extract()))

example_etl()
```

## Operadores y Hooks

Cuando la TaskFlow API no es suficiente (ej: interacciones complejas con servicios externos), se deben usar Operadores estándar o Custom Hooks.

- **Idempotencia**: Todas las tareas DEBEN ser idempotentes. Si una tarea se ejecuta dos veces con los mismos parámetros, el resultado final en el sistema de destino debe ser el mismo.
- **Manejo de Conexiones**: Nunca hardcodear credenciales. Usar siempre `BaseHook.get_connection()` o pasar el `conn_id` a los operadores.

## Estándares de Nomenclatura

- **DAG IDs**: Deben ser descriptivos y seguir el patrón `{dominio}_{proceso}_dag`. Ejemplo: `metrics_login_success_rate_dag`.
- **Task IDs**: Usar `snake_case`. En TaskFlow API, el nombre de la función es el ID de la tarea por defecto.
- **Archivos**: Los archivos de DAGs deben terminar en `_dag.py`.

## Documentación

Cada DAG debe incluir un docstring detallado explicando:
- Propósito del pipeline.
- Fuente y destino de los datos.
- Frecuencia esperada y consideraciones de re-ejecución.
