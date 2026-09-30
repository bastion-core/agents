# Transformation Patterns: Pandas Cleaning & Fail-Fast Data Quality (Edge Processing)

Este documento establece las directrices de limpieza, normalización y validación de calidad de datos usando Pandas dentro del scaffold de pipelines de datos.

---

## 1. Regla de Oro: Pandas EXCLUSIVAMENTE en los Bordes

En la arquitectura moderna de datos (**Airflow + pandas + dbt**):
- **pandas se utiliza ÚNICAMENTE en los bordes**: ingesta desde APIs, archivos planos (CSV, Excel), payloads JSON/Webhooks, y formateo previo al aterrizaje de los datos en el almacén (Data Warehouse / PostgreSQL).
- **Prohibición estricta**: NUNCA utilizar pandas para realizar transformaciones, joins, agregaciones o cálculos analíticos sobre datos que ya residen en la base de datos o warehouse. Esas operaciones pertenecen exclusivamente a **dbt**.
- **Antipatrón Prohibido**: Extraer datos de tablas del warehouse hacia un DataFrame de pandas para limpiarlos o enriquecerlos y volver a insertarlos. Si los datos ya están en el warehouse, la transformación debe ser un modelo SQL de dbt.

---

## 2. Principio Fail-Fast (Calidad Estricta en Ingesta)

1. **Nunca ocultar errores**: Errores de esquema, columnas obligatorias faltantes o tipos corruptos deben fallar de inmediato con una excepción tipada (`DataValidationError`).
2. **Alertar al scheduler tempranamente**: Fallar en la fase de extracción/limpieza en el borde previene que datos corruptos lleguen a PostgreSQL o contaminen las capas de staging de dbt.
3. **Validación de contratos antes de la carga**: Todo contrato de tipos, nulabilidad y unicidad debe ser verificado antes de persistir los artefactos en el `StepContext` o emitirlos al Data Warehouse.

```python
class DataValidationError(Exception):
    """Excepción lanzada cuando los datos de borde no cumplen con las reglas de calidad."""
    pass
```

---

## 3. Limpieza y Normalización Canónica con Pandas

### Buenas Prácticas Obligatorias
- **Manejo Temporal Estricto**: Fechas y timestamps siempre normalizados a UTC usando `pd.to_datetime(..., utc=True)`.
- **Sanitización de Strings**: `.str.strip()`, conversión de strings vacíos o de espacios en blanco a `None` / `np.nan`.
- **Tipado Seguro**: Usar tipos nullables de Pandas (`Int64`, `boolean`, `string`) para evitar coerciones silenciosas de enteros a flotantes cuando existen valores nulos.
- **Deduplicación Pre-Carga**: Deduplicar sobre la Natural Key (`customer_nk` / `_nk`) antes de emitir los datos a la capa de carga.
- **Hash de Registro Determinista**: Mantener o calcular el hash SHA-256 (`record_hash`) para garantizar idempotencia en la base de datos destino.

### Transformador Canónico de Borde (Edge Transformer)
```python
import pandas as pd
from typing import Any
from pipelines.core import Step, StepContext

class DataValidationError(Exception):
    """Excepción para violaciones de contrato en la etapa de borde."""
    pass

class CleanCustomerDataTransformer(Step):
    """Limpia y valida registros crudos de clientes bajo política Fail-Fast en el borde."""

    MANDATORY_COLUMNS = {"customer_id", "email", "registration_date", "status"}
    VALID_STATUSES = {"ACTIVE", "INACTIVE", "SUSPENDED"}

    def execute(self, context: StepContext) -> None:
        raw_data = context.get_artifact("raw_records", default=[])
        if not raw_data:
            context.record_metric("transformed_rows", 0)
            return

        # 1. Cargar a DataFrame de Pandas
        df = pd.DataFrame(raw_data)

        # 2. Validación de Contrato de Columnas (Fail-Fast)
        missing_cols = self.MANDATORY_COLUMNS - set(df.columns)
        if missing_cols:
            raise DataValidationError(f"Faltan columnas requeridas en el dataset de origen: {missing_cols}")

        initial_count = len(df)

        # 3. Limpieza y Normalización de Textos
        df["customer_nk"] = df["customer_id"].astype(str).str.strip()
        df["email"] = df["email"].astype(str).str.strip().str.lower()
        df["status"] = df["status"].astype(str).str.strip().str.upper()

        # Validación estricta de dominios de valores
        invalid_statuses = set(df["status"]) - self.VALID_STATUSES
        if invalid_statuses:
            raise DataValidationError(f"Valores de status no permitidos detectados: {invalid_statuses}")

        # Normalización temporal a UTC
        df["registration_at"] = pd.to_datetime(df["registration_date"], utc=True, errors="coerce")
        if df["registration_at"].isna().any():
            null_dates_count = int(df["registration_at"].isna().sum())
            raise DataValidationError(f"Se detectaron {null_dates_count} registros con fechas corruptas o nulas.")

        # 4. Validación de Unicidad de Natural Key
        duplicates = df[df.duplicated(subset=["customer_nk"], keep=False)]
        if not duplicates.empty:
            raise DataValidationError(
                f"Violación de unicidad de Natural Key en origen: {len(duplicates)} filas duplicadas para customer_nk"
            )

        # 5. Metadatos técnicos de auditoría para carga
        df["_ingested_at"] = pd.to_datetime(context.logical_date, utc=True)
        df["_dag_id"] = context.dag_id or "unknown_dag"
        df["_run_id"] = context.run_id or "unknown_run"

        # 6. Almacenar el artefacto curado listo para el Loader
        context.set_artifact("cleaned_customers_df", df)
        context.record_metric("input_rows", initial_count)
        context.record_metric("transformed_rows", len(df))
```

---

## 4. Handoff hacia la Capa de Carga y dbt

Una vez que el DataFrame de Pandas ha sido limpiado, validado y enriquecido con metadatos de auditoría:
1. El artefacto es consumido por un **Loader** que realiza una inserción/upsert masivo en la tabla de staging (`stg.*` o `raw.*`) en PostgreSQL.
2. Tras la confirmación de la carga, el control del pipeline pasa inmediatamente a **dbt** (orquestado vía Astronomer Cosmos), quien asume todas las transformaciones posteriores dentro del warehouse.
