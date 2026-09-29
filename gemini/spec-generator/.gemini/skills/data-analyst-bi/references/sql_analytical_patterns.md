# Patrones de SQL Analítico Avanzado para Business Intelligence

Este documento reúne patrones canónicos y optimizados de SQL analítico para PostgreSQL y Data Warehouses basados en Kimball (`marts.*`).

---

## 1. Patrón Modular con Common Table Expressions (CTEs)

Toda consulta compleja debe estructurarse en bloques lógicos secuenciales:
1. `filtered_events`: Selección acotada con proyección de columnas y filtros de partición.
2. `windowed_metrics`: Aplicación de funciones analíticas de ventana.
3. `aggregated_summary`: Agrupación y cálculo de métricas finales.

---

## 2. Análisis de Cohortes y Retención

Cálculo de la retención de usuarios agrupados por el mes en que realizaron su primera acción:

```sql
WITH user_first_activity AS (
    SELECT
        user_id,
        date_trunc('month', min(activity_at))::date AS cohort_month
    FROM marts.fct_user_activities
    GROUP BY user_id
),

user_monthly_activity AS (
    SELECT DISTINCT
        user_id,
        date_trunc('month', activity_at)::date AS activity_month
    FROM marts.fct_user_activities
),

cohort_retention AS (
    SELECT
        f.cohort_month,
        (extract(year FROM a.activity_month) - extract(year FROM f.cohort_month)) * 12 +
        (extract(month FROM a.activity_month) - extract(month FROM f.cohort_month)) AS month_number,
        count(distinct f.user_id) AS active_users
    FROM user_first_activity f
    JOIN user_monthly_activity a ON f.user_id = a.user_id
    GROUP BY 1, 2
),

cohort_sizes AS (
    SELECT cohort_month, active_users AS initial_cohort_size
    FROM cohort_retention
    WHERE month_number = 0
)

SELECT
    r.cohort_month,
    s.initial_cohort_size,
    r.month_number,
    r.active_users,
    round(r.active_users::numeric / nullif(s.initial_cohort_size, 0) * 100, 2) AS retention_rate_pct
FROM cohort_retention r
JOIN cohort_sizes s ON r.cohort_month = s.cohort_month
ORDER BY r.cohort_month, r.month_number;
```

---

## 3. Embudos de Conversión (Funnels) Secuenciales

Seguimiento de progresión secuencial de pasos (ej: Visita $\to$ Registro $\to$ Checkout $\to$ Pago):

```sql
WITH funnel_stages AS (
    SELECT
        session_id,
        max(case when event_name = 'PAGE_VIEW' then 1 else 0 end) AS step_1_view,
        max(case when event_name = 'SIGN_UP' then 1 else 0 end) AS step_2_signup,
        max(case when event_name = 'CHECKOUT_STARTED' then 1 else 0 end) AS step_3_checkout,
        max(case when event_name = 'ORDER_PAID' then 1 else 0 end) AS step_4_paid
    FROM marts.fct_web_events
    WHERE event_date_utc >= current_date - interval '30 days'
    GROUP BY session_id
)
SELECT
    sum(step_1_view) AS stage_1_views,
    sum(case when step_1_view = 1 and step_2_signup = 1 then 1 else 0 end) AS stage_2_signups,
    sum(case when step_1_view = 1 and step_2_signup = 1 and step_3_checkout = 1 then 1 else 0 end) AS stage_3_checkouts,
    sum(case when step_1_view = 1 and step_2_signup = 1 and step_3_checkout = 1 and step_4_paid = 1 then 1 else 0 end) AS stage_4_payments
FROM funnel_stages;
```

---

## 4. Ventanas Deslizantes y Medias Móviles (Rolling Windows)

Cálculo de ingresos acumulados móviles de 7 y 30 días para suavizar la estacionalidad diaria:

```sql
SELECT
    order_date_utc,
    daily_revenue,
    round(avg(daily_revenue) OVER (
        ORDER BY order_date_utc
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_avg_7d_revenue,
    round(avg(daily_revenue) OVER (
        ORDER BY order_date_utc
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_avg_30d_revenue
FROM (
    SELECT
        order_date_utc,
        sum(net_amount_usd) AS daily_revenue
    FROM marts.fct_daily_orders
    GROUP BY 1
) sub
ORDER BY order_date_utc;
```
