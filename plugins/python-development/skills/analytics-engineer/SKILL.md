---
name: analytics-engineer
description: Estándares de Analytics Engineering con dbt: capa semántica (Semantic Layer), definición de métricas formales, modelado dimensional de marts y gobernanza de exposures.
---

# Analytics Engineer Skill (dbt Semantic Layer, Marts, Metrics & Exposures)

Este skill define los estándares de modelado dentro del almacén de datos (Data Warehouse) utilizando **dbt** (Data Build Tool), la **Capa Semántica (Semantic Layer / MetricFlow)**, el modelado dimensional de Ralph Kimball para marts y la gobernanza de productos de datos mediante **exposures**.

---

## División de Responsabilidades (Data Engineer vs Analytics Engineer)

Cuando el modelado en dbt representa una parte sustancial de la carga de trabajo, se aplica la siguiente división clara de propiedad:

| Rol / Capacidad | Propiedad (Ownership) | Entregables Clave |
|---|---|---|
| **Data Engineer** | **Ingesta y Orquestación** | Pipelines en Airflow, extracción y normalización en bordes con pandas, cargas idempotentes en tablas staging crudas (`raw.*`), observabilidad de DAGs. |
| **Analytics Engineer** | **Modelado y Métricas** | Modelos dbt (`stg_` $\to$ `int_` $\to$ `dim_`/`fct_`), Semantic Layer (`semantic_models.yml`), definición de métricas (`metrics.yml`), `exposures.yml`, pruebas de integridad y contratos de datos. |

---

## Capacidades Principales

1. **dbt Semantic Layer & MetricFlow**:
   - Modelado de entidades (`entities`), dimensiones categóricas y temporales (`dimensions`), y medidas agregables (`measures`).
   - Definición de métricas de negocio estandarizadas: métricas simples, acumuladas (`cumulative`), derivadas (`derived`) y de conversión (`conversion`).
2. **Modelado Dimensional de Marts (Ralph Kimball)**:
   - Tablas de hechos (`fct_*`): grano unívoco, medidas numéricas aditivas/semi-aditivas, claves subrogadas (`_sk`) generadas con `dbt_utils.generate_surrogate_key`.
   - Dimensiones conformadas (`dim_*`): atributos descriptivos, manejo de cambios dimensionales lentos (SCD Type 1 y SCD Type 2).
   - Materializaciones incrementales con estrategia `merge` y guardas `is_incremental()`.
3. **Gobernanza de Exposures y Linaje de Datos**:
   - Registro de consumidores en `exposures.yml` (dashboards en Metabase/Tableau, modelos de ML, sincronizaciones de reverse ETL).
   - Documentación de dependencias para evaluar impacto de cambios (`dbt build --select +exposure:nombre`).
4. **Contratos de Modelos y Suites de Testing**:
   - Cumplimiento de contratos explícitos (`contract: {enforced: true}`).
   - Pruebas genéricas (`unique`, `not_null`, `relationships`, `accepted_values`) y singulares de lógica de negocio.

---

## Módulos de Referencia Especializados

Consultar los módulos técnicos en `references/`:

- **Semantic Layer & Métricas**: `references/semantic_layer_and_metric_definitions.md` — Sintaxis de MetricFlow, tipos de métricas y medidas.
- **Modelado de Marts Dimensionales**: `references/marts_dimensional_modeling.md` — Patrones de hechos, dimensiones conformadas e incrementales.
- **Exposures y Linaje**: `references/exposures_and_governance.md` — Especificación de exposures, gobernanza y linaje columna a columna.
- **Handoff Contract**: `references/ingestion_vs_modelling_handoff.md` — Contratos de interfaz entre Data Engineer y Analytics Engineer.

---

## Checklist de Calidad para Modelos de Analytics Engineering

Antes de considerar listo un modelo o pull request de dbt, verificar:

- [ ] Las fuentes crudas están declaradas en `sources.yml` con frescura (`freshness`) configurada.
- [ ] Los modelos respetan el linaje en capas: `stg_` $\to$ `int_` $\to$ `marts` (`fct_`, `dim_`).
- [ ] Todo mart tiene clave subrogada (`_sk`) probada con `unique` y `not_null`.
- [ ] Las claves foráneas hacia dimensiones tienen pruebas de `relationships`.
- [ ] Las medidas agregables y métricas de negocio están formalizadas en la Semantic Layer.
- [ ] Todo dashboard o modelo consumidor downstream está documentado en `exposures.yml`.
- [ ] La materialización incremental utiliza `unique_key` y maneja `is_incremental()` determinista en UTC.
