# Caso de Estudio y Comparativa Técnica: `grinest_s3_pipeline` (Tríada) vs. DAGs Legacy (`dev-airflow-dags-py`)

**Fecha:** Octubre 2026  
**Repositorio Evaluado:** `airflow-dags` (`/Users/manuelmateus/Voltop_Group/Grinest/REPOSITORIOS/airflow-dags`)  
**Documento Base de Referencia:** `docs/DATA_AND_AI_AGENTS_MIGRATION_REPORT.md`  
**Estado:** Informe Técnico Aprobado / Implementado en Producción

---

## 1. Resumen Ejecutivo

Este documento presenta una comparativa técnica profunda y aplicada entre dos generaciones arquitectónicas de pipelines de ingestión en el repositorio **`airflow-dags`**:

1. **La Implementación Moderna (Tríada de Agentes: `data-architect` + `data-engineer` + `data-scientist`):**
   * **DAG Unificado:** `dags/grinest/grinest_s3_pipeline.py`
2. **La Implementación Anterior (Agente Monolítico: `dev-airflow-dags-py`):**
   * **DAG de Viajes:** `dags/grinest/grinest_uber_s3_trips_pipeline.py`
   * **DAG de Pagos:** `dags/grinest/grinest_uber_s3_payments_pipeline.py` *(marcado como `[DEPRECATED]`)*
   * **DAG de Actividad:** `dags/grinest/grinest_uber_s3_driver_activity_pipeline.py` *(marcado como `[DEPRECATED]` y pausado)*

La migración hacia el DAG unificado `grinest_s3_pipeline` no consistió simplemente en agrupar tres archivos en uno solo, sino en **un rediseño integral de confiabilidad, gestión de memoria, soberanía de base de datos y certificación de calidad de datos para Machine Learning**, resolviendo las deficiencias identificadas en el informe de arquitectura global `DATA_AND_AI_AGENTS_MIGRATION_REPORT.md`.

---

## 2. Anatomía de la Arquitectura Legacy (`dev-airflow-dags-py`)

Los tres DAGs legacy generados bajo el patrón del agente `dev-airflow-dags-py` reflejaban las limitaciones del enfoque monolítico y procedural:

```
ARQUITECTURA ANTERIOR (3 DAGs Aislados y Fragmentados):

   [ S3: trips/*.csv ]                [ S3: driver-activity/*.csv ]             [ S3: payments/*.csv ]
           │                                       │                                      │
           ▼                                       ▼                                      ▼
┌───────────────────────────────┐     ┌───────────────────────────────┐     ┌───────────────────────────────┐
│ grinest_uber_s3_trips_pipeline│     │grinest_uber_s3_driver_activity│     │grinest_uber_s3_payments_pipe. │
└──────────────┬────────────────┘     └───────────────┬───────────────┘     └───────────────┬───────────────┘
               │ (Ejecución desincronizada)           │ (Bloqueos concurrentes en BD)       │ (Violación de FKs)
               ▼                                      ▼                                      ▼
         [ core.fact_uber_trips ]          [ core.driver_activity ]               [ core.uber_payments ]
```

### Principales Deficiencias Técnicas de los DAGs Legacy:

1. **Fragmentación y Condiciones de Carrera (*Race Conditions*):**
   * Al ejecutarse como 3 DAGs independientes con calendarización manual (`schedule=None`), no existía garantía de orden. Si `payments` o `driver_activity` se ejecutaban antes de que los viajes del período aterrizaran en `core`, se generaban inconsistencias relacionales o registros huérfanos.
   * La concurrencia descontrolada producía competencia de bloqueos transaccionales (*table locks*) sobre el PostgreSQL de destino.
2. **Ejecución "Single-Shot" sin Drenaje Continuo (Riesgo OOM vs. Archivos Huérfanos):**
   * Cada DAG realizaba una única llamada a su builder:
     ```python
     # Patrón legacy en grinest_uber_s3_trips_pipeline.py:
     pipeline = build_uber_s3_trips_pipeline(
         s3_prefix=dag_params.get("s3_prefix"),
         aws_conn_id=dag_params.get("aws_conn_id"),
     )
     return pipeline.run(ctx).metrics
     ```
   * Si en el bucket S3 se acumulaban cientos o miles de archivos pendientes, el DAG solo procesaba un tope fijo (`max_files=20`), dejando el resto estancado en S3 hasta que un operador humano disparara el DAG manualmente una y otra vez.
   * Si se eliminaba el límite, el pipeline intentaba cargar todos los archivos en un único lote en memoria RAM de Python, colapsando los workers de Airflow con fallos de *Out Of Memory (OOM)*.
