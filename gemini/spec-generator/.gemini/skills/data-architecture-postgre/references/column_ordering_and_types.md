# Orden Físico, Alineación en Memoria y Tipos de Datos en PostgreSQL

Este documento describe la optimización de almacenamiento a bajo nivel (eliminación de padding de CPU en tuplas) y las directrices para la selección rigurosa de tipos de datos en PostgreSQL.

---

## 1. Alineación en Memoria y Padding de CPU (Tuple Layout)

En PostgreSQL, cada registro de tabla (tupla o `HeapTupleHeader`) se almacena en páginas de 8 KB. Los procesadores modernos requieren que los tipos de datos se almacenen en direcciones de memoria alineadas a múltiplos de su tamaño:

- **8 bytes**: `BIGINT`, `BIGSERIAL`, `TIMESTAMPTZ`, `TIMESTAMP`, `DOUBLE PRECISION`, `UUID` (16 bytes = 2 x 8).
- **4 bytes**: `INTEGER`, `SERIAL`, `DATE`, `REAL`.
- **2 bytes**: `SMALLINT`, `SMALLSERIAL`.
- **1 byte**: `BOOLEAN`, `"char"`.
- **Variable (varlena)**: `TEXT`, `VARCHAR`, `NUMERIC`, `JSONB`, `BYTEA`, Arrays. Tienen un header propio (1 o 4 bytes) y deben alinearse según el caso.

### 1.1 El Costo del Padding Oculto

Si las columnas se definen de forma desordenada intercalando tipos pequeños con tipos de 8 bytes, PostgreSQL inserta **bytes de relleno (padding)** invisibles entre cada columna para mantener la alineación:

```sql
-- ❌ MAL: Intercalación desordenada (Genera 24 bytes de padding por fila)
CREATE TABLE bad_orders (
    is_active    BOOLEAN,     -- 1 byte + 7 bytes PADDING
    created_at   TIMESTAMPTZ, -- 8 bytes
    status_code  SMALLINT,    -- 2 bytes + 2 bytes PADDING
    user_id      INTEGER,     -- 4 bytes
    is_deleted   BOOLEAN,     -- 1 byte + 7 bytes PADDING
    total_amount NUMERIC(12,2) -- varlena
);

-- ✅ BIEN: Ordenado de mayor a menor tamaño físico (0 bytes de padding)
CREATE TABLE good_orders (
    created_at   TIMESTAMPTZ, -- 8 bytes (alineación 8)
    user_id      INTEGER,     -- 4 bytes (alineación 4)
    status_code  SMALLINT,    -- 2 bytes (alineación 2)
    is_active    BOOLEAN,     -- 1 byte
    is_deleted   BOOLEAN,     -- 1 byte (completa par de 2 bytes)
    total_amount NUMERIC(12,2) -- varlena al final
);
```

**Impacto**: En una tabla de 50 millones de registros, eliminar el padding ahorra **1.2 GB a 3 GB de RAM en el buffer cache**, reduciendo drásticamente las lecturas a disco (I/O).

---

## 2. Regla de Orden Físico Recomendado

Para maximizar la densidad de tuplas por página de 8 KB y respetar la legibilidad humana, aplicar el siguiente orden:

```
┌────────────────────────────────────────────────────────┐
│ 1. Fixed 8-byte types: BIGINT, TIMESTAMPTZ, UUID       │
│ 2. Fixed 4-byte types: INTEGER, DATE, REAL             │
│ 3. Fixed 2-byte types: SMALLINT                        │
│ 4. Fixed 1-byte types: BOOLEAN                         │
│ 5. Variable-length types: TEXT, VARCHAR, NUMERIC, JSONB│
└────────────────────────────────────────────────────────┘
```

### 2.1 Reconciliación con la Legibilidad Lógica

