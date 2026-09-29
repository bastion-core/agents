# Pruebas Declarativas de Calidad de Datos (Great Expectations & SodaCL)

Este documento define la sintaxis y patrones de diseño para pruebas declarativas de calidad de datos usando SodaCL y Great Expectations en bases de datos PostgreSQL y almacenes analíticos.

---

## 1. Patrón Canónico con SodaCL (`soda/checks_orders.yml`)

SodaCL proporciona una sintaxis concisa y declarativa para evaluar la salud de tablas relacionales:

```yaml
# soda/checks_orders.yml
checks for core.orders:
  # 1. Integridad de Clave Primaria y Grain
  - duplicate_count(order_id) = 0:
      name: "Garantía de Unicidad de order_id"
  - missing_count(order_id) = 0:
      name: "Nulabilidad Prohibida en PK order_id"

  # 2. Integridad Referencial
  - values in (customer_id) must exist in core.customers (customer_id):
      name: "Consistencia de Clave Foránea hacia Clientes"

  # 3. Restricciones de Dominio y Rango
  - invalid_count(order_status) = 0:
      name: "Dominio Válido de order_status"
      valid values: ['PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED']

  - min(total_amount_cents) >= 0:
      name: "Monto No Negativo"

  # 4. Frescura y Flujo Continuo
  - freshness(ordered_at) < 30m:
      name: "SLA de Frescura: Última orden no mayor a 30 minutos"
      warn: when > 20m
      fail: when > 30m

  # 5. Detección de Anomalías de Volumen
  - row_count between 1000 and 500000:
      name: "Volumetría razonable esperada"
```

---

## 2. Expectation Suite con Great Expectations (Python API)

```python
"""quality/gx_orders_suite.py"""

import great_expectations as gx

context = gx.get_context()
validator = context.sources.pandas_default.read_sql(
    "SELECT * FROM core.orders LIMIT 10000"
)

# 1. Unicidad y Nulabilidad
validator.expect_column_values_to_be_unique(column="order_id")
validator.expect_column_values_to_not_be_null(column="order_id")
validator.expect_column_values_to_not_be_null(column="ordered_at")

# 2. Conjunto de Valores Aceptados
validator.expect_column_values_to_be_in_set(
    column="order_status",
    value_set=["PENDING", "PROCESSING", "COMPLETED", "FAILED", "CANCELLED"],
)

# 3. Rango de Fechas
validator.expect_column_values_to_be_between(
    column="ordered_at", min_value="2020-01-01", max_value="now"
)

# Guardar la suite
validator.save_expectation_suite(discard_failed_expectations=False)
```

---

## 3. Comportamiento ante Fallas (Fail-Fast vs Alerta Preventiva)

- **Fail-Fast (Blocking Gate)**: Errores en Claves Primarias (`duplicate_count > 0`), nulos en campos obligatorios o quiebre de tipos de datos abortan la transacción o detienen la ejecución del DAG downstream.
- **Warning (Preventive Alert)**: Variaciones moderadas de volumen ($\pm 20\%$) o alertas preventivas de frescura envían notificación a Slack sin detener el pipeline.
