# State Management - Airflow DAGs

Este documento describe cómo se gestiona el estado y el flujo de información entre Steps, tareas y corridas.

## StepContext (dentro de una corrida)

El estado de una corrida del pipeline vive en el `StepContext`, en memoria, dentro de la misma tarea de Airflow:

- `logical_date`: fecha que representa el DAG run (`{{ ds }}`).
- `params`: parámetros de entrada (ventana `window_start` / `window_end`, lookback, etc.).
- `artifacts`: outputs de cada Step, indexados por nombre del Step. Aquí sí pueden viajar DataFrames.
- `metrics`: contadores enteros (filas extraídas, transformadas, cargadas). Un Step que retorna `int` registra la métrica automáticamente.

## XComs (entre tareas)

- Solo metadatos pequeños: `result.metrics`, IDs de lote, rutas de archivos.
- Nunca DataFrames ni datasets. Si dos tareas necesitan compartir datos voluminosos, se persisten en almacenamiento (S3/GCS o una tabla `stg`) y se pasa la referencia.
- En TaskFlow API el valor retornado por `@task` se guarda en XCom automáticamente; por eso el `@task` del DAG retorna solo `result.metrics`.

## Variables de Airflow

- Configuración global que cambia poco: rutas base de APIs, flags de activación.
- Acceso con `Variable.get("key", deserialize_json=True)` dentro de la tarea, no a nivel de módulo (evita consultas a la base de metadatos en cada parseo).

## Persistencia en Base de Datos

- **Punto de verdad**: los resultados (KPIs, métricas, dimensiones) residen en el DWH (`core`, `unified_kpi`, `metric_registry`), no en los metadatos de Airflow.
- **Auditoría de corridas**: las tablas internas de auditoría se gestionan con Alembic. Si un pipeline registra sus métricas de corrida, usa esas tablas existentes en vez de crear tablas paralelas.
- **Columnas de auditoría por fila**: `created_at` / `updated_at` (`TIMESTAMPTZ`) y `source_file` cuando la fuente es un archivo.