La jerarquía lógica estándar de una tabla es:
1. Primary Key (`id` / `entity_id`)
2. Contexto de Tenant (`tenant_id`, `org_id`)
3. Claves de negocio / Códigos naturales (`code`, `slug`)
4. Claves foráneas (`user_id`, `account_id`)
5. Atributos descriptivos de negocio
6. Métricas y valores numéricos
7. Banderas y estados (`status`, `is_active`)
8. Cargas semi-estructuradas (`metadata`, `payload` JSONB)
9. Columnas de auditoría (`created_at`, `updated_at`, `deleted_at`)

**Estrategia de balance**:
- Si la tabla tendrá **menos de 100.000 filas**, priorizar la legibilidad lógica.
- Si la tabla superará **1.000.000 de filas**, es **OBLIGATORIO** aplicar el orden por bytes físicos descendente para optimizar almacenamiento y buffer pool.

---

## 3. Matriz de Selección de Tipos de Datos

### 3.1 Primary Keys: UUIDv7 vs BIGINT Identity
- **`BIGINT GENERATED ALWAYS AS IDENTITY`**:
  - Preferido para tablas internas, dimensiones de DWH y sistemas con alto volumen de inserción secuencial.
  - Ocupa solo 8 bytes (vs 16 de UUID), índices B-Tree más pequeños y compactos.
- **`UUIDv7` (o ULID)**:
  - Preferido para APIs públicas, arquitecturas distribuidas y prevención de enumeración.
  - Al estar ordenado por timestamp en los bits iniciales, **evita la fragmentación de páginas del B-Tree** que causaba el UUIDv4 aleatorio.
- **Antipatrón**: Nunca usar `SERIAL` ni `BIGSERIAL` en PostgreSQL moderno. Usar la sintaxis estándar SQL: `BIGINT GENERATED ALWAYS AS IDENTITY`.

### 3.2 Cadenas de Texto: TEXT vs VARCHAR vs CHAR
- **`TEXT`**: El tipo predeterminado recomendado. En PostgreSQL, `TEXT` y `VARCHAR` usan la misma estructura interna (`varlena`). No hay diferencia de rendimiento.
- **`VARCHAR(N)`**: Usar únicamente cuando exista un límite de negocio estricto (ej: código postal ISO de 10 caracteres, hash SHA-256 de 64 caracteres).
- **`CHAR(N)`**: **PROHIBIDO**. Rellena con espacios en blanco al final, desperdicia bytes y genera comportamientos inesperados en comparaciones de cadenas.

### 3.3 Valores Numéricos: NUMERIC vs DOUBLE PRECISION
- **`NUMERIC(precision, scale)`**:
  - Obligatorio para valores monetarios, precios, transacciones financieras e intereses.
  - Almacena números decimales exactos sin errores de redondeo de punto flotante.
- **`DOUBLE PRECISION` / `REAL`**:
  - Usar exclusivamente para telemetría, coordenadas GPS, mediciones científicas o machine learning donde la velocidad de CPU supere la necesidad de precisión exacta al centavo.

### 3.4 Datos Semi-estructurados: JSONB vs JSON
- **`JSONB`**: Obligatorio. Almacena en formato binario descompuesto, elimina espacios redundantes, soporta indexación GIN y operaciones de contención (`@>`, `?`, jsonpath).
- **`JSON`**: Solo aceptable como buffer de paso de logs crudos donde no se requiera ninguna consulta ni índice sobre los campos internos.

### 3.5 Banderas y Estados: BOOLEAN y ENUMs
- **`BOOLEAN`**: Usar siempre tipo nativo `BOOLEAN` (`TRUE`/`FALSE`). Prohibido usar `INTEGER` (0/1) o `CHAR(1)` ('Y'/'N').
- **Estados / Enumeraciones**:
  - Opción A (Recomendada para APIs ágiles): `TEXT` con restricción `CHECK (status IN ('PENDING', 'PAID', 'CANCELLED'))`. Permite agregar valores futuros sin bloqueos de tabla prolongados.
  - Opción B (Recomendada para dominios inmutables): `CREATE TYPE order_status AS ENUM (...)`. Ocupa 4 bytes internamente.
