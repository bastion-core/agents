# Migraciones Seguras y DDL sin Downtime en PostgreSQL

Este documento contiene los protocolos de seguridad obligatorios para ejecutar cambios de esquema (DDL) en bases de datos PostgreSQL de producción sin provocar caídas de servicio, bloqueos en cola (lock queues) ni degradación del rendimiento.

---

## 1. La Anatomía del Bloqueo en PostgreSQL

La mayoría de sentencias `ALTER TABLE` adquieren un bloqueo de tipo `AccessExclusiveLock`. Este es el nivel de bloqueo más restrictivo del motor:
- Bloquea cualquier `SELECT`, `INSERT`, `UPDATE` o `DELETE` concurrente.
- Si una consulta larga (ej: un reporte o `SELECT` de 5 segundos) está en ejecución, el `ALTER TABLE` debe esperar a que termine.
- **La Catástrofe de la Cola de Bloqueos (Lock Queue Starvation)**: Mientras el `ALTER TABLE` espera, todas las nuevas consultas que lleguen detrás de él quedarán bloqueadas en cola. En segundos, el pool de conexiones de la aplicación se satura y el sistema colapsa por completo.

---

## 2. Los Dos Guardarraíles Obligatorios

Antes de ejecutar cualquier script DDL en producción, es **OBLIGATORIO** configurar timeouts cortos de sesión:

```sql
-- 1. Si no puede adquirir el bloqueo en 2 segundos, aborta la transacción inmediatamente
SET lock_timeout = '2s';

-- 2. Si la sentencia tarda más de 30 segundos en ejecutarse, aborta
SET statement_timeout = '30s';
```

Si el script falla por timeout, se reintenta automáticamente mediante un backoff exponencial sin interrumpir el tráfico en vivo de la aplicación.

---

## 3. Patrones de Operaciones DDL Seguras

### 3.1 Creación y Eliminación de Índices (`CONCURRENTLY`)
- **Regla**: Prohibido usar `CREATE INDEX` o `DROP INDEX` estándar en tablas con tráfico.
- **Solución**: Usar `CONCURRENTLY`. Requiere ejecutarse **fuera de bloques de transacción** (`autocommit = on`).

```sql
-- ✅ SEGURO: No bloquea lecturas ni escrituras
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_id 
ON orders (customer_id);

-- ✅ SEGURO: Eliminación sin bloqueo exclusivo
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_legacy_status;
```

*Nota: Si un `CREATE INDEX CONCURRENTLY` falla a mitad de camino, deja un índice inválido. Se debe verificar con `\d` o consultar `pg_class` y ejecutar `DROP INDEX CONCURRENTLY` antes de reintentar.*

---

### 3.2 Agregar Columnas `NOT NULL` con Valor por Defecto
- **En PostgreSQL 11+**: `ALTER TABLE t ADD COLUMN c TYPE NOT NULL DEFAULT 'val'` es **completamente seguro e instantáneo** (actualiza únicamente los metadatos del catálogo del sistema sin reescribir la tabla física).
- **Excepción peligrosa**: Si el valor por defecto es una función no inmutable/volátil (ej: `clock_timestamp()` o `uuid_generate_v4()`), PostgreSQL reescribirá toda la tabla bloqueándola.
- **Patrón para funciones volátiles o versiones antiguas**:

```sql
-- Paso 1: Agregar columna como NULLABLE (Instantáneo)
ALTER TABLE users ADD COLUMN api_token UUID;

-- Paso 2: Backfill progresivo en lotes (Batching) desde la aplicación o script
-- UPDATE users SET api_token = gen_random_uuid() WHERE api_token IS NULL LIMIT 5000;

-- Paso 3: Agregar constraint NOT NULL como NOT VALID (Instantáneo)
ALTER TABLE users ADD CONSTRAINT chk_users_api_token_not_null 
    CHECK (api_token IS NOT NULL) NOT VALID;

-- Paso 4: Validar constraint sin bloquear escrituras
ALTER TABLE users VALIDATE CONSTRAINT chk_users_api_token_not_null;
```

---

### 3.3 Creación Segura de Claves Foráneas (Foreign Keys)
Crear una Foreign Key estándar escanea toda la tabla para comprobar la integridad referencial, manteniendo un bloqueo compartido que impide escrituras.

**El Patrón de 2 Pasos Seguros**:

```sql
-- Paso 1: Crear la FK como NOT VALID (Bloqueo fugaz de milisegundos, no valida registros existentes)
ALTER TABLE order_items 
ADD CONSTRAINT fk_order_items_orders_order_id 
    FOREIGN KEY (order_id) REFERENCES orders(id) 
    NOT VALID;

-- Paso 2: Validar la FK concurrentemente (Escanea la tabla con ShareUpdateExclusiveLock, permitiendo lecturas y escrituras)
ALTER TABLE order_items 
VALIDATE CONSTRAINT fk_order_items_orders_order_id;
```

---

### 3.4 Renombrar o Eliminar Columnas (Patrón Expand-Contract)
**PROHIBIDO** ejecutar `ALTER TABLE t RENAME COLUMN` o `ALTER TABLE t DROP COLUMN` directamente en producción si la aplicación está activa.

**Fases del Patrón Expand-Contract**:
1. **Expand**: Agregar la nueva columna manteniendo la antigua.
2. **Dual-write**: La aplicación escribe concurrentemente en ambas columnas (la antigua y la nueva).
3. **Backfill**: Script en segundo plano copia los datos históricos de la columna vieja a la nueva.
4. **Read Switch**: La aplicación pasa a leer exclusivamente de la nueva columna.
5. **Contract**: Se apaga la escritura en la columna vieja.
6. **Drop**: Una vez validado durante varios días, se elimina la columna vieja de forma segura.

---

## 4. Plantilla de Migración de Producción (Up / Down)

Toda migración debe estructurarse con script de aplicación idempotente y script de rollback verificado:

```sql
-- ============================================================================
-- MIGRATION UP (Safe DDL)
-- ============================================================================
SET lock_timeout = '2s';
SET statement_timeout = '30s';

-- 1. Crear tabla si no existe
CREATE TABLE IF NOT EXISTS billing_invoices (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id BIGINT NOT NULL,
    invoice_number TEXT NOT NULL,
    amount_cents BIGINT NOT NULL,
    is_settled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. FK con NOT VALID
ALTER TABLE billing_invoices 
ADD CONSTRAINT fk_invoices_org 
    FOREIGN KEY (organization_id) REFERENCES organizations(id) 
    NOT VALID;

-- 3. Validar FK
ALTER TABLE billing_invoices VALIDATE CONSTRAINT fk_invoices_org;

-- ============================================================================
-- MIGRATION DOWN (Rollback)
-- ============================================================================
-- SET lock_timeout = '2s';
-- ALTER TABLE IF EXISTS billing_invoices DROP CONSTRAINT IF EXISTS fk_invoices_org;
-- DROP TABLE IF EXISTS billing_invoices;
```
