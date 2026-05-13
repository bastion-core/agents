---
name: airflow-dags-py
description: Estándares de arquitectura y patrones de desarrollo para DAGs de Apache Airflow en Python sobre el scaffold con Pipeline framework (Step/Pipeline/StepContext), Queries Module, DWH raw/stg/core y migraciones SQL planas.
---

# Airflow DAGs Development Skill

Este skill proporciona el conocimiento experto para diseñar e implementar pipelines de datos sobre el scaffold **`airflow-dags-scaffold`**. La filosofía: el DAG es **delgado**, la lógica vive en **Steps** componibles, el SQL reutilizable vive en **`pipelines/queries/`**, el DDL del data lake vive en **`sql/`** versionado y plano, y Alembic queda **solo** para tablas internas de aplicación.

## Recursos Disponibles

- **Arquitectura**:
  - `references/architecture.md`: Estructura del repositorio (dags/, sql/, scripts/python/pipelines/), separación `sql/` (data lake) vs Alembic (app internal), conexiones por capa.
- **Patrones de Desarrollo**:
  - `references/dev_patterns.md`: Pipeline framework (Step/Pipeline/StepContext), thin DAG, Reusable Steps, Queries Module, `@as_step`, DWH naming conventions (raw/stg/core), reglas CI obligatorias.
- **Gestión de Estado**:
  - `references/state_management.md`: Artefactos del `StepContext`, métricas auto-registradas, XComs solo para el resultado del run, persistencia en tablas del DWH (no en metadata Airflow).

## Instrucciones de Uso

### 1. Diseño de Arquitectura

Al diseñar un pipeline nuevo o modificar uno existente:

1. Consultar `references/architecture.md` para ubicar correctamente cada artefacto:
   - DAG en `dags/<dag_id>.py` (o subcarpeta de dominio si aplica).
   - Pipeline builder en `scripts/python/pipelines/examples/<flujo>.py` (o `<dominio>/<flujo>.py`).
   - Steps específicos en `scripts/python/pipelines/{extractors,transformations,loaders}/<entity>.py`.
   - Queries reutilizables en `scripts/python/pipelines/queries/<tabla>.py`.
   - DDL del DWH en `sql/<schema>/NNN_<tabla>.sql`.
2. Si el cambio agrega columnas/tablas al DWH, **primero** redactar el `.sql` en la capa correcta (`raw/`, `stg/` o `core/`) siguiendo las reglas de idempotencia del scaffold.
3. Decidir si la persistencia operacional necesita Alembic (solo para tablas internas como `app_metrics`, audit, runs) o `sql/` (cualquier cosa del data lake).

### 2. Implementación de DAGs

Al escribir el DAG:

1. **Regla del thin DAG**: el archivo en `dags/` solo debe armar `StepContext`, invocar `pipeline.run(ctx)` y devolver `result.metrics`. **Cero lógica de negocio**.
2. Bootstrap obligatorio al inicio del archivo:
   ```python
   from _bootstrap import default_on_failure_callback, setup_python_path
   setup_python_path()

   from airflow.decorators import dag, task                # noqa: E402
   import pipelines.utils.db.postgresql_connect            # noqa: E402, F401
   from pipelines.core import StepContext                  # noqa: E402
   from pipelines.examples.<flujo> import build_<flujo>_pipeline   # noqa: E402
   ```
3. Cumplir las **reglas CI obligatorias** (validadas automáticamente):
   - DAG ID en snake_case (`^[a-z][a-z0-9_]*$`).
   - `default_args["owner"]` ≠ `"airflow"`.
   - Al menos un tag (`tags=[...]`).
   - `catchup=False` (no negociable).
   - `description="..."` presente.
   - `ruff check` y `ruff format` limpios.
4. Usar siempre `default_on_failure_callback` del bootstrap como `on_failure_callback` para tener logging estructurado uniforme.

### 3. Composición del Pipeline

1. Cada flujo expone un único builder `build_<flujo>_pipeline() -> Pipeline` en `pipelines/examples/<flujo>.py` (o `<dominio>/<flujo>.py`).
2. Preferir Steps **pre-construidos** del framework cuando alcancen:
   - `SqlExtractor` — SELECT contra Postgres registrado → DataFrame.
   - `BigQueryExtractor` — query a BigQuery → DataFrame.
   - `PostgresLoader` — DataFrame → tabla Postgres (`append` / `replace`).
   - `CsvLoader` — DataFrame → archivo CSV.
3. Crear Steps custom (`Extractor` / `Transformer` / `Loader`) solo cuando se necesite lógica específica del dominio. Ubicaciones:
   - `pipelines/extractors/<source>.py`
   - `pipelines/transformations/<entity>.py`
   - `pipelines/loaders/<entity>.py`
4. Usar `@as_step(name=..., inputs=..., kind="transformer")` solo para lógica puntual no reutilizable. Si la lógica se repite o crece, promoverla a clase.
5. Declarar siempre `inputs = ["<step_previo>"]` cuando un Step depende de un upstream — el `Pipeline` valida que el artefacto exista antes de ejecutar.

