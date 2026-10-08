# PostgreSQL Loading Patterns: Physical Optimization, Idempotency & Audit

Este documento establece las mejores prácticas de arquitectura y carga masiva en PostgreSQL, aplicando los estándares de `data-architecture-postgre`.

---

## 1. Orden Físico de Columnas (Alineación de Tuplas)

Para evitar el desperdicio de memoria y CPU padding por alineación a múltiplos de 8 bytes en PostgreSQL, **todas las tablas deben ordenar sus columnas estrictamente de mayor a menor tamaño**:

1. **Fijos de 8 bytes**: `BIGINT`, `TIMESTAMPTZ`, `DOUBLE PRECISION`, `UUID`.
2. **Fijos de 4 bytes**: `INTEGER`, `DATE`, `REAL`.
3. **Fijos de 2 bytes**: `SMALLINT`.
4. **Fijos de 1 byte**: `BOOLEAN`, `CHAR(1)`.
5. **Variables (Varlena)**: `TEXT`, `VARCHAR`, `NUMERIC`, `JSONB`, `BYTEA`.

### Ejemplo Canónico de DDL en Ingesta Raw
```sql
-- sql/raw/010_raw_customers.sql
-- Owner: data-engineer-airflow
-- Purpose: Almacenar clientes crudos normalizados en el borde (landing zone)

CREATE TABLE IF NOT EXISTS raw.customers (
    -- Fijos 8 bytes
    customer_sk         BIGINT GENERATED ALWAYS AS IDENTITY,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    _ingested_at        TIMESTAMPTZ NOT NULL,
    
    -- Fijos 4 bytes
    registration_date   DATE NOT NULL,
    
    -- Fijos 1 byte
    is_active           BOOLEAN NOT NULL DEFAULT true,

    -- Variables (Varlena)
    customer_nk         TEXT NOT NULL,
    email               TEXT NOT NULL,
    customer_status     VARCHAR(30) NOT NULL,
    _dag_id             VARCHAR(100) NOT NULL,
    _run_id             VARCHAR(100) NOT NULL,
    _record_hash        VARCHAR(64) NOT NULL,

    CONSTRAINT pk_raw_customers PRIMARY KEY (customer_sk),
    CONSTRAINT uq_raw_customers_nk UNIQUE (customer_nk)
);

CREATE INDEX IF NOT EXISTS idx_raw_customers_email ON raw.customers (email);
CREATE INDEX IF NOT EXISTS idx_raw_customers_ingested ON raw.customers (_ingested_at DESC);
```

---

## 2. Guardarraíles de Sesión y DDL Seguro

Toda ejecución de scripts o transacciones de carga debe estar protegida contra bloqueos prolongados:

```sql
SET lock_timeout = '2s';
SET statement_timeout = '30s';
```

---

## 3. Carga Masiva Idempotente (Bulk Raw + Upsert)

En lugar de inserciones fila por fila (`INSERT INTO ... VALUES (...)`), se utiliza una tabla temporal no indexada cargada vía `COPY` o `execute_values`, seguida de un merge con `INSERT ... ON CONFLICT DO UPDATE`.

### Targets de Conflicto por Capa

| Capa | Clave de Conflicto (`ON CONFLICT (...)`) | Comportamiento |
|---|---|---|
| `raw.*` | `(customer_nk)` o `(_record_hash)` | `DO UPDATE SET updated_at = clock_timestamp(), ...` o `DO NOTHING` |
| `stg.*` | N/A (Vistas construidas sobre `raw.*` vía dbt) | Lógica declarativa en dbt |
| `core.dim_*` | Business Key (`customer_id`) | SCD Tipo 1 o SCD Tipo 2 gestionado en dbt |
| `core.fct_*` | `(order_sk)` o grano transaccional | Materialización incremental en dbt (`merge`) |

