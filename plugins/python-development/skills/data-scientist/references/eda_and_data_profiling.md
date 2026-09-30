# Exploratory Data Analysis (EDA) & Data Profiling

Este documento establece los estándares de calidad metodológica, rigor analítico y arquitectura de código para el Análisis Exploratorio de Datos (EDA) y perfilamiento de datasets.

---

## 1. Arquitectura Híbrida: Módulos `.py` + Companion Notebook `.ipynb`

Para garantizar la reproducibilidad científica y al mismo tiempo facilitar la comunicación ejecutiva y técnica:

```text
src/
├── features/                          # Módulos puros de Python (lógica desacoplada)
│   ├── profiling.py                   # Cálculo de estadísticas descriptivas, cardinalidad y tipos
│   ├── missing_analysis.py            # Auditoría y pruebas de tipos de valores faltantes (MCAR, MAR)
│   ├── outlier_detector.py            # Detección multivariada y univariada de anomalías
│   └── correlation.py                 # Matrices de asociación continua y categórica
notebooks/
│   └── 01_exploratory_data_analysis.ipynb # Companion notebook (visualizaciones, storytelling e insights)
reports/
│   ├── eda_executive_summary.md       # Resumen ejecutivo con hallazgos clave
│   └── figures/                       # Gráficos estáticos exportados en alta resolución (PNG/SVG)
```

**Regla de Oro**: Ninguna transformación o lógica de limpieza crítica debe vivir exclusivamente en las celdas de un Jupyter Notebook. El notebook importa funciones desde `src/` y actúa como capa de presentación e interacción.

---

## 2. Metodología de Perfilamiento en 4 Fases

### Fase 1: Inspección Estructural y Contratos de Esquema
1. **Dimensiones y Tipado Físico vs Conceptual**:
   - Identificar variables numéricas continuas, discretas, categóricas nominales, categóricas ordinales y temporales.
   - Auditar IDs y claves que no deben entrar como predictoras directas.
2. **Cardinalidad y Varianza Cero**:
   - Detectar columnas con varianza cero (constantes) o cuasi-cero (`quasi-constant variance < 0.01`).
   - Identificar alta cardinalidad en variables categóricas (>100 categorías) para planificar esquemas de reducción (Target Encoding, Frequency Encoding o agrupamiento en `Other`).

### Fase 2: Diagnóstico Riguroso de Valores Faltantes
Clasificar la naturaleza del valor faltante antes de imputar:
- **MCAR (Missing Completely at Random)**: La falta de datos no depende de ninguna variable observada ni no observada.
- **MAR (Missing at Random)**: La falta depende de otras variables observadas (ej: salario no reportado dependiente de nivel educativo).
- **MNAR (Missing Not at Random)**: La falta depende del valor en sí mismo (ej: personas con ingresos extremos que ocultan su ingreso).

```python
# src/features/missing_analysis.py
import pandas as pd
from typing import Dict, Any

def audit_missing_values(df: pd.DataFrame) -> pd.DataFrame:
    """Genera un reporte completo de completitud por columna."""
    missing_count = df.isnull().sum()
    missing_pct = (missing_count / len(df)) * 100
    
    summary = pd.DataFrame({
        "missing_count": missing_count,
        "missing_percentage": missing_pct,
        "dtype": df.dtypes
    }).query("missing_count > 0").sort_values(by="missing_percentage", ascending=False)
    
    return summary
```

### Fase 3: Análisis y Detección de Valores Atípicos (Outliers)
Distinguir entre anomalías legítimas de negocio (ej: fraude, transacciones masivas) y errores de instrumentación/captura:
- **Univariado**:
  - Rango Intercuartílico (IQR): $[Q1 - 1.5 \times IQR, Q3 + 1.5 \times IQR]$.
  - Z-Score modificado con mediana y MAD (Median Absolute Deviation) para distribuciones no normales.
- **Multivariado**:
  - `IsolationForest` o `LocalOutlierFactor (LOF)` para combinaciones de variables multidimensionales anómalas.

```python
# src/features/outlier_detector.py
import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest

def detect_multivariate_outliers(df: pd.DataFrame, contamination: float = 0.02) -> pd.Series:
    """Detecta anomalías multivariadas usando Isolation Forest sin filtrar el dataset original."""
    numeric_df = df.select_dtypes(include=[np.number]).dropna()
    iso = IsolationForest(contamination=contamination, random_state=42, n_jobs=-1)
    preds = iso.fit_predict(numeric_df)
    return pd.Series(preds == -1, index=numeric_df.index, name="is_anomaly")
```

### Fase 4: Análisis Bivariado, Multivariado y Asociación
- **Numérica vs Numérica**: Correlación de Pearson (lineal, requiere normalidad) vs Spearman / Kendall (monotónica no paramétrica).
- **Categórica vs Categórica**: V de Cramér o Coeficiente de Incertidumbre de Theil.
- **Numérica vs Categórica**: Ratio de Correlación ($\eta$) o pruebas ANOVA / Kruskal-Wallis.
- **Multicolinealidad**: Factor de Inflación de la Varianza (`VIF > 5` amerita remoción o combinación de features).

---

## 3. Prevención Estricta de Data Leakage en EDA

1. **Partición Previa Obligatoria**: Si el objetivo del proyecto incluye entrenamiento supervisado de Machine Learning, el EDA exploratorio a fondo debe ejecutarse sobre el conjunto de **Train** tras realizar un split estratificado o temporal.
2. **Prohibición de Transformaciones Globales**: Nunca calcular medias de imputación, desviaciones de estandarización o rangos min-max sobre el dataset completo antes del split.
