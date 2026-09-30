---
name: data-quality-governance
description: "Estándares de calidad y gobernanza de datos: contratos de datos, suites de Great Expectations o Soda, linaje de datos, clasificación/enmascaramiento PII y SLAs de frescura."
---

# Data Quality & Governance Skill (Contracts, Soda/GX, Lineage, PII & Freshness)

Este skill define los estándares de calidad, observabilidad y gobernanza de datos para arquitecturas híbridas (OLTP y OLAP/DWH). Establece directrices rigurosas para implementar contratos de datos, pruebas de calidad declarativas (Great Expectations / SodaCL), linaje integral, protección de datos sensibles (PII) y acuerdos de nivel de servicio (SLAs) de frescura.

---

## Capacidades Principales

1. **Contratos de Datos (Data Contracts)**:
   - Especificación formal entre productores y consumidores: esquema tipado, restricciones semánticas, SLA de disponibilidad y política de breaking changes versionada (`v1` $\to$ `v2`).
2. **Suites de Calidad de Datos (Great Expectations & SodaCL)**:
   - Declaración de expectativas y validaciones automatizadas pre/post ingesta.
   - Guardas Fail-Fast: bloqueo de pipeline ante fallos críticos vs alertas preventivas.
3. **Linaje de Datos y Trazabilidad (Lineage)**:
   - Linaje a nivel de tabla y columna (OpenLineage, dbt lineage).
   - Análisis de impacto downstream antes de aplicar migraciones DDL.
4. **Clasificación y Enmascaramiento de PII (Personally Identifiable Information)**:
   - Taxonomía estricta de datos personales: Directos (DNI, email, teléfono, tarjeta) e Indirectos (IP, geolocalización, fecha nacimiento).
   - Enmascaramiento dinámico en PostgreSQL (`pgcrypto`, vistas enmascaradas, roles restringidos) y hashing determinista con salt.
   - Catalogación mandatoria mediante metadatos `COMMENT ON COLUMN ... IS 'PII: [Categoría] - [Regla de Enmascaramiento]'`.
5. **SLAs de Frescura y Latencia de Datos (Freshness)**:
   - Medición continua de desfase temporal (`max_staleness`).
   - Umbrales de advertencia (`warn_after`) y error crítico (`error_after`).

---

## Módulos de Referencia Especializados

Consultar los módulos técnicos en `references/`:

- **Contratos de Datos**: `references/data_contracts_and_schemas.md` — Estructura estándar YAML de data contract, control de cambios y versionado semántico.
- **Validaciones con Great Expectations y Soda**: `references/great_expectations_and_soda_checks.md` — Sintaxis SodaCL y GX Expectation Suites para tablas OLTP/OLAP.
- **Linaje y Catálogo de Metadatos**: `references/lineage_and_metadata.md` — Mapeo de linaje columna a columna y gobernanza de impacto.
- **Clasificación y Enmascaramiento PII**: `references/pii_classification_and_masking.md` — Patrones DDL de enmascaramiento dinámico, pseudonimización y etiquetado.
- **SLAs de Frescura y Monitoreo**: `references/freshness_slas_and_monitoring.md` — Definición de SLAs temporales, queries de auditoría y alertas.

---

## Checklist de Gobernanza y Calidad de Datos

Antes de certificar una arquitectura de datos o migración, verificar:

- [ ] Las tablas expuestas a terceros o analítica cuentan con un Data Contract formal.
- [ ] Existen pruebas declarativas (SodaCL o GX) para nulos, unicidad y rangos de valor.
- [ ] Todo atributo con PII está clasificado en `COMMENT ON COLUMN` con prefijo `PII:`.
- [ ] Los usuarios no privilegiados consumen vistas con enmascaramiento dinámico o hashing.
- [ ] El SLA de frescura está definido con columna temporal UTC de referencia.
- [ ] El impacto downstream en linaje fue validado para prevenir quiebres de dashboards o modelos.
