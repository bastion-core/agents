# Contratos de Datos (Data Contracts) y Gobernanza de Esquemas

Este documento establece la metodología y el formato estándar para definir Contratos de Datos formales entre productores de datos (sistemas transaccionales / APIs) y consumidores (pipelines, analítica y ML).

---

## 1. Estructura Canónica de un Data Contract

Un Data Contract es un artefacto declarativo (generalmente versionado en Git) que especifica:
1. **Metadatos y Propietarios**: Versión del contrato, equipo productor, consumidores autorizados.
2. **Esquema Físico y Tipado**: Nombre de columnas, tipos de datos, nulabilidad y ordenamiento.
3. **Reglas de Calidad y Semántica**: Restricciones de negocio (rangos de valores, formatos regex).
4. **Acuerdo de Nivel de Servicio (SLA)**: Frescura máxima permitida, disponibilidad y retención.

```yaml
# contracts/orders_data_contract.v1.yml
version: 1.0.0
dataset: core.orders
domain: payments
status: active
owner:
  team: Core Checkout Engineering
  contact: checkout-team@company.com

schema:
  type: table
  columns:
    - name: order_id
      type: uuid
      primary_key: true
      nullable: false
      description: "Identificador UUIDv7 único universal de la orden."
    - name: customer_id
      type: uuid
      foreign_key: core.customers.customer_id
      nullable: false
    - name: order_status
      type: text
      nullable: false
      allowed_values: ['PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED']
    - name: total_amount_cents
      type: bigint
      nullable: false
      minimum: 0
    - name: ordered_at
      type: timestamptz
      nullable: false

service_level_agreement:
  freshness:
    max_staleness: 15 minutes
    timestamp_column: ordered_at
  quality_checks:
    null_threshold_pct: 0.0
    uniqueness_guarantee: true

breaking_change_policy:
  notification_period: 30 days
  versioning_rule: "Cualquier eliminación de columna o cambio de tipo fuerza incremento de versión mayor (v2)."
```

---

## 2. Política de Cambios No Disruptivos (Non-Breaking Changes)

- **Cambios No Disruptivos Permitidos**:
  - Agregar una columna nueva opcional (`NULL` o con default inmutable).
  - Agregar un valor permitido a un catálogo o enum existente.
  - Relajar una restricción de validación (ej: ampliar rango de valores permitidos).
- **Cambios Disruptivos (Breaking Changes)**:
  - Eliminar o renombrar cualquier columna existente.
  - Modificar el tipo de datos de una columna.
  - Convertir una columna nullable en `NOT NULL`.
  - Violación de breaking change requiere migración paralela (`v1` y `v2` coexistiendo durante ventana de deprecación).