### 4. Queries Module

Para SQL reutilizable contra el DWH:

1. **Una tabla del DWH = un archivo en `pipelines/queries/<tabla>.py`**. Si la tabla aún no tiene archivo, se crea.
2. **Una consulta = una función plana** cuyo primer argumento es `session: Session` de SQLAlchemy. Sin clases, sin estado mutable.
3. SQL inline con `text(...)`, parámetros bindeados (no f-strings):
   ```python
   def get_uber_id_map(session: Session) -> dict[str, int]:
       """{uber_driver_id (lowercase): driver_sk} para conductores activos."""
       rows = session.execute(text("""
           SELECT LOWER(uber_driver_id::text), driver_sk
           FROM core.dim_driver
           WHERE uber_driver_id IS NOT NULL AND is_current = true
       """)).fetchall()
       return dict(rows)
   ```
4. **Lo que NO va en `queries/`**:
   - SELECTs full-table de la fuente (eso vive dentro del Extractor que la posee).
   - Bulk INSERT/UPSERT genéricos (eso vive en `pipelines/utils/db.upsert_df`).
5. Promover a clase (`repositories/<tabla>_repository.py`) solo cuando aparezca: cache intra-run, lógica de negocio adicional, estado mutable compartido (SCD2 multi-dim).

### 5. DWH Schema Migrations (`sql/`)

Para DDL del data lake (`raw`, `stg`, `core`):

1. **Naming**: `NNN_<tabla>.sql` (creación, secuencial dentro del esquema) o `NNN_<tabla>_<descripcion>.sql` (cambio posterior).
2. **Idempotencia obligatoria**: usar siempre los guards:
   ```sql
   CREATE SCHEMA IF NOT EXISTS core;
   CREATE TABLE IF NOT EXISTS core.dim_driver (...);
   CREATE INDEX IF NOT EXISTS dim_driver_grinest_idx ON core.dim_driver(grinest_driver_id);
   ALTER TABLE core.dim_driver ADD COLUMN IF NOT EXISTS phone TEXT;
   ```
3. **Nunca editar un archivo aplicado** — el runner detecta drift por SHA-256 y rechaza el run. Para cambios, **agregar un nuevo archivo** con el `ALTER` correspondiente.
4. Header obligatorio con `-- Owner:` y `-- Purpose:` en cada archivo.
5. Orden mental: `raw → stg → core`. `core.fact_*` referencia `core.dim_*`.
6. Ejecutar `python -m pipelines.utils.migrate` (o `--dry-run` para ver pendientes) en CI antes del deploy de DAGs.
7. Alembic queda **solo** para tablas internas de aplicación. Si una migración Alembic toca `raw/stg/core`, mover a `sql/<schema>/`.

### 6. Conexiones a Base de Datos

1. Bootstrap **una sola vez** por proceso (en el DAG, antes del primer `get_db()`):
   ```python
   import pipelines.utils.db.postgresql_connect  # noqa: F401
   ```
2. Sesiones efímeras vía context manager (preferido):
   ```python
   from pipelines.utils.db import get_db
   with get_db("org_dwh_core") as session:
       ...
   ```
3. `SessionManager("<conn>")` solo cuando el repositorio gestiona explícitamente la sesión.
4. Conexiones registradas por capa: `org_dwh_raw`, `org_dwh_stg`, `org_dwh_core` (más las propias del proyecto).
5. Agregar una nueva conexión sigue 4 pasos: `.env.example` → campo en `Settings` (Pydantic) → `configure_database(...)` en `postgresql_connect.py` → consumo via `get_db("<name>")`.

### 7. Manejo de Errores y Logging

- `Pipeline(stop_on_error=True)` (default): el primer Step que falla aborta el run y propaga `StepError(step_name, pipeline_name, original)`. Airflow muestra el stack y aplica `retries`.
- `Pipeline(stop_on_error=False)`: solo cuando los Steps son genuinamente independientes (ej. cargar varios archivos).
- `MissingArtifactError`: el `Pipeline` valida `step.inputs` antes de ejecutar; se lanza si falta el artefacto upstream.
- Eventos automáticos del framework: `pipeline_started`, `step_started`, `step_completed`, `step_failed`, `pipeline_completed`. Cualquier agregador (Loki, Datadog, ELK) puede correlacionar por `run_id` y `pipeline`.

## Reglas de Trabajo – Ingeniería de Datos

### Construir únicamente lo que el pipeline necesita ahora
Nunca crear tablas, funciones, DAGs, Steps o columnas a menos que el stack completo exista hoy: extractor + transformación + loader + DAG + DDL en `sql/`. No crear dimensiones placeholder, ni tablas solo con seeds, ni esquemas especulativos. Si se discute una integración futura, dejar una nota `## Próximos pasos` en la conversación — no tocar el código.

