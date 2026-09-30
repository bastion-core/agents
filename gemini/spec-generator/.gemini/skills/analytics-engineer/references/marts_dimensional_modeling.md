# Modelado Dimensional de Marts en dbt (Ralph Kimball)

Este documento establece las directrices arquitectónicas para diseñar e implementar la capa de consumo analítico (`models/marts/`) siguiendo la metodología de Ralph Kimball.

---

## 1. Principios de Diseño Dimensional

1. **Un Grano Claro por Modelo**: La primera regla de modelado dimensional es declarar y defender el grano (ej: una fila por línea de ítem en orden, o una fila por cliente por día).
2. **Claves Subrogadas Sintéticas (`_sk`)**:
   - Todo mart debe tener una clave primaria subrogada determinista generada mediante `dbt_utils.generate_surrogate_key`.
   - Nunca usar claves naturales (`_nk`) directamente como primary keys en marts.
3. **Separación Estricta de Hechos y Dimensiones**:
   - **Tablas de Hechos (`fct_*`)**: Almacenan eventos de negocio cuantitativos. Contienen claves foráneas hacia dimensiones conformadas y medidas aditivas/semi-aditivas.
   - **Dimensiones Conformadas (`dim_*`)**: Almacenan el contexto de las entidades de negocio. Contienen atributos descriptivos para filtrado, agrupación y segmentación.

---

## 2. Patrón Canónico de Tabla de Hechos (`fct_orders.sql`)

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
        -- Procesamiento incremental basado en timestamp de ingesta UTC
        where _ingested_at >= (select coalesce(max(_ingested_at), '1970-01-01'::timestamptz) from {{ this }})
    {% endif %}
),

customers as (
    select customer_sk, customer_nk from {{ ref('dim_customers') }}
),

stores as (
    select store_sk, store_nk from {{ ref('dim_stores') }}
),

final as (
    select
        -- Clave subrogada de la orden
        {{ dbt_utils.generate_surrogate_key(['orders.order_nk']) }} as order_sk,
        
        -- Claves foráneas dimensionales
        coalesce(customers.customer_sk, '{{ var("unknown_sk", "-1") }}') as customer_sk,
        coalesce(stores.store_sk, '{{ var("unknown_sk", "-1") }}') as store_sk,
        
        -- Degenerate Dimensions (dimensiones sin tabla separada)
        orders.order_nk,
        orders.order_number,
        orders.order_status,
        orders.payment_method,
        
        -- Marcas Temporales UTC
        orders.ordered_at,
        orders._ingested_at,
        
        -- Medidas Aditivas
        orders.subtotal_amount_cents,
        orders.discount_amount_cents,
        orders.tax_amount_cents,
        orders.net_amount_cents,
        (orders.net_amount_cents / 100.0)::numeric(12, 2) as net_amount_usd
        
    from orders
    left join customers on orders.customer_nk = customers.customer_nk
    left join stores on orders.store_nk = stores.store_nk
)

select * from final;
```

---

## 3. Patrón de Dimensión con SCD Tipo 2 (`dim_customers.sql`)

Para rastrear cambios históricos en los atributos de un cliente:
- `dbt snapshot` captura cambios y genera `dbt_valid_from` y `dbt_valid_to`.
- La dimensión conformada expone la vista actual (`is_current = true`) o la dimensión histórica completa.
