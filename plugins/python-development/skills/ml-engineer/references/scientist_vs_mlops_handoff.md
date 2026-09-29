# Contrato de Handoff: Data Scientist vs ML Engineer (MLOps)

Este documento define la frontera formal entre la fase de experimentación y la fase operativa de Machine Learning.

---

## 1. El Principio Fundamental

> **Los científicos de datos experimentan; los ingenieros de ML operan y mantienen los modelos en producción.**

- El **Data Scientist** no debe sobrecargarse configurando balanceadores de carga, monitoreo de infraestructura de inferencia, gateways de API o pipelines de CI/CD para modelos.
- El **ML Engineer** no debe reescribir la lógica matemática ni modificar las decisiones estadísticas del modelo; toma el artefacto empaquetado y garantiza su disponibilidad, baja latencia, observabilidad y reentrenamiento.

---

## 2. Los Entregables Obligatorios del Data Scientist (Definition of Done)

Para que el ML Engineer acepte un modelo en el ciclo de MLOps, el Data Scientist debe proporcionar:

1. **Artifact en MLflow**: Run registrado con modelo empaquetado (PyFunc, Scikit-learn, ONNX o TorchScript).
2. **Model Signature Tipada**: Esquema estricto de inputs y outputs inferido mediante `mlflow.models.infer_signature`.
3. **Métricas en Blind Test Set**: Valores reproducibles de las métricas clave (PR-AUC, F1-Macro, Brier Score, Cohen's d).
4. **Conjunto de Datos de Referencia (Baseline Distribution)**: Distribución de variables predictoras en Train para cálculo de PSI inicial.
5. **Reporte Metodológico**: Explicabilidad SHAP, justificación de exclusión de features y confirmación de que no existe data leakage.

---

## 3. Las Responsabilidades del ML Engineer en Producción

Recibido el artefacto:
1. Registra el modelo como `@challenger` en el Model Registry.
2. Construye el endpoint de inferencia con FastAPI o Triton Server (lifespan, Pydantic v2, métricas Prometheus).
3. Habilita Shadow Deployment para evaluar latencia P95/P99 en condiciones reales.
4. Programa el cálculo periódico de drift (PSI) sobre el tráfico de inferencia.
5. Diseña el DAG de reentrenamiento continuo en Airflow.
