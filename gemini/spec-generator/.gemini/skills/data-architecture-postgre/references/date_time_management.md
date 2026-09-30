# Gestión de Fechas, Horas y Datos Temporales en PostgreSQL

Este documento establece el estándar de ingeniería de datos para el manejo riguroso de zonas horarias, columnas temporales, auditoría automática, rangos continuos y particionamiento por tiempo en PostgreSQL.

---

## 1. El Principio Universal UTC

1. **La Base de Datos siempre opera en UTC**:
   - Todo servidor, contenedor, réplica y sesión de aplicación debe configurar su zona horaria a UTC (`SET timezone = 'UTC'`).
   - Las conversiones a zonas horarias locales (ej: `America/Bogota`, `Europe/Madrid`) son responsabilidad de la capa de presentación o de reportes específicos (`AT TIME ZONE`).

2. **`TIMESTAMPTZ` es Obligatorio para Puntos en el Tiempo**:
   - En PostgreSQL, `TIMESTAMPTZ` (`timestamp with time zone`) almacena el instante físico universal como un entero de 8 bytes normalizado a UTC.
   - **Antipatrón Prohibido**: `TIMESTAMP WITHOUT TIME ZONE`. Almacena un valor flotante desprovisto de referencia temporal, provocando corrupción de datos durante cambios de horario de verano (DST) o al interactuar con servicios en distintas regiones.
   - **Única excepción válida para `TIMESTAMP WITHOUT TIME ZONE`**: Tareas calendarizadas recurrentes de reloj de pared (ej: "ejecutar todos los días a las 09:00 hora de la tienda local", independientemente de la zona).

---

## 2. Convenciones de Tipos Temporales y Nombres

| Tipo de Dato | Propósito | Nomenclatura | Ejemplo |
|---|---|---|---|
| `TIMESTAMPTZ` | Instante absoluto en la línea de tiempo | Sufijo `*_at` | `created_at`, `updated_at`, `paid_at`, `cancelled_at` |
| `DATE` | Fecha de calendario sin componente de hora | Sufijo `*_date` | `birth_date`, `due_date`, `fiscal_date` |
| `TIME` | Hora del día sin fecha asociada | Sufijo `*_time` | `opening_time`, `daily_sync_time` |
| `INTERVAL` | Duración o lapso transcurrido | Sufijo `*_duration` o `*_interval` | `session_duration`, `sla_interval` |
| `TSTZRANGE` | Periodo continuo con inicio y fin | Sufijo `*_period` o `*_range` | `booking_period`, `validity_range` |

---

## 3. Estándar de Columnas de Auditoría y Triggers

Toda tabla transaccional o dimensional debe incluir columnas de auditoría consistentes:

```sql
-- Estructura estándar de auditoría
created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
deleted_at TIMESTAMPTZ NULL -- Opcional: solo si el dominio requiere Soft Delete
```

### 3.1 Función y Trigger Idempotente para `updated_at`

Para garantizar que `updated_at` refleje siempre el instante exacto de la última modificación en la base de datos (incluso si una consulta manual o script olvida actualizarlo):

```sql
-- 1. Función compartida para actualizar updated_at (Crear una vez por base de datos)
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger aplicado a cada tabla
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION trg_set_updated_at();
```

---

## 4. Prevención de Solapamiento Temporal con `TSTZRANGE` y `EXCLUDE`

En casos de reservas, alquileres, agendas o vigencias, validar solapamientos en la aplicación genera condiciones de carrera (race conditions). PostgreSQL resuelve esto a nivel de motor mediante restricciones de exclusión con GiST:

```sql
-- Requiere la extensión btree_gist para mezclar UUID/BIGINT con rangos
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE vehicle_rentals (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id BIGINT NOT NULL,
    rental_period TSTZRANGE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Garantiza que un mismo vehículo NUNCA tenga dos reservas solapadas
    CONSTRAINT excl_rentals_no_overlap 
    EXCLUDE USING gist (
        vehicle_id WITH =,
        rental_period WITH &&
    )
);

-- Inserción de ejemplo usando tstzrange:
-- tstzrange('2026-10-01 10:00:00Z', '2026-10-05 18:00:00Z', '[)')
```

---

## 5. Particionamiento Declarativo por Fecha (Time-Based Partitioning)

Para tablas de eventos, logs, auditoría o series de tiempo que superen los 20-50 millones de registros, particionar por rango temporal:

```sql
-- 1. Tabla padre particionada
CREATE TABLE event_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    tenant_id BIGINT NOT NULL,
    event_name TEXT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, created_at) -- La columna de partición DEBE ser parte de la PK
) PARTITION BY RANGE (created_at);

-- 2. Particiones mensuales
CREATE TABLE event_logs_p2026_10 PARTITION OF event_logs
    FOR VALUES FROM ('2026-10-01 00:00:00Z') TO ('2026-11-01 00:00:00Z');

CREATE TABLE event_logs_p2026_11 PARTITION OF event_logs
    FOR VALUES FROM ('2026-11-01 00:00:00Z') TO ('2026-12-01 00:00:00Z');

-- 3. Ventaja crítica de retención (Zero Cost Purge):
-- En lugar de un costoso DELETE FROM event_logs WHERE created_at < ... (que causa bloat y locks),
-- se elimina o archiva la tabla de la partición de forma instantánea:
-- DROP TABLE event_logs_p2026_10;
```
