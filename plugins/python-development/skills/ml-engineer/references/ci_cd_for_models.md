# CI/CD para Modelos de Machine Learning (Continuous Integration & Delivery)

Este documento define la automatización de pruebas, empaquetado y despliegue continuo de artefactos de Machine Learning.

---

## 1. Pirámide de Pruebas de Software para ML

En un pipeline de CI/CD para ML, no basta con evaluar métricas de pérdida: el modelo debe someterse a pruebas de software formales:

1. **Pruebas de Invarianza**: Modificaciones en variables no predictoras o perturbaciones mínimas (ej: cambiar de mayúscula a minúscula un texto) no deben alterar la predicción.
2. **Pruebas Direccionales (Morphic Tests)**: Aumentar el saldo impago o la antigüedad de mora debe monotónicamente aumentar (o mantener) la probabilidad de default predicha.
3. **Pruebas de Rendimiento por Slice**: Evaluar que ningún subgrupo demográfico o geográfico crítico sufra una caída de rendimiento superior al 15% respecto al promedio global.
4. **Pruebas de Latencia y Memoria**: Verificar que la inferencia unitaria responda en $<50\text{ ms}$ (P99) bajo una carga simulada.

---

## 2. Implementación de Behavioral Tests en Pytest

```python
"""tests/ml/test_model_behavior.py"""

import numpy as np
import pytest


def test_monotonic_risk_increase(trained_pipeline, sample_input_df):
    """Verifica que incrementar 'days_past_due' incremente el riesgo predicho."""
    base_prob = trained_pipeline.predict_proba(sample_input_df)[:, 1][0]

    higher_risk_df = sample_input_df.copy()
    higher_risk_df["days_past_due"] += 60

    new_prob = trained_pipeline.predict_proba(higher_risk_df)[:, 1][0]
    assert new_prob >= base_prob, "Violación de monotonicidad en riesgo"


def test_invariance_to_minor_noise(trained_pipeline, sample_input_df):
    """Verifica estabilidad ante pequeñas perturbaciones numéricas."""
    base_pred = trained_pipeline.predict(sample_input_df)[0]

    perturbed_df = sample_input_df.copy()
    perturbed_df["session_duration_sec"] += 1.0  # +1 segundo no cambia predicción

    perturbed_pred = trained_pipeline.predict(perturbed_df)[0]
    assert base_pred == perturbed_pred, "Inestabilidad numérica ante ruido mínimo"
```

---

## 3. Estrategias de Despliegue en Producción

- **Shadow Deployment (Dark Traffic)**: El modelo candidato recibe una copia del tráfico real en segundo plano sin responder a los clientes. Sus predicciones y latencia se comparan contra el champion en silencio.
- **Canary Release**: Se enruta un 5% del tráfico al nuevo modelo candidato. Si la tasa de error 5xx es 0 y las métricas de negocio se mantienen estables durante 24 horas, se escala progresivamente a 100%.
