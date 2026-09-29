---
name: data-architecture-postgre
description: Estándares de arquitectura de datos en PostgreSQL para diseño de tablas, orden y alineación física de columnas, tipos óptimos, índices, manejo temporal UTC y migraciones DDL sin downtime.
---

# PostgreSQL Data Architecture Skill

Este skill proporciona el conocimiento experto y los estándares no-negociables para diseñar, crear, auditar y evolucionar modelos de datos y tablas en PostgreSQL bajo arquitecturas híbridas (OLTP y OLAP/DWH).

## Recursos de Referencia Especializados

Para aplicar directrices detalladas según el aspecto del diseño, consultar los módulos en `references/`:

- **Nomenclatura**: `references/naming_conventions.md` — Estándares estrictos de `snake_case`, prefijos de esquema (`raw`/`stg`/`core`/`app`), sufijos de restricciones (`pk_`, `fk_`, `uq_`, `chk_`) e índices.
- **Alineación y Tipos**: `references/column_ordering_and_types.md` — Optimización de tuplas y CPU padding (8-byte, 4-byte, 2-byte, 1-byte, varlena), selección entre UUIDv7 vs Identity BIGINT, `TEXT` vs `VARCHAR`, `NUMERIC` vs floats.
- **Índices y Rendimiento**: `references/indexing_and_performance.md` — B-Tree, GIN para JSONB, BRIN para tablas masivas temporales, índices parciales, índices cubrientes (`INCLUDE`), regla de orden (igualdad primero, rango después), obligatoriedad de indexar FKs y `fillfactor` para HOT updates.
- **Gestión Temporal**: `references/date_time_management.md` — Filosofía universal UTC, uso obligatorio de `TIMESTAMPTZ`, triggers automáticos para `updated_at`, exclusión temporal de solapamientos con `tstzrange` y particionamiento declarativo.
- **Migraciones Seguras**: `references/safe_ddl_and_migrations.md` — Protocolo Zero-Downtime, guardarraíles de `lock_timeout`, creación concurrente de índices, FKs en 2 fases (`NOT VALID` + `VALIDATE`), patrón expand-contract y scripts de rollback.
- **Modelado y Gobernanza**: `references/data_modeling_and_governance.md` — Modelado 3NF vs Kimball Dimensional (SCD Tipo 2, Fact/Dim), autodocumentación con `COMMENT ON`, etiquetado de PII y aislamiento multi-tenant con Row-Level Security (RLS).

---

## Workflow del Arquitecto de Datos (5 Fases)

Cada vez que se solicite diseñar o modificar una tabla o esquema, seguir este proceso:

```
1. Descubrimiento de Carga -> 2. Diseño Estructural -> 3. Indexación -> 4. Script DDL Seguro -> 5. Documentación
```

### Fase 1: Descubrimiento de Carga y Capa Arquitectónica
1. Identificar la capa de destino:
   - **OLTP / Transaccional (`app`)**: Priorizar normalización 3NF, integridad referencial y baja latencia de escritura.
   - **OLAP / Data Warehouse (`core` / `marts`)**: Priorizar modelos dimensionales Kimball (`dim_*`, `fact_*`), claves subrogadas sintéticas (`_sk`) e inmutabilidad.
   - **Ingesta / Staging (`raw` / `stg`)**: Carga append-only, particionamiento temporal y limpieza.
2. Estimar volumen esperado: si la tabla superará 1M de filas, la optimización de alineación física de columnas es obligatoria.

### Fase 2: Diseño Estructural y Selección de Tipos
1. **Primary Key**:
   - APIs públicas / microservicios: `UUIDv7` (o ULID) para prevenir enumeración sin fragmentar índices B-Tree.
   - Tablas internas / DWH: `BIGINT GENERATED ALWAYS AS IDENTITY` para máxima densidad y velocidad.
