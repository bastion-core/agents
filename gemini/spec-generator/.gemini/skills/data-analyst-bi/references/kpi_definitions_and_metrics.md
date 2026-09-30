# Definición Formal de KPIs y Marcos de Métricas

Este documento establece el estándar de ingeniería y análisis para definir, formalizar y auditar Indicadores Clave de Rendimiento (KPIs) de manera unívoca y matemáticamente rigurosa.

---

## 1. Ficha Técnica Canónica de KPI

Para evitar discrepancias en reportes o interpretaciones divergentes entre equipos de producto, negocio e ingeniería, cada KPI debe contar con una ficha técnica completa:

| Campo | Descripción | Ejemplo |
|---|---|---|
| **Nombre del KPI** | Identificador unívoco en `snake_case` | `monthly_active_users_mau` |
| **Nombre Comercial** | Nombre comprensible para stakeholders | Usuarios Activos Mensuales (MAU) |
| **Objetivo de Negocio** | Pregunta o decisión que responde el KPI | Monitorear la retención y adopción recurrente del producto |
| **Fórmula Matemática** | Expresión algebraica formal | $\text{MAU}_m = \text{CountDistinct}(\text{user\_id} \mid \text{event\_at} \in [m_{\text{start}}, m_{\text{end}}] \land \text{is\_valid\_session} = \text{true})$ |
| **Numerador** | Componente superior (o conteo base) | Conteo único de `user_id` con al menos una sesión válida |
| **Denominador** | Componente divisor (si aplica ratio/tasa) | N/A (Métrica de volumen absoluto) |
| **Grano (Granularidad)** | Unidad mínima de agregación temporal y dimensional | Mensual por `country_code` y `tenant_id` |
| **Filtros de Inclusión** | Condiciones `WHERE` obligatorias | `is_internal_account = FALSE`, `deleted_at IS NULL` |
| **Exclusiones / Casos Borde** | Qué registros quedan expresamente descartados | Bots, transacciones de prueba (`is_test = TRUE`) |
| **Zona Horaria** | Estándar temporal universal | UTC (`TIMESTAMPTZ`) |
| **Cadencia de Refresco** | Periodicidad de cálculo y actualización | Diario a las 02:00 UTC |
| **Propietario (Owner)** | Rol o equipo responsable de la métrica | Product Analytics Team |

---

## 2. Tipología y Fórmulas Estándar de KPIs

### 2.1 Ratios y Tasas (Prevención de División por Cero)
En SQL y bases de datos relacionales, todo ratio debe usar `NULLIF` en el denominador para prevenir excepciones de runtime:

$$\text{Conversion Rate} = \frac{\text{Conversions}}{\text{Total Sessions}}$$

```sql
-- SQL Canónico para Ratio Seguro
SELECT
    date_trunc('month', session_at) AS metric_month,
    count(distinct case when is_converted then session_id end) AS conversions,
    count(distinct session_id) AS total_sessions,
    round(
        count(distinct case when is_converted then session_id end)::numeric /
        nullif(count(distinct session_id), 0) * 100, 
        2
    ) AS conversion_rate_pct
FROM marts.fct_web_sessions
GROUP BY 1;
```

### 2.2 Métricas de Retención y Cohortes
- **D7 / D30 Retention**: Porcentaje de usuarios que regresan en una ventana específica tras su evento de activación inicial.
- **Churn Rate**:
  $$\text{Monthly Churn Rate} = \frac{\text{Churned Customers in Month } M}{\text{Active Customers at Start of Month } M}$$

### 2.3 Métricas de Variación Temporal (MoM y YoY)
Cálculo de crecimiento mes a mes (Month-over-Month) o año contra año (Year-over-Year) utilizando funciones de ventana:

```sql
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', order_date_utc)::date AS revenue_month,
        sum(net_amount_usd) AS monthly_revenue
    FROM marts.fct_orders
    WHERE order_status = 'COMPLETED'
    GROUP BY 1
)
SELECT
    revenue_month,
    monthly_revenue,
    lag(monthly_revenue, 1) OVER (ORDER BY revenue_month) AS prev_month_revenue,
    round(
        (monthly_revenue - lag(monthly_revenue, 1) OVER (ORDER BY revenue_month)) /
        nullif(lag(monthly_revenue, 1) OVER (ORDER BY revenue_month), 0) * 100,
        2
    ) AS mom_growth_pct
FROM monthly_revenue;
```

---

## 3. Principio de Aditividad en Métricas

- **Totalmente Aditivas**: Pueden sumarse a través de cualquier dimensión (ej: `sales_amount_cents`, `item_quantity`).
- **Semi-Aditivas**: Pueden sumarse a través de algunas dimensiones (como producto o cliente), pero NUNCA a través del tiempo (ej: `account_balance`, `inventory_stock_count` — requieren agregación puntual al cierre de periodo).
- **No Aditivas**: Ratios, promedios y porcentajes (ej: `margin_pct`, `conversion_rate`). Nunca deben promediarse promedios; se deben recalcular los numeradores y denominadores agregados antes de dividir.
