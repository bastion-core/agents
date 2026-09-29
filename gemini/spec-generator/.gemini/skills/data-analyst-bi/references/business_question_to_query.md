# Traducción Metodológica: de Pregunta de Negocio a Consulta SQL

Este documento establece el marco para interactuar con stakeholders de producto o negocio no técnicos, transformar preguntas difusas en especificaciones exactas y construir consultas analíticas sin ambigüedad.

---

## 1. El Ciclo de Traducción en 4 Pasos

```text
Pregunta Informal ➔ Desambiguación & Reglas ➔ Contrato de Datos (Grano) ➔ SQL Analítico
```

### Paso 1: Identificación del Objetivo de Decisión
- **Pregunta del Stakeholder**: "¿Cómo van las ventas de este mes y quiénes son los mejores clientes?"
- **Desglose de Desambiguación**:
  1. ¿Qué significa "ventas"? ¿Ingresos brutos facturados, ingresos netos tras descuentos, o cobros efectivamente liquidados en pasarela de pago?
  2. ¿Qué significa "este mes"? ¿Mes calendario actual hasta el instante de la consulta, o mes cerrado anterior?
  3. ¿Qué define al "mejor cliente"? ¿Volumen total monetario (LTV acumulado), frecuencia de pedidos, o margen neto de contribución?

### Paso 2: Formalización de Reglas de Negocio
Redactar una declaración explícita de supuestos para validación con el stakeholder:
- **Venta Válida**: Órdenes con `order_status = 'COMPLETED'` y `payment_status = 'SETTLED'`. Excluir devoluciones (`is_refunded = TRUE`).
- **Mejores Clientes**: Clientes en el percentil 90 o superior de gasto neto acumulado en los últimos 90 días UTC.

### Paso 3: Definición del Grano y Entidades
- **Entidades Involucradas**: `marts.fct_orders`, `marts.dim_customers`.
- **Grano de Salida**: 1 fila por `customer_id`.

### Paso 4: Construcción de la Consulta Canónica
```sql
-- Owner: data-analyst-bi / data-scientist
-- Purpose: Responder al negocio el Top 10% de clientes por ingreso neto en los últimos 90 días

WITH customer_net_spend AS (
    SELECT
        c.customer_id,
        c.customer_nk,
        c.full_name,
        c.email,
        sum(o.net_amount_usd) AS total_net_spent_usd,
        count(distinct o.order_id) AS total_orders,
        ntile(10) OVER (ORDER BY sum(o.net_amount_usd) DESC) AS spend_decile
    FROM marts.fct_orders o
    JOIN marts.dim_customers c ON o.customer_sk = c.customer_sk
    WHERE o.order_date_utc >= current_date - interval '90 days'
      AND o.order_status = 'COMPLETED'
      AND o.deleted_at IS NULL
    GROUP BY 1, 2, 3, 4
)
SELECT
    customer_id,
    customer_nk,
    full_name,
    email,
    total_net_spent_usd,
    total_orders
FROM customer_net_spend
WHERE spend_decile = 1 -- Top 10% de clientes
ORDER BY total_net_spent_usd DESC;
```

---

## 2. Matriz de Clarificación de Preguntas Frecuentes

| Pregunta del Stakeholder | Ambigüedad Clave | Definición Canónica Recomendada |
|---|---|---|
| "¿Cuántos usuarios perdimos?" | Definición de Churn | Inactividad absoluta de sesiones/compras durante 30 días continuos |
| "¿Cuál es el ticket promedio?" | AOV (Average Order Value) | Ingreso neto total / Conteo de órdenes válidas completadas |
| "¿Cuánto margen nos queda?" | Gross vs Net Margin | (Ingresos netos - Costo de bienes vendidos) / Ingresos netos * 100 |
| "¿Qué canal rinde mejor?" | Atribución de Marketing | Modelo First-Touch vs Last-Touch vs Atribución Lineal explícita |