2. **Orden Físico de Columnas**:
   - Organizar las columnas de mayor a menor tamaño en memoria para eliminar bytes de padding de CPU:
     1. Fijos de 8 bytes (`BIGINT`, `TIMESTAMPTZ`, `UUID`).
     2. Fijos de 4 bytes (`INTEGER`, `DATE`).
     3. Fijos de 2 bytes (`SMALLINT`).
     4. Fijos de 1 byte (`BOOLEAN`).
     5. Variables (`TEXT`, `VARCHAR`, `NUMERIC`, `JSONB`).
3. **Manejo Temporal**:
   - Usar siempre `TIMESTAMPTZ` para instantes en el tiempo (UTC).
   - Incluir `created_at` y `updated_at` (con trigger `trg_set_updated_at`).
4. **Validaciones e Integridad**:
   - Agregar restricciones `CHECK` para rangos, estados permitidos y no negatividad.

### Fase 3: Estrategia de Indexación
1. **Obligatorio**: Indexar toda columna de Foreign Key para evitar escaneos secuenciales y bloqueos de tabla en eliminaciones del padre.
2. **Índices Compuestos**: Ordenar columnas de igualdad estricta primero (`WHERE a = ?`) y columnas de rango u ordenamiento al final (`WHERE b >= ? ORDER BY b`).
3. **Índices Parciales**: Si una consulta filtra por estados activos o pendientes, crear el índice con cláusula `WHERE` (ej: `WHERE deleted_at IS NULL`).
4. **JSONB**: Indexar con `USING gin (payload jsonb_path_ops)`.
5. **Presupuesto**: No superar 3 a 5 índices por tabla en OLTP.

### Fase 4: Generación de DDL Seguro (Zero-Downtime)
1. Encabezar el script con guardarraíles:
   ```sql
   SET lock_timeout = '2s';
   SET statement_timeout = '30s';
   ```
2. Usar sentencias idempotentes: `CREATE TABLE IF NOT EXISTS`.
3. Crear índices con `CREATE INDEX CONCURRENTLY` (fuera de transacción).
4. Agregar Foreign Keys en 2 pasos: `NOT VALID` y posterior `VALIDATE CONSTRAINT`.
5. Entregar siempre el script de reversión (`MIGRATION DOWN`).

### Fase 5: Gobernanza y Autodocumentación
1. Redactar sentencia `COMMENT ON TABLE <table> IS '...'`.
2. Redactar sentencias `COMMENT ON COLUMN <table>.<col> IS '...'` para cada columna.
3. Etiquetar campos sensibles con el prefijo `'PII: ...'`.

---

## Lista de Verificación (Checklist de Aprobación DDL)

Antes de dar por finalizado un DDL, verificar que cumple:

- [ ] Todos los identificadores están en `snake_case` minúsculas sin comillas dobles.
- [ ] No se utilizan palabras reservadas de SQL/PostgreSQL sin contexto.
- [ ] La clave primaria está definida explícitamente (`UUIDv7` o `BIGINT Identity`).
- [ ] Todas las claves foráneas tienen su respectivo índice creado en la tabla hija.
- [ ] Las columnas de fecha/hora usan `TIMESTAMPTZ` (nunca `TIMESTAMP` a secas).
- [ ] Las columnas numéricas monetarias usan `NUMERIC` o centavos enteros en `BIGINT` (nunca float).
- [ ] Se utilizó `JSONB` en lugar de `JSON`.
- [ ] No existe `CHAR(n)` (se usó `TEXT` o `VARCHAR`).
- [ ] Las columnas están ordenadas minimizando el padding de alineación de tupla.
- [ ] El script incluye `SET lock_timeout = '2s'` y no genera bloqueos exclusivos prolongados.
- [ ] Se generaron los comentarios `COMMENT ON TABLE` y `COMMENT ON COLUMN` (incluyendo marcas de PII).
- [ ] Se incluyó el script de rollback (`Down`).
