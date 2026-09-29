---
name: data-engineer-airflow
description: Estándares de ingeniería de datos para Airflow + pandas + dbt: ingesta en bordes, carga idempotente y transformaciones dbt (staging, intermediate, marts).
---

# Data Engineer Skill (Airflow + pandas + dbt)

Este skill proporciona el conocimiento experto y los estándares no-negociables para diseñar, implementar, auditar y orquestar pipelines de datos robustos y de nivel de producción bajo el stack moderno: **Apache Airflow**, **pandas** y **dbt**.

---

## Restricciones Duras (Hard Constraints)

- **Orquestación Soberana en Apache Airflow**: Toda orquestación y calendarización vive en Airflow; los DAGs son la unidad atómica de programación utilizando preferentemente **TaskFlow API** (`@dag`, `@task`).
- **pandas EXCLUSIVAMENTE en los Bordes (Edges)**: pandas se permite ÚNICAMENTE en las etapas de extracción, normalización de APIs/JSON/CSV/archivos y validación Fail-Fast antes de que los datos toquen el Data Warehouse.
- **dbt es Dueño Absoluto de las Transformaciones in-Warehouse**: Todo join, agregación, cálculo de métricas de negocio, lógica dimensional (Kimball) y transformación posterior al aterrizaje en la base de datos pertenece exclusivamente a **dbt** (`staging` → `intermediate` → `marts`).
- **Antipatrón Estrictamente Prohibido**: NUNCA extraer datos que ya residen en tablas del warehouse hacia un DataFrame de pandas para limpiarlos o enriquecerlos y volver a insertarlos. Si los datos están en el warehouse, la transformación debe ser un modelo SQL en dbt.
- **Alineación Física de Tuplas**: Toda tabla creada para recibir datos de ingesta debe respetar el orden físico de columnas (de mayor a menor tamaño en bytes) definido en `data-architecture-postgre`.

---

## Recursos de Referencia Especializados

Para directrices técnicas detalladas, consultar los módulos en `references/`:

- **Ingesta y Extracción**: `references/extraction_patterns.md` — Resolución dual de conexiones (Airflow Hook vs Settings), hashing SHA-256 determinista para payloads JSON/APIs y catálogo desacoplado para archivos no estructurados.
- **Limpieza en el Borde con Pandas**: `references/transformation_patterns.md` — Principio Fail-Fast (`DataValidationError`), normalización obligatoria a UTC (`pd.to_datetime`), tipado nullable (`Int64`, `boolean`), sanitización y deduplicación sobre Natural Key (`_nk`).
- **Carga Idempotente a PostgreSQL**: `references/postgres_loading_patterns.md` — Carga masiva con tablas temporales unlogged (`COPY` / `StringIO`), merge atómico con `ON CONFLICT DO UPDATE`, guardarraíles de sesión (`lock_timeout = '2s'`) y observabilidad en `audit.pipeline_runs`.
- **Modelado In-Warehouse con dbt**: `references/dbt_transformation_patterns.md` — Capas de modelado (`staging`, `intermediate`, `marts`), patrón CTE modular, surrogate keys con `dbt_utils`, modelos incrementales (`merge`) y tests en `schema.yml`.
- **Orquestación con Astronomer Cosmos**: `references/cosmos_airflow_orchestration.md` — Integración híbrida de TaskFlow (`@task`) con `DbtTaskGroup`, retries y fallos con granularidad de modelo individual, configuración de `ProfileConfig` y fallback con `BashOperator`.
- **Scaffold y Testing Espejo**: `references/pipeline_testing_and_scaffold.md` — Jerarquía de directorios espejo, pruebas unitarias aisladas con `pytest`, tests de integridad de DAGs con `DagBag` y pruebas de compilación dbt en CI.

---

## Workflow del Ingeniero de Datos (5 Fases)

Cada vez que se solicite diseñar o implementar un pipeline de datos, seguir este ciclo de 5 fases:

```
1. Contrato & Extracción ➔ 2. Limpieza de Borde ➔ 3. Carga Idempotente ➔ 4. Modelado dbt ➔ 5. Orquestación & Test
```

### Fase 1: Descubrimiento y Extracción en el Borde
1. Identificar la fuente de datos (REST API, Webhook, archivo CSV/Parquet, base relacional).
2. Determinar si los datos son planos, semi-estructurados o binarios.
3. Extraer preservando el payload crudo y calculando el `record_hash` (SHA-256) para garantizar idempotencia.

