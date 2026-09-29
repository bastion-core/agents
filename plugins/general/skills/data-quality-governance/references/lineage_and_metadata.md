# Linaje de Datos (Data Lineage), Trazabilidad y Análisis de Impacto

Este documento establece las prácticas para registrar el linaje de datos a nivel de tabla y columna, permitiendo auditar el flujo de información y realizar análisis de impacto preventivo antes de cambios DDL.

---

## 1. Niveles de Linaje

1. **Linaje a Nivel de Tabla (Coarse-Grained)**: Identifica el flujo general entre capas (ej: `raw.orders` $\to$ `stg.stg_orders` $\to$ `marts.fct_orders`).
2. **Linaje a Nivel de Columna (Fine-Grained / Column-Level)**: Rastrea transformaciones matemáticas o derivaciones exactas (ej: `raw.orders.amount` y `raw.orders.currency` originan `marts.fct_orders.net_amount_usd`).

---

## 2. Especificación de Linaje con OpenLineage

OpenLineage es el estándar abierto para la recolección de metadatos de linaje en tiempo de ejecución:

```json
{
  "eventType": "COMPLETE",
  "eventTime": "2026-09-26T12:00:00Z",
  "producer": "https://github.com/company/data-platform",
  "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json",
  "job": {
    "namespace": "dwh_pipeline",
    "name": "marts.fct_orders_build"
  },
  "inputs": [
    {
      "namespace": "postgres://dwh-prod",
      "name": "stg.stg_orders"
    },
    {
      "namespace": "postgres://dwh-prod",
      "name": "dim.dim_customers"
    }
  ],
  "outputs": [
    {
      "namespace": "postgres://dwh-prod",
      "name": "marts.fct_orders",
      "facets": {
        "columnLineage": {
          "fields": {
            "order_sk": {
              "inputFields": [
                { "namespace": "postgres://dwh-prod", "name": "stg.stg_orders", "field": "order_nk" }
              ],
              "transformationDescription": "dbt_utils.generate_surrogate_key"
            }
          }
        }
      }
    }
  ]
}
```

---

## 3. Protocolo de Análisis de Impacto Pre-Migración

Antes de autorizar un `ALTER TABLE` o `DROP COLUMN`:
1. **Inspección de Linaje**: Consultar el grafo de dependencias downstream para identificar:
   - Vistas dependientes en la base de datos (`information_schema.view_table_usage`).
   - Modelos dbt aguas abajo (`dbt ls --select <model>+`).
   - Exposures y dashboards conectados (`exposures.yml`).
2. **Ventana de Pre-Aviso**: Notificar a los owners downstream documentados con al menos 15 días de anticipación ante breaking changes.
