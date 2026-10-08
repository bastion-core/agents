# Informe Técnico y Arquitectónico: Evolución de Agentes de Datos e IA, Red de QA y Adopción de dbt en el Data Warehouse

**Fecha:** Octubre 2026  
**Autor:** Data & AI Platform Engineering  
**Audiencia:** Equipo de Ingeniería, Datos, Arquitectura y Producto  
**Estado:** Vigente / Aprobado

---

## 1. Resumen Ejecutivo y Razón Estratégica del Cambio

Con el escalamiento de nuestros repositorios y la diversificación de iniciativas analíticas y predictivas, la arquitectura de agentes requería evolucionar desde un modelo artesanal y acoplado hacia un estándar de nivel empresarial.

Se ha tomado la decisión estratégica de:
1. **Eliminar el agente monolítico `dev-airflow-dags-py`** (y sus skills asociadas `airflow-dags-py` y `qa-airflow-dags-py`).
2. **Introducir una Tríada de Especialistas:**
   - **`data-architect`**: Diseño físico de esquemas PostgreSQL, DDL seguro con cero downtime, eliminación de padding de tuplas y modelado Kimball.
   - **`data-engineer`**: Ingesta ligera en los bordes con Airflow (TaskFlow API) + pandas, orquestación con Astronomer Cosmos y soberanía absoluta de **`dbt`** para transformaciones in-warehouse.
   - **`data-scientist`**: Inferencia estadística rigurosa, modelos predictivos sin fuga de datos (*data leakage*), ciclo de vida MLOps (MLflow, Model Registry, drift monitoring) y servido de ultra baja latencia con FastAPI.
3. **Desplegar una Red de Agentes de Confiabilidad (QA Dedicado):**
   - **`qa-data-architect`**: Auditoría de bloqueos DDL, índices en Foreign Keys, RLS y alineación de memoria.
   - **`qa-data-engineer`**: Auditoría de idempotencia en backfills, SLAs, reintentos y detección del antipatrón de pandas en el DWH.
   - **`qa-data-scientist`**: Auditoría metodológica contra data leakage, *p-hacking*, validación de supuestos estadísticos y reproducibilidad.
4. **Formalizar la Adopción de `dbt` como Estándar Soberano de Transformación**: Reemplazo definitivo del procesamiento procedural de datos en memoria Python dentro del warehouse por el patrón ELT declarativo y comprobable.

---

## 2. ¿Por qué se eliminó `dev-airflow-dags-py`?

El agente legacy `dev-airflow-dags-py` nació para generar DAGs sobre un andamiaje propietario (`airflow-dags-scaffold`, `StepContext`, `Queries Module`). Sin embargo, acumuló deficiencias estructurales:

1. **Monolito Funcional Ineficiente:** Pretendía asumir simultáneamente el diseño de tablas SQL, la extracción de APIs, la transformación pesada de datos y la orquestación, sin dominar a fondo ninguna de estas áreas.
2. **Promoción de Antipatrones de Memoria:** Fomentaba la extracción de tablas completas del warehouse hacia DataFrames de pandas para transformarlas en workers de Airflow y re-insertarlas, provocando cuellos de botella y fallos recurrentes de *Out Of Memory (OOM)*.
3. **Ceguera de Motor de Base de Datos:** Los scripts DDL generados carecían de guardarraíles contra bloqueos de producción (`lock_timeout`), no verificaban índices en claves foráneas y desaprovechaban la alineación física de tuplas en PostgreSQL.
4. **Ausencia Total de Capacidades IA/ML:** No ofrecía soporte para experimentación estadística, feature engineering, tracking en MLflow ni servido predictivo.

---

## 3. La Nueva Tríada Especializada de Desarrollo

En lugar de delegar todo el ciclo del dato a un solo agente generalista, cada componente del ciclo de vida es liderado por un especialista con directrices canónicas:

