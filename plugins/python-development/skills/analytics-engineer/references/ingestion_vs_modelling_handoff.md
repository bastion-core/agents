# Contrato de Interfaz y Handoff: Data Engineer vs Analytics Engineer

Este documento delimita formalmente la frontera de responsabilidades, contratos de datos y puntos de acoplamiento entre el **Data Engineer** y el **Analytics Engineer**.

---

## 1. Matriz de Propiedad de Ciclo de Vida de Datos

```text
[ Fuentes Externas ]
         │ (APIs, CSV, DBs transaccionales)
         ▼
[ Ingesta en los Bordes ]  ────►  PROPIEDAD: Data Engineer (Airflow + pandas)
         │
         ▼
[ Tablas Raw / Staging ]   ────►  CONTRATO DE HANDOFF (Esquema físico, UTC, _ingested_at)
         │
         ▼
[ Modelado In-Warehouse ]  ────►  PROPIEDAD: Analytics Engineer (dbt: stg_ → int_ → marts)
         │
         ▼
[ Capa Semántica y BI ]    ────►  PROPIEDAD: Analytics Engineer (MetricFlow, KPIs, Exposures)
```

---

## 2. El Contrato de Handoff (Raw Data Contract)

El Data Engineer entrega los datos en el esquema `raw.*` bajo las siguientes garantías obligatorias:
1. **Presencia de Columnas de Metadatos**:
   - `_ingested_at` (`TIMESTAMPTZ` en UTC): Marca exacta de la carga en base de datos.
   - `_dag_id` (`TEXT`): Identificador del DAG de Airflow ejecutor.
   - `_run_id` (`TEXT`): ID de ejecución específico de la corrida.
   - `_record_hash` (`TEXT`): Hash SHA-256 de los atributos crudos para deduplicación.
2. **Idempotencia de Carga**: El Data Engineer garantiza que no hay filas duplicadas con idéntico `_record_hash` en el mismo `_ingested_at`.
3. **Inmutabilidad de Datos Crudos**: La capa `raw.*` no aplica reglas de negocio complejas ni modifica la semántica de origen; entrega tipos de datos limpios y caracteres escapados.

---

## 3. La Responsabilidad del Analytics Engineer

Una vez que los datos residen en `raw.*`, el Analytics Engineer:
1. Construye vistas de `staging` (`stg_*`) aplicando nombres en minúsculas `snake_case` y casteos de tipo consistentes.
2. Construye modelos intermedios (`int_*`) para resolver relaciones muchos a muchos o desnormalizaciones preliminares.
3. Construye los marts dimensionales de Ralph Kimball (`dim_*`, `fct_*`) y genera claves subrogadas (`_sk`).
4. Formaliza la **Capa Semántica** y los **Exposures** para habilitar el consumo autónomo de analistas de negocio, dashboards y modelos de machine learning.
