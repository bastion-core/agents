# Architecture - Airflow DAGs

Este documento describe la arquitectura y organización de los repositorios de DAGs de Apache Airflow construidos sobre el scaffold **`airflow-dags-scaffold`**.

## Estructura del Repositorio

```text
/
├── dags/                               # DAGs de Airflow (wrappers delgados)
│   ├── _bootstrap.py                   # setup_python_path() + default_on_failure_callback
│   ├── _templates/                     # Plantillas de referencia (ignoradas por Airflow)
│   └── <dominio>_<proceso>_dag.py      # Un DAG = un builder de Pipeline
├── scripts/python/pipelines/           # Lógica de los pipelines (sin dependencia de Airflow)
│   ├── core/                           # Framework: Step, Pipeline, StepContext, exceptions
│   ├── extractors/                     # Steps de extracción reutilizables y por fuente
│   ├── transformations/                # Steps de transformación (pandas)
│   ├── loaders/                        # Steps de carga (Postgres, CSV)
│   ├── queries/                        # SQL reutilizable al DWH (un archivo por tabla)
│   ├── examples/ | <dominio>/          # Builders build_<flujo>_pipeline()
│   ├── config/settings.py              # Settings Pydantic desde .env
│   └── utils/                          # db/ (DatabaseManager, get_db), migrate.py, logger
├── sql/                                # DDL del data lake, SQL plano versionado
│   ├── raw/   stg/   core/             # Un archivo .sql idempotente por tabla o cambio
├── alembic/                            # Migraciones SOLO de tablas internas de la app
├── tests/                              # Espejo de dags/ y scripts/python/pipelines/
├── pyproject.toml
└── requirements.txt                    # Cambios disparan rebuild de la imagen (~10-15 min)
```

## Principios de Diseño

1. **DAG delgado**: el DAG solo arma un `StepContext`, invoca `build_<flujo>_pipeline().run(ctx)` y retorna `result.metrics`. No contiene lógica de negocio.
2. **Pipeline declarativo**: `Pipeline(name=..., steps=[Extractor, Transformer, Loader])`. Cada Step es una unidad testeable sin Airflow ni base de datos.
3. **Capas del DWH**: `raw` (payload de la fuente, `record_hash`), `stg` (limpio y normalizado, clave natural `_nk`), `core` (`dim_*`, `fact_*`, `bridge_*`).
4. **Transformaciones**: la limpieza y normalización en el borde se hacen en pandas dentro de Steps de `transformations/`. Las agregaciones sobre datos que ya están en el DWH se prefieren como SQL set-based (queries o DDL de vistas) cuando el volumen lo justifica.

## Esquema de Base de Datos

- **`sql/` (data lake)**: toda tabla de `raw`, `stg` y `core` se crea y evoluciona con archivos `NNN_<tabla>[_<cambio>].sql` idempotentes, aplicados por `pipelines.utils.migrate`. Un archivo aplicado nunca se edita.
- **Alembic**: solo para tablas internas de la aplicación (auditoría de corridas, registries internos). Nunca toca `raw`, `stg` ni `core`.
- **Orden de despliegue**: la migración que crea o altera una tabla debe aplicarse antes de desplegar el DAG que la consume.

## Organización de DAGs

- Los archivos de DAG viven en `dags/` y se nombran `<dominio>_<proceso>_dag.py`.
- `dags/_templates/` contiene las plantillas de DAG, pipeline, query y transformer que todo DAG nuevo debe seguir.
- La lógica reutilizable entre dominios se ubica en `scripts/python/pipelines/`, nunca en `dags/`.