```
                                  CICLO DE VIDA DEL DATO
                                  
  [ Fuentes Externas / APIs / Logs ]
                 │
                 ▼ (Extracción y Normalización en Borde)
      ┌─────────────────────┐
      │    data-engineer    │ ──► Airflow TaskFlow + pandas (Fail-Fast)
      └──────────┬──────────┘
                 │
                 ▼ (Aterrizaje Físico y Almacenamiento)
      ┌─────────────────────┐
      │   data-architect    │ ──► PostgreSQL DDL Seguro (Zero-Downtime,
      └──────────┬──────────┘     Alineación de Tuplas, Cero Padding, Kimball)
                 │
                 ▼ (Transformaciones In-Warehouse)
      ┌─────────────────────┐
      │    data-engineer    │ ──► dbt Core (staging ➔ intermediate ➔ marts)
      └──────────┬──────────┘     + Astronomer Cosmos
                 │
                 ▼ (Consumo Analítico y Predictivo)
      ┌─────────────────────┐
      │   data-scientist    │ ──► Pipelines ML herméticos, Inferencia Estadística,
      └─────────────────────┘     Model Registry (@champion), Drift (PSI), FastAPI
```

### A. `data-architect` (Storage, Physical DDL & Governance)
* **Skills asociadas:** `data-architecture-postgre`, `data-quality-governance`
* **Misión:** Diseñar esquemas relacionales (OLTP) y dimensionales (OLAP/Kimball) de alto rendimiento en PostgreSQL.
* **Invariantes:**
  - **Alineación física de columnas:** Ordenamiento estricto (8B $\to$ 4B $\to$ 2B $\to$ 1B $\to$ Varlena) para eliminar el desperdicio de memoria y CPU padding.
  - **DDL seguro sin downtime:** Timeouts de bloqueo (`SET lock_timeout = '2s'`), creación de índices con `CREATE INDEX CONCURRENTLY` fuera de transacciones y claves foráneas en dos fases (`NOT VALID` $\to$ `VALIDATE CONSTRAINT`).
  - **UTC Universal:** Uso mandatorio de `TIMESTAMPTZ` y triggers de auditoría (`trg_set_updated_at`).
  - **Gobernanza:** Diccionarios de datos autogenerados (`COMMENT ON TABLE/COLUMN`) y marcas PII obligatorias.

### B. `data-engineer` (Ingestion, dbt Modeling & Airflow Orchestration)
* **Skills asociadas:** `data-engineer-airflow`, `analytics-engineer`, `data-analyst-bi`
* **Misión:** Construir pipelines idempotentes combinando extracción ligera en bordes, orquestación moderna y modelado in-warehouse.
* **Invariantes:**
  - **pandas estrictamente en los bordes:** Uso limitado a la extracción inicial, tipado nullable, normalización UTC y validación *Fail-Fast* (`DataValidationError`).
  - **dbt dueño de las transformaciones:** Cero joins o agregaciones en Python sobre datos persistidos; el warehouse computa las transformaciones mediante SQL compilado.
  - **Idempotencia determinista:** Cargas masivas vía staging temporal `UNLOGGED ... ON COMMIT DROP` fusionadas con `ON CONFLICT (...) DO UPDATE` sobre Natural Keys (`_nk`) o hash SHA-256 (`_record_hash`).
  - **Cosmos para dbt en Airflow:** Reemplazo de llamadas opacas por `DbtTaskGroup` para observabilidad a nivel de nodo.