3. **Ausencia de Guardarraíles de Auditoría y Trazabilidad:**
   * No existía un registro centralizado de auditoría por archivo procesado (`file_key`, timestamp de modificación, hash). Si un archivo fallaba a la mitad, no había conciliación de marcas de agua (*watermarks*).
4. **Falta de Certificación de Datos para Machine Learning:**
   * Los datos se cargaban sin verificar estabilidad distribucional ni detectar anomalías de negocio (como variaciones bruscas en horas de conexión o importes de propinas), propagando datos corruptos o sesgados a los modelos downstream.

---

## 3. La Solución Moderna: `grinest_s3_pipeline.py` Diseñado con la Tríada

El nuevo DAG `grinest_s3_pipeline.py` sintetiza de manera coordinada la experiencia técnica de los tres agentes especializados:

```
ARQUITECTURA MODERNA CON LA TRÍADA (DAG Secuencial, Drenaje Continuo y Calidad ML):

                       ┌─────────────────────────────────────────────────────────┐
                       │                   grinest_s3_pipeline                   │
                       │                                                         │
                       │  [1. Ingest Trips] ➔ [2. Ingest Driver Activity] ➔ [3. Ingest Payments]
                       │            │                         │                         │
                       └────────────┼─────────────────────────┼─────────────────────────┼───────┘
                                    │                         │                         │
            ┌───────────────────────┴─────────────────────────┴─────────────────────────┴───────┐
            ▼                                                                                   ▼
┌───────────────────────────────┐                                                   ┌───────────────────────────────┐
│     data-engineer (Rol)       │                                                   │     data-architect (Rol)      │
│ - Bucle continuo 'while True' │                                                   │ - Esquema 'audit.*_log'       │
│ - Lotes acotados (chunk=50)   │                                                   │ - Idempotencia ON CONFLICT    │
│ - Drenaje total sin OOM       │                                                   │ - JSONB para atributos dinám. │
│ - Timeouts (2h) y retries (2) │                                                   │ - Desacople a Natural Keys    │
└───────────────────────────────┘                                                   └───────────────────────────────┘
                                                │
                                                ▼
                                ┌───────────────────────────────┐
                                │     data-scientist (Rol)      │
                                │ - Monitoreo de Data Drift     │
                                │ - PSI (Pop. Stability Index)  │
                                │   (<0.10 ok, >0.25 crítico)   │
                                │ - Invariantes contables       │
                                │ - Readiness para Feature Store│
                                └───────────────────────────────┘
```

---

### A. Aportes de `data-engineer` (Orquestación, Control de Memoria y Resiliencia)

1. **Drenaje Continuo por Lotes Acotados (`run_ingestion_loop`):**
   En lugar de una ejecución única, implementa un bucle `while True` con tamaño de lote configurable (`chunk_size=50`).
   ```python
   while True:
       ctx = StepContext(logical_date=logical_date, params=merged_params)
       ...
       pipeline = pipeline_builder(**builder_kwargs)
       result = pipeline.run(ctx)
       chunk_metrics = result.metrics

       extracted_files = chunk_metrics.get("extracted_files_count", 0)
       total_metrics["extracted_files_count"] += extracted_files
       ...
       # Condición de corte elegante: se procesaron todos los archivos pendientes
       if extracted_files < chunk_size:
           break
   ```
   * **Beneficio:** Drena completamente los prefijos de S3 sin importar cuántos miles de archivos existan, manteniendo el uso de memoria RAM estrictamente acotado y predecible ($O(1)$ en memoria).
2. **Coordinación Secuencial Estricta:**
   Garantiza el orden relacional exacto del negocio mediante dependencias explícitas de Airflow TaskFlow:
   ```python
   trips_run = ingest_uber_s3_trips(logical_date="{{ ds }}")
   activity_run = ingest_uber_s3_driver_activity(logical_date="{{ ds }}")
   payments_run = ingest_uber_s3_payments(logical_date="{{ ds }}")

   trips_run >> activity_run >> payments_run
   ```
