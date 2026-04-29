# State Management - Airflow DAGs

Este documento describe cómo se gestiona el estado y el flujo de información entre tareas en los pipelines de Airflow.

## XComs (Cross-Communication)

Se utilizan para pasar pequeñas cantidades de datos entre tareas.

- **Cuándo usar**: Para pasar metadatos, IDs de carga, o resultados de validaciones.
- **Limitaciones**: NO usar para pasar grandes volúmenes de datos (ej. DataFrames completos o archivos pesados). En su lugar, guardar el archivo en almacenamiento persistente (S3/GCS) y pasar la ruta por XCom.
- **TaskFlow API**: El valor retornado por una función decorada con `@task` se guarda automáticamente en XCom.

## Variables de Airflow

Utilizadas para configuraciones globales que cambian poco frecuentemente.

- **Uso**: Rutas base de APIs, flags de activación de funcionalidades, límites de reintentos globales.
- **Acceso**: Preferir el acceso vía `Variable.get("key", deserialize_json=True)`.

## Persistencia en Base de Datos

Para el estado persistente a largo plazo o resultados finales que consumen otros sistemas (como Dashboards), se utilizan tablas dedicadas gestionadas por **Alembic**.

- **Tablas de Auditoría**: Se utilizan para registrar qué lotes de datos han sido procesados (`pairing_audit_table`).
- **Registros de Métricas**: Las métricas calculadas se guardan en tablas de `unified_kpi` o registros específicos (`metric_registry`).
- **Punto de Verdad**: El estado de los KPIs siempre debe residir en la base de datos, no en los metadatos de Airflow.