### Usar lo que Postgres ya ofrece
Evitar recrear funcionalidad nativa. Las fechas y timestamps viven en columnas `DATE` / `TIMESTAMP` — no en una tabla `dim_date`. Usar `DATE_TRUNC`, `EXTRACT`, `TO_CHAR`, `GENERATE_SERIES` directamente en las consultas. Añadir una tabla de lookup solo cuando contenga datos que no puedan derivarse (p. ej. `dim_driver`, `dim_fleet`).

### Usar la estructura ya existente
Antes de diseñar algo nuevo, leer:
- Los `sql/<schema>/*.sql` aplicados.
- Los Steps de `pipelines/extractors/`, `pipelines/transformations/`, `pipelines/loaders/`.
- Las queries de `pipelines/queries/`.
- Los pipelines builders de `pipelines/examples/`.

Reutilizar `upsert_df`, `get_db`, los Reusable Steps (`SqlExtractor`, `PostgresLoader`...) y el patrón de capas `raw → stg → core` ya establecido. Respetar los nombres de columnas (`<entity>_sk`, `<entity>_nk`, `<system>_<entity>_id`, `record_hash`), las claves de conflicto por capa y la lógica de upsert que ya están en el repositorio.

### Respetar el contrato de naming del DWH

| Capa | Tabla | Conflict target upsert |
|---|---|---|
| `raw` | `raw.<source>_<entity>` | `[record_hash]` |
| `stg` | `stg.<source>_<entity>` (mismo nombre que raw) | NK compuesta del dominio |
| `core` | `core.dim_<entity>` | external_id del sistema fuente |
| `core` | `core.fact_<entity>[_<grain>]` | SK + grano temporal + dimensión secundaria |
| `core` | `core.bridge_<e1>_<e2>` | SK1 + SK2 + timestamp inicio |

**Anti-patterns a evitar**:
- Renombrar la misma columna entre capas (ej. `supplier_account` vs `supplier_nk`).
- Propagar typos de la fuente (`refound_tolls` en vez de `refund_tolls`) — renombrar al limpiar en `stg`.
- Mezclar centinelas y NULL para "ausencia" en la misma semántica (preferir NULL).
- Hardcodear columnas a valores fijos en el loader (`df['col'] = 0`); si siempre vale lo mismo no debería existir.

### Probar cada join y cada columna que debería tener datos
Después de escribir una transformación o loader, verificar el conteo de filas y la tasa de valores no nulos en las columnas clave antes de declararlo terminado:

```sql
-- patrón rápido de sanity check
SELECT
    COUNT(*)                          AS total_rows,
    COUNT(driver_sk)                  AS driver_sk_filled,
    COUNT(activity_date)              AS date_filled,
    MIN(activity_date),
    MAX(activity_date)
FROM core.fact_driver_activity;
```

Si se espera que un join haga match (p. ej. resolución de driver), verificar la tasa de match explícitamente:

```sql
SELECT match_status, COUNT(*) FROM stg.uber_driver_activity GROUP BY 1;
```

Una columna que siempre es `NULL` es un bug, no un estado válido — investigar antes de continuar.

### Visibilizar datos vacíos o faltantes inmediatamente
Si una tabla, columna o lookup no tiene datos cuando debería tenerlos, detenerse y reportarlo:

- Mostrar al usuario la consulta exacta y el resultado.
- Pedir los datos fuente o credenciales faltantes si ese es el bloqueante.
- Si el usuario no puede proveerlo en la sesión actual, añadir una nota `## Bloqueado / próximos pasos` listando exactamente qué se necesita y por qué, y continuar con el trabajo no bloqueado.

Nunca aceptar silenciosamente resultados vacíos ni saltar una capa porque los datos "vendrán después".

### Probar — o indicar al usuario exactamente cómo probar
Después de cada cambio, ejecutar la tarea del DAG, el pipeline builder, o la función de Python correspondiente y revisar el output. Validación local del pipeline:

```bash
PYTHONPATH=scripts/python python3 -c "
import pipelines.utils.db.postgresql_connect  # noqa: F401
from pipelines.core import StepContext
from pipelines.examples.<flujo> import build_<flujo>_pipeline
print(build_<flujo>_pipeline().run(StepContext()).metrics)
"
```

Si la ejecución directa no es posible (sin acceso a DB, sin Airflow, sin archivo), decirlo explícitamente y entregar al usuario el comando o consulta exacta a ejecutar:

```
No puedo conectarme a la instancia de Airflow desde aquí.
Ejecuta esto para verificar:
  docker exec -it <container> airflow tasks test <dag_id> <task_id> <date>
Luego revisa:
  SELECT COUNT(*) FROM core.fact_driver_activity WHERE activity_date = '<date>';
```

Nunca marcar una tarea como completa sin haberla ejecutado tú mismo o entregar al usuario un paso de verificación concreto.

### Validación previa al PR

Antes de abrir un PR:

```bash
# Lint/format
ruff check dags/ scripts/python/ tests/
ruff format --check dags/ scripts/python/ tests/

# Migraciones SQL (dry-run)
python -m pipelines.utils.migrate --dry-run

# Tests
pytest tests/ -v --cov=scripts/python/pipelines --cov-report=term-missing
```
