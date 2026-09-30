# Convenciones de Nomenclatura para PostgreSQL

Este documento establece el estándar estricto de nomenclatura para objetos de base de datos PostgreSQL en arquitecturas híbridas (OLTP y OLAP/DWH).

---

## 1. Reglas Generales de Identificadores

- **Case**: Usar exclusivamente `snake_case` en minúsculas.
- **Caracteres permitidos**: `[a-z0-9_]`. Nunca usar espacios, guiones ni mayúsculas.
- **Comillas dobles**: **PROHIBIDO** el uso de identificadores entre comillas dobles (`"ColumnName"`). Todos los identificadores deben ser case-insensitive válidos.
- **Longitud máxima**: 63 bytes (límite interno de PostgreSQL `NAMEDATALEN - 1`). Los nombres que excedan este límite se truncarán silenciosamente.
- **Idioma**: Inglés técnico para todos los nombres de esquemas, tablas, columnas y restricciones.
- **Palabras reservadas**: Prohibido usar palabras reservadas de SQL o PostgreSQL como identificadores directos (ej: `user`, `order`, `group`, `table`, `limit`, `type`, `status`, `select`). Usar variantes contextuales: `app_user`, `customer_order`, `user_group`, `status_type`.

---

## 2. Convenciones para Esquemas (Schemas)

Organizar los objetos en esquemas según el dominio o la capa arquitectónica:

| Esquema | Propósito | Ejemplo de Tablas |
|---|---|---|
| `app` (o nombre de dominio) | Tablas operacionales OLTP de la aplicación | `app.users`, `billing.invoices` |
| `raw` | Capa Bronze / Ingesta: datos crudos append-only | `raw.stripe_charges`, `raw.device_events` |
| `stg` | Capa Silver / Staging: datos limpios y tipados | `stg.stg_stripe_charges`, `stg.stg_devices` |
| `core` / `marts` | Capa Gold: modelos dimensionales (Kimball) | `core.dim_customers`, `core.fact_orders` |
| `audit` | Registros de auditoría y Change Data Capture | `audit.entity_change_logs` |

---

## 3. Convenciones para Tablas y Vistas

### 3.1 Tablas OLTP
- Nombrar en **plural** representando colecciones de entidades de negocio:
  - ✅ `users`, `orders`, `order_items`, `payment_transactions`, `organizations`
  - ❌ `user`, `Order`, `order-item`, `tbl_orders`
- Tablas de relación muchos a muchos (junction/bridge): concatenar las entidades en singular o un nombre compuesto de dominio:
  - ✅ `user_roles`, `product_categories`, `organization_memberships`

### 3.2 Tablas OLAP / DWH
- Usar prefijos explícitos de modelado dimensional:
  - Dimensiones: `dim_<entidad>` (ej: `dim_customers`, `dim_products`, `dim_date`).
  - Hechos / Transacciones: `fact_<evento_negocio>` (ej: `fact_orders`, `fact_page_views`).
  - Puentes: `bridge_<entidad1>_<entidad2>` (ej: `bridge_customer_groups`).
  - Agregaciones / Data Marts: `mart_<dominio>_<concepto>` (ej: `mart_finance_monthly_revenue`).

### 3.3 Vistas y Particiones
- Vistas estándar: prefijo `v_` (ej: `v_active_subscriptions`).
- Vistas materializadas: prefijo `mv_` (ej: `mv_daily_sales_summary`).
- Tablas particionadas (hijas): `<tabla_padre>_p<rango>` (ej: `events_p2026_01`, `events_p2026_02`).

---

## 4. Convenciones para Columnas (Headers)

### 4.1 Identificadores y Claves
- Clave primaria interna:
  - En tablas OLTP: `id` (cuando la entidad está implícita en la tabla) o `<entidad_singular>_id`.
  - En modelos DWH: `<entidad>_sk` (Surrogate Key sintética) y `<entidad>_nk` (Natural/Business Key de origen).
- Clave foránea (Foreign Key):
  - Formato: `<entidad_referenciada_singular>_id`.
  - Ejemplos: `user_id`, `organization_id`, `parent_category_id`.
  - Cuando hay múltiples relaciones a la misma tabla, agregar el rol como prefijo: `created_by_user_id`, `assigned_to_user_id`.

### 4.2 Columnas Booleanas
- Siempre usar prefijos afirmativos interrogativos: `is_`, `has_`, `can_`, `should_`.
- Ejemplos válidos: `is_active`, `is_verified`, `has_discount`, `can_read_billing`.
- **Antipatrón prohibido**: Negaciones directas como `is_not_active`, `disabled`, `is_inactive`.

### 4.3 Columnas Temporales (Fechas y Timestamps)
- `*_at`: Para momentos exactos en el tiempo (`TIMESTAMPTZ`): `created_at`, `updated_at`, `deleted_at`, `paid_at`, `expires_at`.
- `*_date`: Para fechas calendario sin hora (`DATE`): `birth_date`, `due_date`, `invoice_date`.
- `*_time`: Para horas del día sin fecha (`TIME`): `start_time`, `cutoff_time`.
- `*_duration` o `*_interval`: Para duraciones (`INTERVAL`): `session_duration`, `retry_interval`.

### 4.4 Unidades, Medidas y Dinero
- Declarar siempre la unidad en el nombre de la columna para evitar ambigüedades:
  - Dinero / Moneda: Guardar en centavos (enteros) o especificar divisa: `amount_cents`, `price_usd_cents`, `tax_cents`.
  - Tiempo: `timeout_seconds`, `retry_delay_ms`, `lock_duration_seconds`.
  - Peso / Distancia: `weight_kg`, `distance_meters`, `file_size_bytes`.

---

## 5. Convenciones para Restricciones e Índices

Seguir este esquema determinista para nombres de restricciones:

| Tipo de Restricción | Patrón de Nombre | Ejemplo |
|---|---|---|
| Primary Key | `pk_<table>` | `pk_users`, `pk_order_items` |
| Foreign Key | `fk_<table>_<target_table>_<col>` | `fk_orders_users_user_id` |
| Unique Constraint | `uq_<table>_<columnas>` | `uq_users_email`, `uq_org_members_org_user` |
| Check Constraint | `chk_<table>_<descripcion>` | `chk_orders_amount_positive`, `chk_users_email_valid` |
| Exclusion Constraint | `excl_<table>_<descripcion>` | `excl_room_bookings_no_overlap` |
| Índice B-Tree | `idx_<table>_<columnas>` | `idx_users_email`, `idx_orders_user_created` |
| Índice Único | `udx_<table>_<columnas>` | `udx_users_username` |
| Índice Parcial | `idx_<table>_<cols>_<condicion>` | `idx_orders_unpaid_status`, `idx_users_active_email` |
| Índice GIN | `gin_<table>_<columna>` | `gin_audit_logs_payload`, `gin_articles_tags` |
| Índice BRIN | `brin_<table>_<columna>` | `brin_events_created_at` |