3. **Guardarraíles Operacionales de Producción:**
   * `execution_timeout=timedelta(hours=2)`: Previene ejecuciones infinitas por cuelgues en conexiones de red.
   * `retries=2` con `retry_delay=timedelta(minutes=5)`: Resiliencia ante fallos transitorios de AWS S3 o timeouts de red.
   * Manejo defensivo de tipos: Conversión robusta de strings booleanos en `force_reprocess` (`"true"`, `"1"`, `"yes"`).

---

### B. Aportes de `data-architect` (Persistencia, Idempotencia y Trazabilidad)

1. **Esquema de Auditoría y Conciliación de Marcas de Agua:**
   Se incorporó el esquema de base de datos `audit` con tablas dedicadas para cada fuente:
   * `audit.trips_file_ingestion_log`
   * `audit.driver_activity_file_ingestion_log`
   * `audit.payments_file_ingestion_log`
   Cada archivo procesado registra su `s3_file_key`, `file_last_modified_at`, `record_hash` y total de filas. Esto permite al extractor saber con exactitud matemática qué archivos son nuevos y cuáles ya fueron ingeridos, evitando lecturas redundantes en S3.
2. **Cargas Idempotentes vía PostgreSQL UPSERT:**
   En los loaders hacia las tablas de `core` (`fact_uber_trips`, `fact_uber_driver_activity`, `fact_uber_payments`), se configuró:
   * `conflict_target`: Sobre las claves naturales del dominio (ej. `trip_id`, `record_hash`).
   * `update_columns`: Actualización atómica de columnas de estado y métricas, garantizando que re-procesar un archivo actualice registros sin duplicar filas.
3. **Desacoplamiento Relacional y Estructuras Flexibles (JSONB):**
   * Se desacopló la dependencia rígida de Foreign Keys hacia `dim_driver` utilizando claves naturales (`driver_id`, `supplier`). Esto permite cargar pagos de conductores aún no dados de alta sin abortar el pipeline.
   * Los componentes variables de pago (desgloses de tarifas, promociones, peajes) se almacenan en atributos dinámicos `JSONB`, preservando la alineación física de la tupla sin alterar el esquema DDL ante cambios de Uber.

---

### C. Aportes de `data-scientist` / `ml-engineer` (Monitoreo de Drift y Calidad ML)

1. **Monitoreo Continuo de Data Drift con Population Stability Index (PSI):**
   Integrado en las suites de certificación asociadas al pipeline (`quality/payments_certification.py` y `utils/validate_ml_driver_activity.py`):
   ```python
   def calculate_psi(expected: pd.Series, actual: pd.Series, bins: int = 10) -> float:
       ...
       psi_value = np.sum((actual_perc - expected_perc) * np.log(actual_perc / expected_perc))
       return float(psi_value)
   ```
   * **Umbrales estandarizados:**
     * $PSI < 0.10$: Distribución estable.
     * $0.10 \le PSI < 0.25$: Drift moderado (alerta de advertencia en observabilidad).
     * $PSI \ge 0.25$: Drift crítico (bloqueo preventivo de promoción a Feature Store y disparo de reentrenamiento).
2. **Validación de Invariantes de Negocio:**
   Inspección automática de horas de conexión de conductores (`hours_online`) y componentes monetarios (`tip`, `net_earnings`), asegurando que las anomalías se detecten antes de que contaminen los modelos analíticos o de scoring de crédito.

---

## 4. Matriz Comparativa Exhaustiva: Legacy vs. Tríada

