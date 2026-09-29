# Monitoreo de Data Drift, Concept Drift y Estrategias de Alerta

Este documento establece las métricas estadísticas y la arquitectura para detectar la degradación de modelos en producción.

---

## 1. Métricas de Detección de Drift

### 1.1 Population Stability Index (PSI)
Mide el cambio en la distribución de una variable entre la población de referencia (Train) y la ventana actual de producción (Inference):

$$PSI = \sum_{i=1}^{k} \left( \text{Actual}_i - \text{Expected}_i \right) \times \ln\left( \frac{\text{Actual}_i}{\text{Expected}_i} \right)$$

- **$PSI < 0.10$**: Estable. No hay cambio representativo en la población.
- **$0.10 \le PSI < 0.25$**: Drift Moderado. Emitir advertencia preventiva en observabilidad.
- **$PSI \ge 0.25$**: Drift Crítico. Disparar alarma de incidente y activar pipeline de reentrenamiento.

### 1.2 Distancia Wasserstein y Test Kolmogorov-Smirnov (KS)
Para variables continuas con distribuciones multimodales, el test KS de dos muestras o la distancia de Wasserstein (Earth Mover's Distance) permiten cuantificar el desplazamiento absoluto de masa de probabilidad.

---

## 2. Implementación de Monitoreo con Pandas y Scipy

```python
"""src/monitoring/drift_detector.py"""

import numpy as np
import pandas as pd


def calculate_psi(
    expected: np.ndarray, actual: np.ndarray, num_buckets: int = 10
) -> float:
    """Calcula el Population Stability Index entre referencia y producción."""
    # Definir cuantiles basados en la distribución de referencia
    percentiles = np.linspace(0, 100, num_buckets + 1)
    bucket_bounds = np.percentile(expected, percentiles)
    bucket_bounds[0] = -np.inf
    bucket_bounds[-1] = np.inf

    # Contar frecuencias por bucket
    expected_counts = pd.cut(expected, bins=bucket_bounds).value_counts(
        sort=False
    )
    actual_counts = pd.cut(actual, bins=bucket_bounds).value_counts(sort=False)

    # Convertir a proporciones con suavizado de Laplace para evitar división por cero
    expected_pct = (expected_counts + 1) / (len(expected) + num_buckets)
    actual_pct = (actual_counts + 1) / (len(actual) + num_buckets)

    # Fórmula del PSI
    psi_vector = (actual_pct - expected_pct) * np.log(actual_pct / expected_pct)
    return float(np.sum(psi_vector))
```

---

## 3. Matriz de Severidad y Acciones de Alerta

| Nivel de Alerta | Condición | Canal | Acción Automatizada |
|---|---|---|---|
| **Verde (Normal)** | $PSI < 0.10$ en todas las features clave | Métricas en Grafana | Ninguna |
| **Amarillo (Alerta)** | $0.10 \le PSI < 0.25$ en $\ge 2$ features | Notificación en Slack | Abrir ticket de inspección de fuentes |
| **Rojo (Crítico)** | $PSI \ge 0.25$ en top feature de SHAP | PagerDuty + Slack | Trigger de pipeline de reentrenamiento |
