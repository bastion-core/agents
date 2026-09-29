# Acuerdos de Nivel de Servicio (SLAs) de Frescura y Monitoreo de Latencia

Este documento define la metodología para medir, auditar y alertar sobre la frescura de los datos en bases de datos PostgreSQL y almacenes analíticos.

---

## 1. Definición Formal de Frescura de Datos

La frescura mide el tiempo transcurrido desde el último evento registrado o la última sincronización respecto al tiempo actual en UTC:

$$\text{Staleness} = \text{clock\_timestamp()} - \max(\text{event\_timestamp\_utc})$$

### Parámetros Canónicos del SLA
- **`max_staleness`**: Desfase máximo tolerado antes de considerar que el pipeline o la fuente transaccional está degradada.
- **`warn_after`**: Umbral preventivo (alerta interna al equipo de datos).
- **`error_after`**: Umbral crítico de violación de SLA (notificación de incidente PagerDuty y afectación a dashboards).

---

## 2. Consulta Canónica de Auditoría de Frescura en PostgreSQL

```sql
-- Auditoría de frescura para tablas críticas transaccionales o marts
SELECT
    'core.orders' AS table_name,
    max(ordered_at) AS last_record_at,
    clock_timestamp() AS checked_at,
    clock_timestamp() - max(ordered_at) AS current_staleness,
    CASE
        WHEN clock_timestamp() - max(ordered_at) > interval '1 hour' THEN 'CRITICAL'
        WHEN clock_timestamp() - max(ordered_at) > interval '20 minutes' THEN 'WARNING'
        ELSE 'OK'
    END AS freshness_status
FROM core.orders;
```

---

## 3. Configuración en dbt `sources.yml`

```yaml
# models/staging/sources.yml
version: 2

sources:
  - name: ecommerce
    database: prod_db
    schema: raw
    tables:
      - name: orders
        loaded_at_field: _ingested_at
        freshness:
          warn_after: {count: 30, period: minute}
          error_after: {count: 60, period: minute}
```
