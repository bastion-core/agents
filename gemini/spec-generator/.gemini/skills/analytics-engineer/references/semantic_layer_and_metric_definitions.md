# dbt Semantic Layer & MetricFlow: Definición Estándar de Métricas

Este documento establece la arquitectura y directrices de implementación para la Capa Semántica de dbt (MetricFlow), garantizando que las métricas de negocio se definan una sola vez en código y se consuman de manera consistente en BI, APIs y ciencia de datos.

---

## 1. Arquitectura de la Capa Semántica

La Capa Semántica se compone de dos tipos fundamentales de especificaciones YAML:
1. **Semantic Models (`models/semantic/semantic_models.yml`)**: Vinculan modelos físicos de marts con entidades, dimensiones y medidas agregables.
2. **Metrics (`models/semantic/metrics.yml`)**: Expresiones matemáticas construidas sobre las medidas para responder preguntas de negocio.

---

## 2. Definición Canónica de Semantic Model

```yaml
# models/semantic/sem_orders.yml
version: 2

semantic_models:
  - name: sem_orders
    description: "Modelo semántico de órdenes de compra cerradas y liquidadas."
    model: ref('fct_orders')
    defaults:
      agg_time_dimension: ordered_at

    entities:
      - name: order_id
        type: primary
      - name: customer_id
        type: foreign
      - name: store_id
        type: foreign

    dimensions:
      - name: ordered_at
        type: time
        type_params:
          time_granularity: day
      - name: order_status
        type: categorical
      - name: payment_method
        type: categorical
      - name: is_first_order
        type: categorical

    measures:
      - name: order_total_usd
        description: "Monto total monetario neto de la orden en USD."
        agg: sum
        expr: net_amount_usd
      - name: order_count
        description: "Conteo total de órdenes generadas."
        agg: count
        expr: order_id
      - name: distinct_customers
        description: "Conteo único de clientes transaccionales."
        agg: count_distinct
        expr: customer_id
```

---

## 3. Tipología Estándar de Métricas en dbt

### 3.1 Métrica Simple
Medida directa agregada:
```yaml
# models/semantic/metrics.yml
metrics:
  - name: net_revenue_usd
    label: "Ingresos Netos (USD)"
    description: "Suma total de ingresos netos de órdenes válidas."
    type: simple
    type_params:
      measure: order_total_usd
```

### 3.2 Métrica Derivada (Ratios y Margen)
Calculada combinando dos o más métricas:
```yaml
  - name: average_order_value_aov
    label: "Ticket Promedio (AOV)"
    description: "Ingresos netos totales divididos por el conteo total de órdenes."
    type: derived
    type_params:
      expr: net_revenue_usd / order_count
      metrics:
        - name: net_revenue_usd
        - name: order_count
```

### 3.3 Métrica Acumulada (Cumulative)
Métricas acumuladas en el tiempo (ej: ingresos acumulados en los últimos 30 días):
```yaml
  - name: cumulative_revenue_30d
    label: "Ingresos Acumulados 30D"
    type: cumulative
    type_params:
      measure: order_total_usd
      window: 30 days
```

### 3.4 Métrica de Conversión (Conversion)
Mide el paso secuencial de una entidad entre dos estados:
```yaml
  - name: user_order_conversion_rate
    label: "Tasa de Conversión de Usuario a Comprador"
    type: conversion
    type_params:
      conversion_type_params:
        base_measure: user_signup_count
        conversion_measure: distinct_customers
        entity: customer_id
        window: 7 days
```