### C. `data-scientist` (Statistical Rigor, ML Modeling & MLOps)
* **Skills asociadas:** `data-scientist`, `ml-engineer`
* **Misión:** Experimentación científica, modelado predictivo hermético y despliegue robusto de modelos en producción.
* **Invariantes:**
  - **Prevención hermética de Data Leakage:** Todo preprocesamiento encapsulado en Scikit-Learn `Pipeline` ajustado con `fit()` **únicamente** sobre la partición `train`.
  - **Particionado cronológico:** Uso obligatorio de `TimeSeriesSplit` en datos temporales y `GroupKFold` para evitar filtración de usuarios entre conjuntos.
  - **Rigor en pruebas de hipótesis:** Validación de supuestos (Shapiro-Wilk, Levene), reporte obligatorio del tamaño del efecto (Cohen's $d$, $\eta^2$) y corrección por múltiples comparaciones (FDR Benjamini-Hochberg).
  - **MLOps Integrado:** Registro en MLflow con firma estricta (`infer_signature`), tags `@champion` y `@challenger`, monitoreo de Population Stability Index (PSI) y endpoints FastAPI cargados en el evento `lifespan`.

---

## 4. Comparativa Técnica: Antes vs. Ahora

| Dimensión | Antes (`dev-airflow-dags-py`) | Ahora (`data-architect` + `data-engineer` + `data-scientist`) |
| :--- | :--- | :--- |
| **Alcance Arquitectónico** | Monolítico y acoplado a un scaffold propietario. | Modular, desacoplado y basado en estándares de la industria (Modern Data Stack). |
| **Diseño de Base de Datos** | Scripts SQL planos sin guardarraíles de concurrencia ni optimización física. | **`data-architect`**: Alineación de tuplas (eliminación de padding), DDL seguro sin bloqueos, RLS y UTC estricto. |
| **Transformación de Datos** | Procedural en Python/pandas dentro de los workers de Airflow (alto riesgo de OOM). | **`data-engineer`**: ELT moderno. pandas solo en el borde; **100% de transformación in-warehouse en dbt**. |
| **Orquestación** | Custom wrappers monolíticos (`build_<flujo>_pipeline()`). | **Airflow TaskFlow API** (`@dag`, `@task`) integrado con **Astronomer Cosmos**. |
| **Ciencia de Datos e IA** | No contemplado. | **`data-scientist` & `ml-engineer`**: EDA riguroso, pruebas de hipótesis, MLflow, PSI drift y servido FastAPI. |
| **Aseguramiento de Calidad** | Chequeos básicos de DagBag e importación. | **3 agentes de QA dedicados** con matrices de severidad y guardarraíles de producción. |

---

## 5. Matriz de Pros y Contras de Cada Agente

### A. Legacy: `dev-airflow-dags-py` (Eliminado)
* **Pros:**
  * Un solo agente centralizaba la creación de DAGs básicos de Airflow.
* **Contras:**
  * Provocaba saturación de RAM en workers de Airflow al procesar DataFrames pesados.
  * No aplicaba optimizaciones de PostgreSQL ni prevenía bloqueos de tablas en producción.
  * Ignoraba por completo las capas semánticas de métricas y el ciclo de vida de modelos de ML.

### B. `data-architect`
* **Pros:**
  * Optimiza físicamente el tamaño en disco y memoria de PostgreSQL reduciendo costos de infraestructura.
  * Garantiza migraciones seguras sin tiempo de inactividad mediante scripts Up/Down idempotentes.
  * Estandariza la gobernanza, diccionarios de datos y seguridad multi-tenant (RLS).
* **Contras:**
  * Su alcance se limita a esquemas y contratos de persistencia; no diseña la lógica procedural de los pipelines.

### C. `data-engineer`
* **Pros:**
  * Elimina los cuellos de botella de memoria al descargar el procesamiento analítico al warehouse mediante `dbt`.
  * Garantiza idempotencia matemática en backfills históricos mediante marcas de intervalo de Airflow.
  * Integra la capa analítica de negocio (Analytics Engineering, métricas formales y marts dimensionales).
* **Contras:**
  * Requiere disciplina de equipo para separar la ingesta cruda del modelado SQL, evitando scripts rápidos "ad-hoc" en Python.

### D. `data-scientist`
* **Pros:**
  * Erradica los errores metodológicos más comunes en la industria (data leakage, p-hacking, overfitting).
  * Conecta la experimentación en Jupyter/Python con la operación continua en producción (MLOps, MLflow, drift).
  * Provee endpoints predictivos seguros y de baja latencia con tipado estricto en Pydantic v2.
* **Contras:**
  * Exige un estándar de rigor superior al prototipado informal (pruebas de supuestos, semillas, firmas formales).

---

## 6. Veredicto Arquitectónico: ¿Cuál Elegir?

### **Decisión: No se elige uno solo; se adopta la Tríada en Colaboración.**

Intentar reemplazar un agente monolítico por otro agente monolítico volvería a generar acoplamiento y degradación técnica. La interacción recomendada entre los agentes es secuencial y complementaria:

1. **¿Vas a diseñar una tabla nueva, optimizar índices o planear una migración crítica en PostgreSQL?**  
   $\longrightarrow$ Invoca a **`@data-architect`**.
2. **¿Vas a extraer datos de una API/archivo, orquestar un DAG en Airflow o crear modelos analíticos/marts en SQL?**  
   $\longrightarrow$ Invoca a **`@data-engineer`**.
3. **¿Vas a realizar un análisis exploratorio, validar una hipótesis estadística, entrenar un modelo predictivo o desplegar una API de inferencia?**  
   $\longrightarrow$ Invoca a **`@data-scientist`**.

---

## 7. Detalle Exhaustivo: Red de Agentes de QA (Quality Assurance)

Los agentes de QA inspeccionan pull requests, especificaciones SDD y código propuesto antes de su pase a staging o producción, emitiendo reportes estandarizados con clasificación de riesgos.

```
                    FLUJO DE APROBACIÓN DE CALIDAD
                    
  Especificación / Código Propuesto
                 │
                 ▼
     ┌───────────────────────┐
     │     Agente de QA      │
     │  Especializado del    │
     │        Dominio        │
     └───────────┬───────────┘
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
[ PASS: Veredicto ]   [ FAIL: Hallazgos con Severidad ]
  - Aprobado            - CRÍTICA: Bloqueo de PR
  - Listo para merge    - ALTA: Corrección obligatoria
                        - Emite script/código corregido
```

### A. `qa-data-architect`
Audita la infraestructura de persistencia bajo 6 pilares:

1. **Riesgo de Bloqueo y DDL Seguro (Severidad: CRÍTICA):**
   - Verifica presencia obligatoria de:
     ```sql
     SET lock_timeout = '2s';
     SET statement_timeout = '30s';
     ```
   - Exige `CREATE INDEX CONCURRENTLY` (siempre fuera de transacciones).
   - Exige Foreign Keys en 2 fases (`NOT VALID` $\to$ `VALIDATE CONSTRAINT`).
   - Bloquea alteraciones de tipo o valores por defecto que fuercen reescrituras de tabla completas con `AccessExclusiveLock`.
2. **Indexación de Claves Foráneas (Severidad: ALTA):**
   - Comprueba que toda FK en la tabla hija tenga un índice B-Tree dedicado, previniendo escaneos secuenciales masivos al borrar en la tabla padre.
3. **Orden Físico y Eliminación de Padding (Severidad: MEDIA):**
   - Comprueba el orden decreciente por bytes (8B $\to$ 4B $\to$ 2B $\to$ 1B $\to$ Varlena) en tablas de alto volumen y calcula los bytes ahorrados por tupla.
4. **Integridad Temporal UTC (Severidad: CRÍTICA):**
   - Rechaza cualquier columna temporal definida como `TIMESTAMP WITHOUT TIME ZONE`; exige `TIMESTAMPTZ` y trigger `trg_set_updated_at`.
5. **Seguridad RLS Multi-Tenant (Severidad: ALTA):**
   - Audita `ENABLE ROW LEVEL SECURITY` y `FORCE ROW LEVEL SECURITY` en esquemas multi-inquilino.
6. **Nomenclatura y Catálogo (Severidad: BAJA a MEDIA):**
   - Exige minúsculas `snake_case`, prefijos canónicos (`dim_`, `fact_`, `pk_`, `fk_`) y comentarios obligatorios en el catálogo (`COMMENT ON TABLE/COLUMN`) con marcas `'PII: ...'`.

---

### B. `qa-data-engineer`
Audita los pipelines de orquestación y transformación bajo 5 pilares:

1. **Idempotencia y Determinismo (Severidad: CRÍTICA):**
   - Prohíbe inserciones directas `INSERT INTO ... VALUES (...)`.
   - Exige staging temporal `UNLOGGED` fusionado con `INSERT ... ON CONFLICT (...) DO UPDATE` sobre Natural Keys o hashes deterministas.
   - Prohíbe terminantemente `datetime.now()` en filtros; exige macros de intervalo de Airflow (`data_interval_start`, `data_interval_end`).
2. **Seguridad en Backfills (Severidad: ALTA):**
   - Exige `catchup=False` por defecto. Si un DAG ejecuta backfills, verifica límites de concurrencia (`max_active_runs`, `max_active_tasks`) y control de tasa hacia fuentes externas.
3. **Reintentos y Gestión de Memoria (Severidad: ALTA):**
   - Prohíbe `retries=0`. Exige reintentos exponenciales y callbacks de incidentes (`on_failure_callback`).
   - Prohíbe transferir DataFrames o cargas masivas a través de XCom (restringido a métricas y contadores escalares).
4. **Veto al Antipatrón de Extracción de DWH (Severidad: CRÍTICA):**
   - Rechaza cualquier DAG donde un DataFrame de pandas extraiga tablas del warehouse para realizar joins o agregaciones intermedias. Exige delegar la lógica a dbt.
5. **Calidad de Modelos dbt (Severidad: ALTA):**
   - Audita la presencia de tests en `schema.yml` (`unique` en claves subrogadas, `not_null`, `relationships` en FKs).
   - Valida la orquestación mediante `DbtTaskGroup` de Cosmos con reintentos a nivel de modelo individual.

---

### C. `qa-data-scientist`
Audita la metodología estadística y de Machine Learning bajo 6 pilares:

1. **Prevención Hermética de Data Leakage (Severidad: CRÍTICA):**
   - Audita que todo preprocesamiento resida en un `Pipeline` o `ColumnTransformer` de Scikit-Learn.
   - Verifica que `fit()` y `fit_transform()` se apliquen **exclusivamente** sobre el conjunto de entrenamiento (`train`).
   - Detecta y veta la fuga de variable objetivo (*Target Leakage*) por variables del futuro.
2. **Particionado Adecuado (Severidad: CRÍTICA):**
   - Rechaza `train_test_split(shuffle=True)` en datos temporales, exigiendo `TimeSeriesSplit`.
   - Audita el uso de `GroupKFold` en entidades multi-registro (usuarios, cuentas) para evitar que registros de la misma entidad coexistan en train y test.
3. **Rigor Estadístico y Prevención de P-Hacking (Severidad: ALTA):**
   - Exige comprobación de normalidad (Shapiro-Wilk) y homocedasticidad (Levene) antes de autorizar tests paramétricos (Student, ANOVA).
   - Exige corrección por múltiples comparaciones (FDR Benjamini-Hochberg o Bonferroni) al evaluar subgrupos.
   - Veta reportes que dependan únicamente de $p < 0.05$; exige reportar el tamaño del efecto (Cohen's $d$, $\eta^2$) y el intervalo de confianza al 95%.
4. **Honestidad de Métricas (Severidad: ALTA):**
   - Prohíbe el uso de Accuracy ante clases desbalanceadas (>1:5); exige PR-AUC, F1-Macro o MCC, junto a la calibración con Brier Score.
5. **Gobernanza con MLflow (Severidad: ALTA):**
   - Verifica fijación de semillas (`random_state=42`) y completitud de parámetros, métricas, artefactos de explicabilidad SHAP y firma tipada (`infer_signature`).
6. **Preparación para Servido en Producción (Severidad: MEDIA a ALTA):**
   - Verifica esquemas Pydantic v2 en FastAPI y carga única de modelos en el manejador `lifespan`.
   - Audita la línea base de drift mediante el Population Stability Index (PSI).

---

## 8. El Cambio de Paradigma: dbt Soberano en el Data Warehouse

### De ETL Procedural en Memoria a ELT Declarativo In-Warehouse

```
ENFOQUE ANTERIOR (ETL Procedural):
[Fuente] ──► [Worker Airflow / pandas] ──(Transformaciones en RAM)──► [Tabla Final DWH]
             ⚠️ Colapsos por memoria (OOM)
             ⚠️ Joins lentos fuera del motor de base de datos
             ⚠️ Pruebas manuales y lógica dispersa en scripts

ENFOQUE ACTUAL (ELT Declarativo con dbt):
[Fuente] ──► [Worker Airflow / pandas] ──(Carga Idempotente)──► [Tablas Staging / Raw]
                                                                        │
                                                (dbt compila SQL in-warehouse)
                                                                        ▼
                                                   [stg_] ➔ [int_] ➔ [fct_ / dim_]
                                                   ✅ Cero uso de RAM en Airflow
                                                   ✅ Computación distribuida en BD
                                                   ✅ Tests automáticos de unicidad/FK
```

### Arquitectura Canónica de 3 Capas en dbt

1. **Capa 1: Staging (`models/staging/<fuente>/`)**
   - **Materialización:** `view` (no duplica almacenamiento, datos siempre actualizados).
   - **Función:** Espejo 1:1 de las tablas de origen. Limpieza básica, renombrado a `snake_case`, casting de tipos (strings a `timestamptz` en UTC) y desempaquetado de atributos de objetos `JSONB`.
   - **Regla estricta:** Prohibido realizar joins con otras entidades en staging.
2. **Capa 2: Intermediate (`models/intermediate/<dominio>/`)**
   - **Materialización:** `view` o `ephemeral`.
   - **Función:** Encapsula lógica de negocio intermedia, uniones complejas multi-tabla y desnormalizaciones que no deben exponerse directamente al usuario final.
3. **Capa 3: Marts (`models/marts/<dominio>/`)**
   - **Materialización:** `table` o `incremental`.
   - **Función:** Modelado dimensional Kimball optimizado para consumo analítico:
     - **Tablas de Hechos (`fct_*`):** Eventos transaccionales y métricas acumuladas.
     - **Dimensiones (`dim_*`):** Entidades de negocio con atributos descriptivos y claves subrogadas sintéticas (`_sk`).

---

### Patrón de Código CTE Canónico en dbt

Todos los modelos dbt deben estructurarse mediante Common Table Expressions (CTEs) modulares:

```sql
-- models/staging/stg_ecommerce__customers.sql
with 

-- 1. Import CTEs (referencia directa con proyección explícita de campos)
source_customers as (
    select * from {{ source('ecommerce_raw', 'customers') }}
),

-- 2. Logical / Transformation CTEs (limpieza, casteo y normalización)
transformed as (
    select
        customer_nk,
        _record_hash,
        trim(lower(email)) as email,
        trim(upper(status)) as status,
        is_active,
        cast(registration_date as date) as registration_date,
        cast(_ingested_at as timestamptz) as _ingested_at,
        cast(updated_at as timestamptz) as updated_at
    from source_customers
),

-- 3. Final CTE
final as (
    select
        customer_nk,
        email,
        status,
        is_active,
        registration_date,
        _ingested_at,
        updated_at,
        _record_hash
    from transformed
)

-- 4. Select Final
select * from final;
```

---

### Surrogate Keys y Estrategia Incremental con Merge

En la capa de marts, generamos claves subrogadas sintéticas unívocas con `dbt_utils` y aplicamos materialización incremental eficiente para tablas de gran volumen:

```sql
-- models/marts/core/fct_orders.sql
{{ config(
    materialized='incremental',
    unique_key='order_sk',
    incremental_strategy='merge',
    on_schema_change='fail'
) }}

with orders as (
    select * from {{ ref('stg_ecommerce__orders') }}
    {% if is_incremental() %}
        -- Procesa únicamente los registros posteriores al timestamp máximo existente
        where _ingested_at >= (select coalesce(max(_ingested_at), '1970-01-01'::timestamptz) from {{ this }})
    {% endif %}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

final as (
    select
        -- Clave sustituta determinista generada por hash
        {{ dbt_utils.generate_surrogate_key(['orders.order_nk']) }} as order_sk,
        customers.customer_sk,
        orders.order_nk,
        orders.amount,
        orders.order_date,
        orders._ingested_at,
        orders.created_at
    from orders
    left join customers on orders.customer_nk = customers.customer_nk
)

select * from final;
```

---

### Contratos de Datos y Pruebas Declarativas (`schema.yml`)

La integridad de los datos se garantiza mediante contratos autoejecutables en cada modelo:

```yaml
# models/marts/core/schema.yml
version: 2

models:
  - name: fct_orders
    description: "Tabla de hechos de órdenes para análisis de ingresos y scoring de riesgo."
    columns:
      - name: order_sk
        description: "Clave sustituta primaria de la orden."
        tests:
          - unique
          - not_null
      - name: customer_sk
        description: "Clave foránea apuntando a dim_customers."
        tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_sk
      - name: amount
        description: "Importe monetario total de la orden."
        tests:
          - not_null
```

---

### Orquestación de Modelos con Astronomer Cosmos en Airflow

En lugar de ejecutar comandos opacos como `BashOperator(bash_command='dbt run')`, utilizamos **Astronomer Cosmos**:
- Cosmos parsea automáticamente el grafo de dependencias de dbt (`manifest.json`) y lo traduce a un **`DbtTaskGroup`** en Airflow.
- Cada modelo SQL se convierte en una tarea individual en la interfaz de Airflow.
- Permite reintentos individuales de modelos fallidos, observabilidad granular de tiempos de ejecución por tabla y visualización del linaje directamente en la consola web de Airflow.

---

## 9. Plantilla de Comunicación Interna para el Equipo

Puedes compartir este comunicado con el equipo técnico:

```markdown
Equipo,

Hemos implementado una actualización arquitectónica profunda en nuestro catálogo de agentes de IA (`gemini/spec-generator/.gemini/agents/`).

### 📌 Resumen de Cambios:
1. **Retiro de `dev-airflow-dags-py`:** El agente monolítico anterior ha sido deprecado debido a su alto acoplamiento, saturación de memoria en workers de Airflow y falta de soporte para optimización de bases de datos e IA.
2. **Nueva Tríada Especializada:**
   - `@data-architect`: Diseño físico de PostgreSQL (cero padding de tuplas), DDL seguro sin downtime y modelos Kimball.
   - `@data-engineer`: Ingesta ligera en el borde con Airflow TaskFlow + pandas, y 100% de transformaciones in-warehouse gobernadas por **dbt**.
   - `@data-scientist`: Inferencia estadística rigurosa, modelos predictivos herméticos (sin data leakage), ciclo MLOps en MLflow y servido FastAPI.
3. **Red de Auditores de QA Dedicados:**
   - `@qa-data-architect`: Inspección de locks, índices en FKs y esquemas multi-tenant RLS.
   - `@qa-data-engineer`: Auditoría de idempotencia en backfills y veto de DataFrames en memoria dentro del warehouse.
   - `@qa-data-scientist`: Auditoría de rigor metodológico, splits temporales y prevención de p-hacking.
4. **Soberanía de dbt en el Data Warehouse:** Toda transformación posterior a la carga pertenece exclusivamente a modelos dbt (`staging` ➔ `intermediate` ➔ `marts`), orquestados de forma transparente con Astronomer Cosmos.

El informe completo con especificaciones técnicas, comparativas y directrices de código se encuentra documentado en:
📁 `docs/DATA_AND_AI_AGENTS_MIGRATION_REPORT.md`
```