### Implementación del Loader en Python
```python
import io
import pandas as pd
import psycopg2.extras
from pipelines.core import Step, StepContext
from pipelines.utils.db.database_manager import DatabaseManager

class PostgresCustomersLoader(Step):
    """Carga datos limpios a PostgreSQL raw de forma masiva e idempotente."""

    def execute(self, context: StepContext) -> None:
        df: pd.DataFrame = context.get_artifact("cleaned_customers_df")
        if df is None or df.empty:
            context.record_metric("loaded_rows", 0)
            return

        # Metadatos del run
        df["_dag_id"] = context.dag_id or "local_run"
        df["_run_id"] = context.run_id or "local_exec"
        
        # Conexión a la base de datos
        db_mgr = DatabaseManager()
        engine = db_mgr.get_engine()

        raw_conn = engine.raw_connection()
        try:
            with raw_conn.cursor() as cur:
                cur.execute("SET lock_timeout = '2s'; SET statement_timeout = '30s';")

                # 1. Crear tabla unlogged temporal de carga
                cur.execute("""
                    CREATE TEMP TABLE tmp_raw_customers (
                        customer_nk TEXT,
                        email TEXT,
                        customer_status VARCHAR(30),
                        registration_date DATE,
                        _ingested_at TIMESTAMPTZ,
                        _dag_id VARCHAR(100),
                        _run_id VARCHAR(100),
                        _record_hash VARCHAR(64)
                    ) ON COMMIT DROP;
                """)

                # 2. Bulk copy en memoria usando StringIO
                csv_buffer = io.StringIO()
                df[[
                    "customer_nk", "email", "customer_status", "registration_date",
                    "_ingested_at", "_dag_id", "_run_id", "_record_hash"
                ]].to_csv(csv_buffer, index=False, header=False, sep="\t", na_rep="\\N")
                csv_buffer.seek(0)

                cur.copy_from(csv_buffer, "tmp_raw_customers", columns=(
                    "customer_nk", "email", "customer_status", "registration_date",
                    "_ingested_at", "_dag_id", "_run_id", "_record_hash"
                ))

                # 3. Upsert atómico hacia la tabla destino raw
                upsert_query = """
                    INSERT INTO raw.customers (
                        customer_nk, email, customer_status, registration_date,
                        _ingested_at, _dag_id, _run_id, _record_hash
                    )
                    SELECT 
                        customer_nk, email, customer_status, registration_date,
                        _ingested_at, _dag_id, _run_id, _record_hash
                    FROM tmp_raw_customers
                    ON CONFLICT (customer_nk) DO UPDATE SET
                        email = EXCLUDED.email,
                        customer_status = EXCLUDED.customer_status,
                        registration_date = EXCLUDED.registration_date,
                        updated_at = clock_timestamp(),
                        _ingested_at = EXCLUDED._ingested_at,
                        _dag_id = EXCLUDED._dag_id,
                        _run_id = EXCLUDED._run_id,
                        _record_hash = EXCLUDED._record_hash;
                """
                cur.execute(upsert_query)
                raw_conn.commit()

            context.record_metric("loaded_rows", len(df))
        finally:
            raw_conn.close()
```

---

## 4. Esquema de Observabilidad: `audit.pipeline_runs`

Cada pipeline debe registrar su ejecución en una tabla central de auditoría.

```sql
-- sql/core/000_audit_pipeline_runs.sql
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.pipeline_runs (
    -- Fijos 8 bytes
    audit_id            BIGINT GENERATED ALWAYS AS IDENTITY,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    finished_at         TIMESTAMPTZ,
    duration_seconds    DOUBLE PRECISION,

    -- Variables (Varlena)
    dag_id              VARCHAR(100) NOT NULL,
    run_id              VARCHAR(150) NOT NULL,
    logical_date        VARCHAR(50) NOT NULL,
    run_status          VARCHAR(20) NOT NULL, -- 'SUCCESS', 'FAILED'
    metrics             JSONB,
    error_message       TEXT,

    CONSTRAINT pk_pipeline_runs PRIMARY KEY (audit_id),
    CONSTRAINT uq_pipeline_runs_execution UNIQUE (dag_id, run_id)
);

CREATE INDEX IF NOT EXISTS idx_audit_runs_dag_date 
ON audit.pipeline_runs (dag_id, started_at DESC);
```
