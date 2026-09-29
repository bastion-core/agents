# Modelado de Datos Híbrido, Gobernanza y Seguridad en PostgreSQL

Este documento establece los patrones de arquitectura de datos tanto para sistemas transaccionales (OLTP) como analíticos (OLAP / DWH), junto con estándares de metadatos, seguridad a nivel de fila (RLS) y clasificación de datos personales (PII).

---

## 1. Arquitectura Híbrida: OLTP vs OLAP/DWH

PostgreSQL es capaz de operar eficientemente como motor transaccional de alto rendimiento y como data warehouse ligero / data mart si se diseñan los esquemas con patrones diferenciados:

```
┌─────────────────────────────────┐      ETL / CDC      ┌───────────────────────────────────┐
│           OLTP (app)            │ ──────────────────> │        OLAP (raw -> stg -> core)  │
│ 3NF Normalizado                 │                     │ Medallion + Modelado Kimball      │
│ Integridad referencial estricta │                     │ Esquema Estrella (Star Schema)    │
│ UUIDv7 / Identity BIGINT        │                     │ Surrogate Keys (_sk) + SCD Type 2 │
└─────────────────────────────────┘                     └───────────────────────────────────┘
```

---

## 2. Patrones para la Capa OLTP (Transaccional)

1. **Normalización (3NF)**: Eliminar redundancias para evitar anomalías en escrituras y transacciones concurrentes.
2. **Control de Concurrencia Optimista**:
   - En tablas susceptibles a actualizaciones concurrentes (ej: inventarios, balances, configuraciones), incluir columna de versión:
   ```sql
   version INTEGER NOT NULL DEFAULT 1
   ```
   - Las consultas de actualización en la aplicación validan y aumentan la versión:
   ```sql
   UPDATE products SET stock = stock - 1, version = version + 1 
   WHERE id = 10 AND version = 1;
   ```
3. **Restricciones de Integridad en el Motor**:
   - Nunca delegar la integridad de datos exclusivamente a la aplicación. Las reglas de negocio inmutables deben residir en restricciones `CHECK`, `NOT NULL`, `FOREIGN KEY` y `UNIQUE`.

---

## 3. Patrones para la Capa OLAP / Data Warehouse (Kimball)

En los esquemas `core` y `marts`, transformar los datos en modelos dimensionales:

### 3.1 Tablas de Dimensión (`dim_*`)
- **Surrogate Key (`_sk`)**: Clave sintética `BIGINT GENERATED ALWAYS AS IDENTITY` propia del DWH.
- **Natural Key (`_nk`)**: Clave de negocio proveniente del sistema fuente original.
- **Slowly Changing Dimensions (SCD Tipo 2)** para rastreo histórico de cambios:

```sql
CREATE TABLE core.dim_customers (
    customer_sk BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_nk TEXT NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    country_code TEXT NOT NULL,
    
    -- Control histórico SCD Tipo 2
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ NOT NULL DEFAULT '9999-12-31 23:59:59Z',
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_customers_lookup 
ON core.dim_customers(customer_nk, is_current);
```

### 3.2 Tablas de Hechos (`fact_*`)
- Unir exclusivamente contra las claves subrogadas (`_sk`) de las dimensiones.
- Granularidad atómica claramente documentada.
- Particionar por fecha de ocurrencia del hecho (`fact_date`).

```sql
CREATE TABLE core.fact_sales (
    sale_id BIGINT GENERATED ALWAYS AS IDENTITY,
    date_sk INTEGER NOT NULL,          -- FK a dim_date (formato YYYYMMDD)
    customer_sk BIGINT NOT NULL,      -- FK a dim_customers
    product_sk BIGINT NOT NULL,       -- FK a dim_products
    quantity INTEGER NOT NULL,
    gross_amount_cents BIGINT NOT NULL,
    discount_cents BIGINT NOT NULL,
    net_amount_cents BIGINT NOT NULL,
    sale_timestamp TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (sale_id, sale_timestamp)
) PARTITION BY RANGE (sale_timestamp);
```

---

## 4. Gobernanza y Autodocumentación (`COMMENT ON`)

Toda tabla y columna en producción debe estar completamente documentada en el catálogo interno de PostgreSQL (`pg_description`). Esto permite que herramientas como dbt, Superset, Metabase, DataHub y catálogos de datos infieran el diccionario automáticamente:

```sql
-- Documentación de Tabla
COMMENT ON TABLE app.orders IS 
'Órdenes transaccionales de compra generadas por clientes en la plataforma web y móvil.';

-- Documentación de Columnas
COMMENT ON COLUMN app.orders.id IS 'Identificador único global de la orden (PK).';
COMMENT ON COLUMN app.orders.status IS 'Estado del ciclo de vida de la orden: PENDING, PAID, SHIPPED, CANCELLED.';
COMMENT ON COLUMN app.orders.amount_cents IS 'Monto total facturado expresado en centavos en la moneda local.';
```

### 4.1 Clasificación y Etiquetado de PII (GDPR / Privacidad)
Para facilitar auditorías de cumplimiento normativo, etiquetar explícitamente los campos sensibles en los comentarios:

```sql
COMMENT ON COLUMN app.users.email IS 'PII: Correo electrónico del usuario (Regulado GDPR/Habeas Data).';
COMMENT ON COLUMN app.users.phone_number IS 'PII: Teléfono celular de contacto.';
COMMENT ON COLUMN app.users.tax_id IS 'PII-CONFIDENTIAL: Documento de identificación tributaria.';
```

---

## 5. Seguridad: Row-Level Security (RLS) y Privilegios Mínimos

### 5.1 Aislamiento Multi-Tenant con RLS
Garantiza que ningún cliente pueda consultar ni modificar datos de otro tenant, independientemente de errores en las cláusulas `WHERE` de la aplicación:

```sql
-- 1. Habilitar RLS en la tabla
ALTER TABLE app.documents ENABLE ROW LEVEL SECURITY;

-- 2. Crear política vinculada al tenant actual de la sesión
CREATE POLICY tenant_isolation_policy ON app.documents
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id', true)::BIGINT)
    WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::BIGINT);
```

### 5.2 Principio de Mínimo Privilegio (Separación de Roles)
- **Rol DDL (Migrador / CI/CD)**: Dueño de las tablas, puede ejecutar `CREATE`, `ALTER`, `DROP`.
- **Rol Runtime (Aplicación)**: Solo privilegios DML (`SELECT`, `INSERT`, `UPDATE`, `DELETE`). Nunca conceder privilegios de superusuario ni permisos de DDL al usuario de la API.

```sql
-- Conceder solo permisos de datos a la aplicación
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM app_user;
GRANT USAGE ON SCHEMA app TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
```
