# Exposures y Gobernanza de Datos Downstream en dbt

Este documento define las prácticas para registrar y gobernar consumidores downstream (dashboards, modelos ML y aplicaciones) mediante archivos `exposures.yml`.

---

## 1. El Rol de los Exposures

Los **Exposures** permiten a los Analytics Engineers definir, documentar e integrar en el grafo de linaje de dbt a los consumidores finales de los modelos (marts y métricas).

Habilitan:
1. **Análisis de Impacto de Cambios**: Ejecutar `dbt build --select +exposure:executive_dashboard` para validar toda la cadena de dependencias antes de un despliegue.
2. **Alertas de Salud en BI**: Saber con precisión qué dashboards se verán afectados si falla una prueba de datos en un mart.
3. **Catálogo Unificado**: Documentar a los propietarios del producto y enlaces directos a las herramientas de visualización.

---

## 2. Especificación Canónica de `exposures.yml`

```yaml
# models/exposures/exposures.yml
version: 2

exposures:
  - name: executive_kpi_dashboard
    label: "Dashboard Ejecutivo de KPIs de Ingresos y Crecimiento"
    type: dashboard
    maturity: high
    url: https://bi.company.com/dashboards/executive-kpis
    description: >
      Dashboard principal para C-Level y VPs que monitorea ingresos netos,
      tasa de churn mensual, ticket promedio y conversión de usuarios.

    depends_on:
      - ref('fct_orders')
      - ref('dim_customers')
      - metric('net_revenue_usd')
      - metric('average_order_value_aov')

    owner:
      name: Product Analytics Team
      email: analytics@company.com

  - name: churn_prediction_model_features
    label: "Feature Pipeline para Modelo de Churn"
    type: ml
    maturity: medium
    description: >
      Pipeline de inferencia batch que alimenta el modelo de predicción
      de churn gestionado por data-scientist en MLflow.

    depends_on:
      - ref('fct_orders')
      - ref('dim_customers')

    owner:
      name: Data Science Team
      email: data-science@company.com
```

---

## 3. Comandos de Linaje con Exposures

- **Ejecutar modelos que alimentan un dashboard específico**:
  ```bash
  dbt build --select +exposure:executive_kpi_dashboard
  ```
- **Identificar exposures afectados por un cambio en un modelo**:
  ```bash
  dbt ls --select fct_orders+ --resource-type exposure
  ```
