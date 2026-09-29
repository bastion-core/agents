# Estrategias de Indexación y Rendimiento en PostgreSQL

Este documento define las reglas de diseño para índices, prevención de contención de escritura, optimización de consultas y mantenimiento del motor de almacenamiento en PostgreSQL.

---

## 1. Tipos de Índices y Cuándo Usarlos

PostgreSQL ofrece múltiples motores de indexación especializados:

| Tipo | Casos de Uso Óptimos | Operadores Soportados | Ejemplo de Creación |
|---|---|---|---|
| **B-Tree** (Default) | Búsquedas por igualdad, rangos, ordenamientos (`ORDER BY`), unicidad | `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, `IS NULL` | `CREATE INDEX idx_users_email ON users(email);` |
| **GIN** (Generalized Inverted) | `JSONB`, arreglos (`array`), búsqueda de texto completo (`tsvector`) | `@>`, `?`, `?&`, `?\|`, `@@` | `CREATE INDEX gin_audit_payload ON audit_logs USING gin(payload jsonb_path_ops);` |
| **BRIN** (Block Range) | Tablas masivas (>10M filas) append-only ordenadas naturalmente en disco por fecha o ID secuencial | Rangos sobre datos físicamente correlacionados | `CREATE INDEX brin_metrics_timestamp ON metrics USING brin(recorded_at);` |
| **GiST** | Datos espaciales (PostGIS), rangos temporales (`tstzrange`), restricciones de exclusión | `&&` (solapamiento), `@>`, `<@` | `CREATE INDEX gist_bookings ON bookings USING gist(booking_range);` |

---

## 2. Reglas Cruciales de Diseño de Índices

### 2.1 Regla de Oro para Índices Compuestos (Equality First, Range Last)
Al diseñar un índice compuesto sobre múltiples columnas, el orden es crítico:
1. **Primero**: Columnas de filtro por **igualdad estricta** (`WHERE status = 'ACTIVE' AND tenant_id = 123`).
2. **Segundo**: Columnas con operadores de **rango** (`WHERE created_at >= '2026-01-01'`) o columnas en `ORDER BY`.

```sql
-- ❌ INEFICIENTE: El rango al inicio invalida la búsqueda binaria para status
CREATE INDEX idx_bad ON orders (created_at, status, tenant_id);

-- ✅ ÓPTIMO: Igualdades primero, rango al final
CREATE INDEX idx_good ON orders (tenant_id, status, created_at DESC);
```

### 2.2 Índices Parciales (Partial Indexes)
Indexar únicamente el subconjunto de filas sobre el que se ejecutan las consultas. Esto reduce el tamaño del índice en un 80-95% y ahorra I/O:

```sql
-- Consultar solo órdenes pendientes de procesamiento
CREATE INDEX idx_orders_unprocessed 
ON orders (created_at) 
WHERE status = 'PENDING';

-- Garantizar email único ignorando registros eliminados lógicamente
CREATE UNIQUE INDEX udx_users_active_email 
ON users (email) 
WHERE deleted_at IS NULL;
```

### 2.3 Índices Cubrientes (Covering Indexes con `INCLUDE`)
Permiten a PostgreSQL ejecutar **Index-Only Scans** (leyendo solo las páginas del índice sin tocar la tabla principal):

```sql
-- La clave del árbol B-Tree es user_id, mientras que total_amount y status van en el payload
CREATE INDEX idx_orders_user_covering 
ON orders (user_id) 
INCLUDE (total_amount_cents, status);

-- Consulta cubierta al 100%:
SELECT total_amount_cents, status FROM orders WHERE user_id = 45;
```

---

## 3. Obligatoriedad de Indexar Claves Foráneas (Foreign Keys)

**HECHO**: PostgreSQL **NO** indexa automáticamente las columnas de clave foránea.
**CONSECUENCIA**: Cuando se elimina (`DELETE`) o actualiza la clave primaria de un registro padre en la tabla referenciada, PostgreSQL debe realizar un **Sequential Scan completo** con bloqueo sobre la tabla hija para validar la integridad referencial. Esto provoca bloqueos globales y lentitud extrema.

**REGLA OBLIGATORIA**: Toda clave foránea que participe en consultas de `JOIN`, `WHERE` o cuyas tablas padre reciban eliminaciones o actualizaciones frecuentes **DEBE tener un índice en la tabla hija**.

```sql
-- Tabla orders con FK a users
ALTER TABLE orders ADD CONSTRAINT fk_orders_users_user_id 
    FOREIGN KEY (user_id) REFERENCES users(id);

-- Índice obligatorio correspondiente
CREATE INDEX idx_orders_user_id ON orders(user_id);
```

---

## 4. Presupuesto de Índices y Antipatrones

Cada índice adicional acelera las lecturas pero **penaliza severamente cada `INSERT`, `UPDATE` y `DELETE`**.

- **Presupuesto por tabla OLTP**: Máximo **3 a 5 índices** (incluyendo Primary Key y Unique).
- **Tablas de alto volumen de escritura (Logs, Eventos, Ingesta)**: Máximo **1 o 2 índices** (preferir BRIN sobre B-Tree para columnas temporales).
- **Antipatrón: Índices Redundantes**:
  - Si existe `idx_orders (tenant_id, user_id, created_at)`, **NO** crear un índice independiente sobre `(tenant_id)`. La regla del prefijo izquierdo ya cubre esa búsqueda.
- **Antipatrón: Indexar baja cardinalidad**:
  - No crear índices B-Tree sobre columnas con pocos valores únicos (ej: `is_active`, `gender`, `country_code`), salvo como parte de un índice compuesto o parcial.

---

## 5. Fillfactor y Actualizaciones en Página (HOT - Heap-Only Tuples)

En tablas con alta frecuencia de `UPDATE`:
- PostgreSQL crea una nueva versión de la fila cada vez que se actualiza. Si las páginas de datos están 100% llenas (`fillfactor = 100`), la nueva tupla debe escribirse en otra página, obligando a actualizar **todos los índices** de la tabla.
- **Solución HOT**: Reducir el `fillfactor` a `80-85%`. Esto reserva un 15-20% de espacio libre en cada página de 8 KB para que los `UPDATE` se realicen dentro de la misma página sin tocar los índices.

```sql
-- Configurar fillfactor en tabla de alta rotación (ej: sesiones o balances)
CREATE TABLE account_balances (
    account_id BIGINT PRIMARY KEY,
    balance_cents BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
) WITH (fillfactor = 80);
```
