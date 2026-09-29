---
name: data-analyst-bi
description: Estándares de análisis de datos y BI: consultas analíticas SQL avanzadas, especificaciones de dashboards, marcos de definición de KPIs y traducción de preguntas de negocio.
---

# Data Analyst & BI Skill (SQL, KPIs, Dashboards & Business Analytics)

Este skill proporciona el conocimiento metodológico y técnico para transformar preguntas de negocio en consultas SQL optimizadas, definir métricas clave (KPIs) con rigor matemático y diseñar especificaciones ejecutivas de dashboards para la toma de decisiones informadas.

---

## Capacidades Principales

1. **Traducción de Preguntas de Negocio**: Desambiguar requerimientos cualitativos de stakeholders no técnicos y traducirlos en definiciones cuantitativas exactas, granularidades y consultas SQL reproducibles.
2. **Definición Rigurosa de KPIs**: Estandarizar métricas mediante fichas técnicas completas (fórmula, numerador, denominador, grano, filtros, dimensiones de corte, casos borde y cadencia).
3. **Especificaciones de Dashboards y Visualización**: Diseñar wireframes conceptuales, matrices de selección de gráficos, parámetros interactivos, jerarquías de filtros y umbrales de alerta.
4. **Patrones de SQL Analítico Avanzado**: Construcción de consultas complejas utilizando Common Table Expressions (CTEs), funciones de ventana (`ROW_NUMBER`, `DENSE_RANK`, `LAG`/`LEAD`), análisis de cohortes, embudos de conversión (funnels) y agregaciones multidimensionales.

---

## Recursos de Referencia Especializados

Para directrices técnicas detalladas, consultar los módulos en `references/`:

- **Traducción de Preguntas de Negocio**: `references/business_question_to_query.md` — Metodología de 4 pasos para desambiguar requerimientos de stakeholders, identificar entidades, granularidades y supuestos analíticos.
- **Definición de KPIs y Métricas**: `references/kpi_definitions_and_metrics.md` — Estructura estándar de ficha técnica de KPI, cálculo de ratios seguros con `NULLIF`, métricas acumuladas y de variación temporal (MoM, YoY).
- **Especificaciones de Dashboards**: `references/dashboard_specifications.md` — Plantilla formal de especificación de dashboard (audiencia, cuadrícula, matriz de selección de visualizaciones, filtros y alertas).
- **Patrones de SQL Analítico**: `references/sql_analytical_patterns.md` — Patrones avanzados de SQL: análisis de cohortes y retención, embudos de conversión, ventanas de tiempo deslizantes y percentiles.

---

## Workflow del Analista de Datos & BI (4 Fases)

```
1. Desambiguación de Pregunta ➔ 2. Ficha Técnica de KPI ➔ 3. Consulta SQL Analítica ➔ 4. Especificación de Dashboard
```

### Fase 1: Desambiguación de la Pregunta de Negocio
1. Identificar al stakeholder y el objetivo de decisión (¿qué acción se tomará con esta respuesta?).
2. Descomponer conceptos cualitativos (ej: "¿cliente activo?") en reglas de negocio auditables (ej: "transacción exitosa en los últimos 30 días UTC").
3. Acordar el grano de análisis (nivel de detalle: usuario, transacción, día, cohorte).

### Fase 2: Definición y Formalización de KPIs
1. Documentar la fórmula matemática exacta:
   - Numerador y Denominador explícitos.
   - Prevención de división por cero mediante `NULLIF(denominador, 0)`.
2. Definir dimensiones de corte permitidas (ej: país, canal de adquisición, segmento).
3. Establecer la ventana temporal y cadencia de refresco.

### Fase 3: Construcción de SQL Analítico Modular
1. Utilizar patrón CTE modular: importación de staging/marts $\to$ transformaciones/ventanas $\to$ agregación final.
2. Filtrar explícitamente registros eliminados (`deleted_at IS NULL`) y estados transaccionales válidos.
3. Asegurar determinismo y respeto de la zona horaria universal (UTC).

### Fase 4: Especificación de Dashboard y Entrega
1. Seleccionar la visualización adecuada según el tipo de variable (tendencia, comparación, composición, distribución).
2. Documentar la distribución en cuadrícula (grid) y jerarquía visual.
3. Detallar filtros globales y dependientes.

---

## Checklist de Aprobación de Entregables de BI

Antes de dar por aprobada una especificación analítica o consulta SQL, verificar:

- [ ] La pregunta de negocio original está documentada junto a sus supuestos explícitos.
- [ ] La granularidad del resultado está unívocamente definida (clave primaria de la tabla resultante).
- [ ] Todas las divisiones en SQL están protegidas contra ceros (`NULLIF`).
- [ ] Los filtros temporales respetan la zona horaria UTC (`TIMESTAMPTZ`).
- [ ] No se utiliza `SELECT *` descontrolado en las consultas analíticas.
- [ ] Se documentó la fórmula de cada KPI con numerador, denominador y exclusiones.
- [ ] La especificación del dashboard define tipo de gráfico justificado y jerarquía de filtros.
