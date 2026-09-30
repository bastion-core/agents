# Extraction Patterns: Structured, Semi-Structured & Unstructured Data

Este documento detalla los estándares y patrones de extracción e ingesta para pipelines de datos sobre el scaffold de Apache Airflow y PostgreSQL.

---

## 1. Patrón Dual de Conexiones y Secretos

Los pipelines deben ser ejecutables tanto dentro de los workers de Airflow como de forma desacoplada (scripts CLI, pruebas unitarias y entornos de desarrollo local).

### Estándar de Resolución
1. **Runtime de Airflow**: Si la librería `airflow` está instalada y se provee un `conn_id`, se resuelve la conexión mediante `airflow.hooks.base.BaseHook.get_connection(conn_id)`.
2. **Runtime Standalone / Local / Tests**: Si no hay contexto de Airflow o falla la resolución de la conexión, se recurre a `Settings` respaldado por Pydantic leyendo variables de entorno (`.env`).

### Implementación Canónica: `resolve_connection_params`
```python
from typing import Any
import os
from pipelines.config.settings import get_settings

def resolve_db_url(conn_id: str | None = None) -> str:
    """Resuelve la URL de base de datos priorizando Airflow Connections con fallback a Settings."""
    if conn_id:
        try:
            from airflow.hooks.base import BaseHook
            conn = BaseHook.get_connection(conn_id)
            return conn.get_uri()
        except Exception:
            pass  # Fallback a settings si no estamos en runtime de Airflow

    settings = get_settings()
    return settings.DATABASE_URL
```

---

## 2. Ingesta de Datos Semi-Estructurados (REST APIs, JSON, Webhooks)

### Principio: Raw Preservation + Deterministic Hashing
- Todo payload JSON recibido debe preservarse intacto en la capa `raw.<fuente>` en una columna `payload JSONB`.
- Se genera un hash determinista (`record_hash`) mediante SHA-256 sobre el JSON canónico (claves ordenadas) para garantizar deduplicación e idempotencia.

### Cálculo Canónico del `record_hash`
```python
import hashlib
import json
from typing import Any

def compute_record_hash(data: dict[str, Any] | list[Any]) -> str:
    """Calcula el hash SHA-256 canónico para deduplicación idempotente."""
    canonical_json = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()
```

### Extractor de API Canónico
```python
import requests
from typing import Any
from pipelines.core import Step, StepContext

class RestApiExtractor(Step):
    """Extrae datos de API REST preservando payloads crudos y metadatos."""
    
    def __init__(self, endpoint_url: str, headers: dict[str, str] | None = None, timeout: int = 30):
        super().__init__()
        self.endpoint_url = endpoint_url
        self.headers = headers or {}
        self.timeout = timeout

    def execute(self, context: StepContext) -> None:
        response = requests.get(self.endpoint_url, headers=self.headers, timeout=self.timeout)
        response.raise_for_status()
        records: list[dict[str, Any]] = response.json()

        enriched_records = []
        for item in records:
            rec_hash = compute_record_hash(item)
            enriched_records.append({
                "record_hash": rec_hash,
                "payload": json.dumps(item),
                "_ingested_at": context.logical_date,
            })

        context.set_artifact("raw_records", enriched_records)
        context.record_metric("extracted_rows", len(enriched_records))
```

---

## 3. Ingesta de Datos No Estructurados (Archivos, PDFs, Imágenes, Audio)

### Principio: Almacenamiento Desacoplado (Object Storage + PostgreSQL Manifest)
- Los archivos binarios o no estructurados **nunca** se almacenan como `BLOB` o `BYTEA` dentro de tablas relacionales de PostgreSQL.
- Se depositan en Object Storage (S3 / GCS / MinIO / Local FS).
- PostgreSQL actúa como catálogo/manifiesto en una tabla `raw.<dominio>_files` registrando metadatos: URI, SHA-256, tamaño en bytes, tipo MIME y fechas de auditoría.

### Esquema Canónico de Manifiesto en PostgreSQL
```sql
-- DDL en sql/raw/001_raw_file_manifest.sql
CREATE TABLE IF NOT EXISTS raw.file_manifest (
    -- Fijos 8 bytes
    file_id             BIGINT GENERATED ALWAYS AS IDENTITY,
    byte_size           BIGINT NOT NULL,
    _ingested_at        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    
    -- Variables (Varlena)
    file_uri            TEXT NOT NULL,
    content_sha256      TEXT NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    source_system       VARCHAR(100) NOT NULL,
    metadata            JSONB,

    CONSTRAINT pk_file_manifest PRIMARY KEY (file_id),
    CONSTRAINT uq_file_manifest_hash UNIQUE (content_sha256)
);

CREATE INDEX IF NOT EXISTS idx_file_manifest_ingested_at 
ON raw.file_manifest (_ingested_at DESC);
```

### Extractor de Archivos / Object Storage
```python
import hashlib
from pathlib import Path
from pipelines.core import Step, StepContext

class FileMetadataExtractor(Step):
    """Inspecciona archivos no estructurados y genera metadatos para el manifiesto."""

    def __init__(self, source_path: Path, storage_prefix: str):
        super().__init__()
        self.source_path = source_path
        self.storage_prefix = storage_prefix

    def execute(self, context: StepContext) -> None:
        manifest_entries = []
        for file_path in self.source_path.glob("*.*"):
            if file_path.is_file():
                sha256_hash = hashlib.sha256()
                byte_size = 0
                with open(file_path, "rb") as f:
                    for chunk in iter(lambda: f.read(65536), b""):
                        sha256_hash.update(chunk)
                        byte_size += len(chunk)

                manifest_entries.append({
                    "file_uri": f"{self.storage_prefix}/{file_path.name}",
                    "content_sha256": sha256_hash.hexdigest(),
                    "byte_size": byte_size,
                    "mime_type": "application/octet-stream",
                    "source_system": "external_landing",
                    "_ingested_at": context.logical_date,
                })

        context.set_artifact("file_manifest", manifest_entries)
        context.record_metric("extracted_files_count", len(manifest_entries))
```

---

## 4. Ingesta Estructurada (RDBMS / BigQuery / SQL)

- Consultas SQL parametrizadas siempre por partición temporal (`logical_date` / `ds`).
- Proyección explícita de columnas (evitar `SELECT *`).
- Asignación de `_ingested_at = CURRENT_TIMESTAMP` y tracking del `record_hash` si la fuente de origen no posee una Primary Key estable.
