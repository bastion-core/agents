# Especificaciones de Dashboards y Directrices de Visualización

Este documento establece la metodología para diseñar especificaciones técnicas y funcionales de dashboards (Metabase, Superset, Tableau, Power BI) a partir de requerimientos de producto.

---

## 1. Plantilla Canónica de Especificación de Dashboard

Cada dashboard debe contar con un documento de especificación formal estructurado de la siguiente forma:

### 1.1 Metadatos Generales
- **Nombre del Dashboard**: Identificador formal y título de despliegue.
- **Audiencia Objetivo**: Ejecutivo (C-Level), Operacional, Producto o Finanzas.
- **Decisiones que Habilita**: Qué acciones concretas tomará el usuario basándose en los datos exhibidos.
- **Cadencia de Refresco**: Tiempo real, cada hora, o diario (batch).
- **Fuente de Datos / Capa**: Tablas y vistas en `marts.*` (DWH Kimball).

### 1.2 Jerarquía de Filtros Globales y Dependientes
| Nombre del Filtro | Tipo de Componente | Columna / Expresión SQL | Dependencia | Valor por Defecto |
|---|---|---|---|---|
| Rango de Fechas | Date Range Picker | `fct_orders.order_date_utc` | Ninguna | Últimos 30 días |
| País | Multi-select Dropdown | `dim_countries.country_code` | Ninguna | Todos |
| Canal de Venta | Single-select | `dim_channels.channel_name` | Depende de País | Todos |

---

## 2. Matriz de Selección de Visualizaciones

| Pregunta / Objetivo Analítico | Tipo de Gráfico Recomendado | Gráfico Alternativo | Antipatrón Prohibido |
|---|---|---|---|
| **Evolución en el tiempo** | Gráfico de Líneas (Line Chart) | Gráfico de Barras temporal | Gráficos de Torta (Pie Charts) |
| **Comparación entre categorías discretas** | Barras Horizontales / Columnas | Treemap | Gráficos de Radar / Donut multi-categoría |
| **Composición de un total (partes del todo)** | Barras 100% Apiladas | Donut (máximo 4 categorías) | Pie Chart con >5 rebanadas |
| **Distribución estadística de valores** | Histograma / Box Plot | Diagrama de Violín | Promedios simples sin varianza |
| **Relación / Correlación bivariada** | Diagrama de Dispersión (Scatter) | Heatmap de Densidad | Gráfico de líneas sin orden temporal |
| **Valores Clave / Indicadores Singulares** | Tarjeta de KPI (Scorecard) | Gauge / Medidor de rango | Tablas gigantescas sin jerarquía |

---

## 3. Distribución en Cuadrícula (Layout Grid 12-Columnas)

Todo dashboard de negocio sigue un patrón visual de pirámide invertida (de lo general a lo particular):

```text
┌────────────────────────────────────────────────────────────────────────┐
│ FILA 1: Barra de Filtros Globales (Fecha UTC, Segmento, Región)       │
├────────────────────────────────────────────────────────────────────────┤
│ FILA 2: 4 Tarjetas de KPIs Principales (Scorecards con variación vs LP)│
│ [ MRR / ARR ]     [ Active Users ]    [ Churn Rate % ]   [ LTV/CAC ]  │
├────────────────────────────────────────────────────────────────────────┤
│ FILA 3: Macrotendencias y Series Temporales (Líneas / Barras)          │
│ [ Evolución Mensual de Ingresos ]    [ Nuevos Usuarios vs Reactivados ]│
├────────────────────────────────────────────────────────────────────────┤
│ FILA 4: Desglose Dimensional y Distribución                            │
│ [ Ingresos por Categoría / País ]    [ Embudo de Conversión de Pasos ] │
├────────────────────────────────────────────────────────────────────────┤
│ FILA 5: Detalle Operacional (Tabla interactiva paginada con drill-down)│
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Alertas y Umbrales de Salud

Definir umbrales cromáticos o disparadores de notificación:
- **Verde (En Meta)**: Valor superior al objetivo presupuestado.
- **Amarillo (Alerta Preventiva)**: Desviación entre 5% y 15% por debajo de la meta.
- **Rojo (Crítico)**: Desviación >15% o caída de métrica de SLA.