### Fase 2: Limpieza y Normalización Fail-Fast (Python / pandas)
1. Cargar el lote en memoria en un DataFrame de pandas.
2. Validar el contrato de columnas obligatorias: si falta una columna, lanzar `DataValidationError` de inmediato.
3. Normalizar fechas y timestamps a UTC (`pd.to_datetime(..., utc=True)`).
4. Sanitizar textos (`str.strip()`, minúsculas en correos, códigos en mayúsculas).
5. Deduplicar registros sobre la Natural Key (`_nk`).

### Fase 3: Carga Masiva Idempotente en Staging (PostgreSQL / DWH)
1. Diseñar o validar la tabla destino en staging respetando el orden físico de columnas (8B → 4B → 2B → 1B → Varlena).
2. Crear tabla temporal `UNLOGGED ... ON COMMIT DROP`.
3. Volcar los datos a la tabla temporal mediante `copy_from` / streaming en memoria.
4. Ejecutar el merge atómico: `INSERT INTO stg.tabla SELECT ... FROM tmp_tabla ON CONFLICT (nk) DO UPDATE ...`.

### Fase 4: Modelado y Transformación in-Warehouse (dbt)
1. **Sources**: Declarar las tablas de staging en `models/staging/<source>/sources.yml`.
2. **Staging (`stg_`)**: Vistas 1:1, proyecciones explícitas, renombrado a `snake_case` y casting de tipos.
3. **Intermediate (`int_`)**: Joins multi-tabla y lógica intermedia compleja en vistas efímeras.
4. **Marts (`fct_` / `dim_`)**: Modelos dimensionales Kimball con Surrogate Keys (`dbt_utils.generate_surrogate_key`). Materializados como `table` o `incremental`.
5. **Calidad**: Definir tests genéricos (`unique`, `not_null`, `relationships`, `accepted_values`) y documentar en `schema.yml`.

### Fase 5: Orquestación, Linaje y Testing Espejo (Airflow + Cosmos)
1. Cablear el DAG en Airflow usando TaskFlow API (`@dag`, `@task`).
2. Conectar la salida de la tarea de carga hacia el `DbtTaskGroup` de Cosmos.
3. Configurar reintentos y timeouts apropiados.
4. Escribir pruebas unitarias en la ruta espejo `tests/` para los pasos de pandas y pruebas de integridad de DAGs.

---

## Entregables Obligatorios por Pipeline

Todo pipeline completado debe entregar:
1. **Esqueleto del DAG**: Archivo en `dags/*_dag.py` mostrando la secuencia `@task` de extracción/carga conectada al `DbtTaskGroup`.
2. **Transformador de Borde**: Función o clase `Step` en `pipelines/transformers/` con tipado estricto y validación Fail-Fast.
3. **Modelos dbt**: Archivos `.sql` en `dbt_project/models/` y su correspondiente `schema.yml` con tests y documentación.
4. **Configuración de Cosmos / Conexión**: Configuración desacoplada enlazada a la Connection de Airflow.
5. **Suite de Pruebas**: Tests unitarios en `tests/pipelines/` y validación de integridad en `tests/dags/`.
6. **Nota de Arquitectura**: Breve justificación del split ("por qué pandas en este borde y por qué dbt en esta transformación").

---

## Checklist de Aprobación de Pipelines

Antes de dar por finalizado un pipeline de datos, verificar el cumplimiento de:

- [ ] La orquestación corre en Apache Airflow bajo TaskFlow API (`@dag`, `@task`).
- [ ] pandas se utiliza estrictamente en el borde (ingesta, parseo y validación pre-warehouse).
- [ ] No existen joins, agrupaciones ni transformaciones analíticas en pandas sobre datos que ya están en el warehouse.
- [ ] El transformador de pandas implementa política Fail-Fast y lanza `DataValidationError` ante esquemas corruptos.
- [ ] Todos los timestamps están explícitamente convertidos a UTC.
- [ ] La carga a la base de datos es masiva e idempotente (evita inserciones individuales `INSERT INTO ... VALUES`).
- [ ] La tabla de staging cumple con el orden físico de columnas (alineación a 8 bytes).
- [ ] Los modelos dbt siguen la arquitectura de capas (`stg_` → `int_` → `fct_`/`dim_`).
- [ ] No existe `SELECT *` descontrolado en los modelos de dbt (proyección explícita en CTEs).
- [ ] Los modelos dbt cuentan con pruebas genéricas (`unique`, `not_null`) en `schema.yml`.
- [ ] La orquestación dbt en Airflow utiliza Cosmos (`DbtTaskGroup`) con reintentos a nivel de modelo individual.
- [ ] No se transmiten DataFrames pesados a través de XCom.
- [ ] Existen pruebas unitarias e integración en la jerarquía espejo de `tests/`.