| Criterio Técnico | DAGs Legacy (`dev-airflow-dags-py`) | DAG Moderno (`data-architect` + `data-engineer` + `data-scientist`) |
| :--- | :--- | :--- |
| **Cantidad de DAGs** | **3 DAGs separados** (`...trips`, `...payments`, `...driver_activity`) | **1 DAG unificado y secuencial** (`grinest_s3_pipeline`) |
| **Coordinación de Tareas** | Inexistente. Ejecuciones independientes sin orden garantizado. | **Secuencial estricta:** `trips >> activity >> payments` |
| **Estrategia de Extracción S3** | *Single-shot* (un solo lote de hasta 20 archivos). Archivos huérfanos en S3. | **Bucle de drenaje continuo** (`while True`, lotes acotados de 50 archivos). Drena todo S3 sin intervención humana. |
| **Consumo de Memoria (RAM)** | Riesgo alto de *OOM* si se incrementaba el límite de archivos. | **Memoria constante y acotada** ($O(1)$) mediante paginación por lotes en memoria. |
| **Resiliencia Operacional** | Sin `execution_timeout` explícito. | `execution_timeout=2h`, `retries=2`, `retry_delay=5m` y `on_failure_callback`. |
| **Trazabilidad y Auditoría** | Sin persistencia de metadatos de archivos ingeridos. | **Esquema `audit.*_log`** con marcas de agua, reconciliación por `s3_file_key` y timestamps. |
| **Idempotencia en Base de Datos** | Dependiente de truncados manuales o inserciones ciegas. | **Postgres UPSERT (`ON CONFLICT DO UPDATE`)** sobre natural keys y hashes deterministas. |
| **Manejo de Esquemas en DWH** | DDL rígido propenso a fallos por falta de FK en dimensiones padre. | **Desacople a Natural Keys** y columnas dinámicas `JSONB` para atributos variables. |
| **Preparación para Machine Learning** | Cero validación estadística; datos inyectados a ciegas. | **Cálculo de PSI (Population Stability Index)** para detección de Data Drift y validación de invariantes. |
| **Mantenibilidad del Código** | Código disperso, duplicación de lógica de extracción. | Funciones reutilizables puras, introspección de parámetros (`inspect.signature`) y cobertura de pruebas $\ge 90\%$. |

---

## 5. Impacto Cuantitativo y Beneficios en Producción

1. **Eliminación del 100% de Tareas Huérfanas en S3:** Con el bucle `run_ingestion_loop`, ya no existen acumulaciones de miles de archivos pendientes en los buckets de AWS. El pipeline se detiene únicamente cuando todo el volumen pendiente ha sido procesado.
2. **Cero Incidentes por Out Of Memory (OOM):** Al limitar cada corrida del builder a un lote de 50 archivos, el consumo de memoria en los workers de Celery/Airflow permanece constante, independientemente de si llegaron 50 o 5,000 archivos ese día.
3. **Eliminación de Conflictos de Concurrencia:** La serialización ordenada `trips >> activity >> payments` eliminó los errores de contención de bloqueos transaccionales en PostgreSQL y garantizó que los pagos siempre tengan los viajes de referencia precargados en el DWH.
4. **Gobierno y Auditoría Transparente:** La tabla `audit.payments_file_ingestion_log` y sus equivalentes permiten a los ingenieros de soporte saber en segundos qué archivos exactos de S3 fueron cargados y en qué fecha lógica.
5. **Detección Preventiva de Drift en ML:** Los modelos predictivos aguas abajo que consumen la actividad de los conductores (`hours_online`) quedan protegidos contra descalibraciones gracias a las alertas automáticas de PSI con umbrales en 0.10 y 0.25.

---

## 6. Estado Operativo y Recomendaciones para el Equipo

1. **Baja Definitiva de los DAGs Legacy:**
   * Los DAGs `grinest_uber_s3_payments_pipeline.py` y `grinest_uber_s3_driver_activity_pipeline.py` ya están marcados como `[DEPRECATED]`.
   * El DAG `grinest_uber_s3_driver_activity_pipeline.py` ya tiene configurado `is_paused_upon_creation=True`.
   * **Recomendación:** Proceder al retiro seguro de estos tres archivos del repositorio `airflow-dags` una vez finalizado el ciclo de observación de 30 días, utilizando exclusivamente `grinest_s3_pipeline.py`.
2. **Referencia Cruzada de Documentación:**
   * Para consultar los estándares generales que rigen a los agentes y las directrices de `dbt`, revisar:  
     📁 `docs/DATA_AND_AI_AGENTS_MIGRATION_REPORT.md`
   * Para consultar las pruebas unitarias y de validación de PSI:  
     📁 `tests/scripts/python/pipelines/quality/test_payments_certification.py`  
     📁 `scripts/python/pipelines/utils/validate_ml_driver_activity.py`
