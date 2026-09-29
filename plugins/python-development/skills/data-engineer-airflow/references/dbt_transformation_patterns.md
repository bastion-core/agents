# dbt Transformation Patterns: Staging, Intermediate & Marts (In-Warehouse)

Este documento define los estándares de modelado y transformación de datos en el Data Warehouse (PostgreSQL, Snowflake, BigQuery, Redshift) utilizando **dbt**.

---

## 1. Principio Fundamental: dbt es Soberano In-Warehouse

- **Toda transformación posterior al aterrizaje de los datos en el warehouse pertenece a dbt**.
- Ningún script de Python/pandas debe realizar joins, agregaciones, cálculo de KPIs, modelado dimensional ni deduplicación histórica una vez que los datos crudos o de staging fueron persistidos en la base de datos.
- Las transformaciones en dbt aprovechan el poder de procesamiento del motor SQL de base de datos de manera declarativa, versionada, modular y comprobable.

---

## 2. Arquitectura de Capas de Modelado (Staging → Intermediate → Marts)

```
[Fuentes Raw / Staging Externas]
               │
               ▼  (models/staging/)
        ┌──────────────┐
        │  stg_*.sql   │  (Materialización: VIEW)
        └──────┬───────┘
               │
               ▼  (models/intermediate/)
        ┌──────────────┐
        │  int_*.sql   │  (Materialización: VIEW o EPHEMERAL)
        └──────┬───────┘
               │
               ▼  (models/marts/)
        ┌──────────────┬──────────────┐
        │  fct_*.sql   │  dim_*.sql   │  (Materialización: TABLE o INCREMENTAL)
        └──────────────┴──────────────┘
```

### Capa 1: Staging (`models/staging/<source_name>/`)
- **Propósito**: Limpieza inicial, renombrado de columnas a `snake_case`, casting explícito de tipos y extracción de atributos de payloads semi-estructurados (`JSONB`).
- **Relación**: Espejo 1 a 1 contra las tablas o fuentes declaradas en `sources.yml`.
- **Materialización**: Obligatoriamente `view` (para no duplicar almacenamiento y garantizar datos frescos).
- **Reglas**:
  - No realizar joins entre diferentes fuentes en esta capa.
  - Proyectar explícitamente cada columna (prohibido `SELECT *`).
  - Estandarizar nombres de timestamps con sufijo `_at` y fechas con sufijo `_date`.

### Capa 2: Intermediate (`models/intermediate/<domain>/`)
- **Propósito**: Encapsular lógica de negocio compleja, joins multi-tabla y desnormalizaciones intermedias antes de construir las métricas finales.
- **Materialización**: `view` o `ephemeral`.
- **Reglas**:
  - No exponer directamente a usuarios finales o herramientas de BI.
  - Nombrado: `int_<dominio>__<verbo_o_accion>.sql` (ej: `int_payments__grouped_by_customer.sql`).

### Capa 3: Marts (`models/marts/<domain>/`)
- **Propósito**: Modelos dimensionales estilo Kimball listos para consumo analítico, reportes y dashboards.
- **Componentes**:
  - **Hechos (`fct_<entidad/evento>.sql`)**: Eventos inmutables, transacciones y métricas acumulativas.
  - **Dimensiones (`dim_<entidad>.sql`)**: Entidades con atributos descriptivos enriquecidos y claves sustitutas (`_sk`).
- **Materialización**: `table` o `incremental`.

---

## 3. Estructura Canónica de Modelos SQL (Patrón CTE Modular)

Todo modelo dbt debe estructurarse usando CTEs (Common Table Expressions) con el siguiente formato estricto:

```sql
-- models/staging/stg_ecommerce__customers.sql
with 

-- 1. Import CTEs (solo refs o sources directos con proyección explícita)
source_customers as (
    select * from {{ source('ecommerce_raw', 'customers') }}
),

-- 2. Logical / Transformation CTEs (renombrado, casting, normalización)
transformed as (
    select
        -- Claves
        customer_nk,
        _record_hash,

        -- Atributos
        trim(lower(email)) as email,
        trim(upper(status)) as status,
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
    select * from {{ ref('stg_ecommerce__orders') }}
    {% if is_incremental() %}
        -- Solo procesar registros más recientes que el valor máximo actual
        where _ingested_at >= (select coalesce(max(_ingested_at), '1970-01-01'::timestamptz) from {{ this }})
    {% endif %}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

final as (
    select
        -- Generación determinista de Surrogate Key usando dbt_utils
        {{ dbt_utils.generate_surrogate_key(['orders.order_nk']) }} as order_sk,
        customers.customer_sk,
        orders.order_nk,
        orders.status,
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
  - name: stg_ecommerce__customers
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
      - name: status
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
    amount
from {{ ref('fct_orders') }}
where status = 'COMPLETED' and (amount <= 0 or amount is null);
```
