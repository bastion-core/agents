# dbt Transformation Patterns: Staging, Intermediate & Marts (In-Warehouse)

Este documento define los estándares de modelado y transformación de datos en el Data Warehouse utilizando **dbt Core**. Aplica la regla estricta: **100% de las transformaciones in-warehouse pertenecen a dbt**.

---

## 1. Capas Canónicas de Modelado

```
[ raw.<source>_<entity> ]  (Tablas aterrizadas por Airflow / pandas en el borde)
           │
           ▼
[ models/staging/ ]        (Vistas 1:1, limpieza, casteo, renombrado a snake_case)
           │
           ▼
[ models/intermediate/ ]   (Vistas o Ephemeral: uniones multi-tabla y lógica compleja)
           │
           ▼
[ models/marts/ ]          (Tablas o Incremental: modelos dimensionales Ralph Kimball)
```

### Reglas de Materialización por Capa
| Capa | Materialización | Propósito | Nomenclatura |
|---|---|---|---|
| `staging` | `view` | Espejo tipado y normalizado de `raw`. Sin joins de negocio. | `stg_<fuente>_<entidad>.sql` |
| `intermediate` | `view` o `ephemeral` | Uniones complejas, desnormalizaciones intermedias. | `int_<entidad>_<proceso>.sql` |
| `marts` | `table` o `incremental` | Tablas de hechos (`fct_*`) y dimensiones (`dim_*`). | `fct_<evento>.sql` / `dim_<entidad>.sql` |

---

## 2. Nomenclatura y Convenciones de Columnas

- **Prefijo de Hechos**: Usar obligatoriamente **`fct_`** para hechos (`fct_orders`, `fct_payments`).
- **Prefijo de Dimensiones**: Usar obligatoriamente **`dim_`** para dimensiones (`dim_customers`, `dim_products`).
- **Surrogate Keys**: Claves subrogadas sintéticas con sufijo `_sk` generadas con `dbt_utils.generate_surrogate_key` (MD5 de texto determinista).
- **Natural Keys**: Claves de negocio de los sistemas fuente con sufijo `_nk` (`customer_nk`, `order_nk`).
- **Valores Financieros / Dinero**: Usar siempre tipo **`NUMERIC`** con escala explícita (ej. `NUMERIC(18, 4)`).
- **Prohibición de Palabras Reservadas**: Prohibido usar `status` aislado; usar nombres contextuales (`order_status`, `customer_status`).
- **Timestamps**: Siempre convertidos a `TIMESTAMPTZ` en UTC con sufijos `_at` (`ordered_at`, `_ingested_at`).

---

## 3. Estructura Canónica de Modelos SQL (Patrón CTE Modular)

Todo modelo dbt debe estructurarse usando CTEs (Common Table Expressions) con el siguiente formato estricto (**sin punto y coma final en la sentencia select final**):

```sql
-- models/staging/stg_ecommerce_customers.sql
with 

-- 1. Import CTEs (solo refs o sources directos con proyección explícita de campos)
source_customers as (
    select
        customer_nk,
        email,
        customer_status,
        is_active,
        registration_date,
        _ingested_at,
        updated_at,
        _record_hash
    from {{ source('ecommerce_raw', 'customers') }}
),

-- 2. Logical / Transformation CTEs (renombrado, casting, normalización)
transformed as (
    select
        -- Claves
        customer_nk,
        _record_hash,

        -- Atributos
        trim(lower(email)) as email,
        trim(upper(customer_status)) as customer_status,
        is_active,

        -- Timestamps normalizados en UTC
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
        customer_status,
        is_active,
        registration_date,
        _ingested_at,
        updated_at,
        _record_hash
    from transformed
)

-- 4. Select Final (sin punto y coma final)
select * from final
```

---

## 4. Estrategia Incremental y Surrogate Keys

### Modelo Incremental Canónico (Marts)
Para tablas de hechos de alto volumen, se utiliza materialización incremental con estrategia `merge`:

```sql
-- models/marts/core/fct_orders.sql
{{ config(
    materialized='incremental',
    unique_key='order_sk',
    incremental_strategy='merge',
    on_schema_change='fail'
) }}

with orders as (
    select
        order_nk,
        customer_nk,
        order_status,
        total_amount,
        order_date,
        _ingested_at,
        created_at
    from {{ ref('stg_ecommerce_orders') }}
    {% if is_incremental() %}
        -- Solo procesar registros más recientes que el valor máximo actual
        where _ingested_at >= (select coalesce(max(_ingested_at), '1970-01-01'::timestamptz) from {{ this }})
    {% endif %}
),

customers as (
    select
        customer_sk,
        customer_nk
    from {{ ref('dim_customers') }}
),

final as (
    select
        -- Generación determinista de Surrogate Key usando dbt_utils
        {{ dbt_utils.generate_surrogate_key(['orders.order_nk']) }} as order_sk,
        customers.customer_sk,
        orders.order_nk,
        orders.order_status,
        orders.total_amount,
        orders.order_date,
        orders._ingested_at,
        orders.created_at
    from orders
    left join customers on orders.customer_nk = customers.customer_nk
)

-- Select final (sin punto y coma)
select * from final
```

---

## 5. Declaración de Fuentes, Tests y Documentación (`schema.yml`)

Cada carpeta de modelos debe contener su archivo de especificación YAML declarando contratos, pruebas genéricas y documentación:

```yaml
# models/staging/ecommerce/schema.yml
version: 2

sources:
  - name: ecommerce_raw
    schema: raw
    tables:
      - name: customers
        description: "Tabla de clientes crudos cargados por el pipeline de extracción Airflow."
        loaded_at_field: _ingested_at
        freshness:
          warn_after: {count: 24, period: hour}
          error_after: {count: 48, period: hour}

models:
  - name: stg_ecommerce_customers
    description: "Clientes curados en staging con tipado consistente y normalización."
    columns:
      - name: customer_nk
        description: "Natural Key única de origen del cliente."
        tests:
          - unique
          - not_null
      - name: email
        description: "Correo electrónico sanitizado y en minúsculas."
        tests:
          - not_null
      - name: customer_status
        description: "Estado operativo del cliente."
        tests:
          - accepted_values:
              values: ['ACTIVE', 'INACTIVE', 'SUSPENDED']
      - name: _ingested_at
        description: "Timestamp UTC de auditoría de ingesta."
        tests:
          - not_null
```

---

## 6. Tests Singulares de Reglas de Negocio

Para validaciones que involucran múltiples columnas o lógica relacional compleja, se crean archivos `.sql` en el directorio `tests/` del proyecto dbt:

```sql
-- tests/assert_total_order_amount_is_positive.sql
-- Falla si existe alguna orden completada con importe negativo o nulo
select
    order_sk,
    total_amount
from {{ ref('fct_orders') }}
where order_status = 'COMPLETED' and (total_amount <= 0 or total_amount is null)
```
