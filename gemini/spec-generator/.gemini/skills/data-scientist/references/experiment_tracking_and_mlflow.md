# Experiment Tracking & Model Registry with MLflow

Este documento define los estándares para el seguimiento de experimentos, versionado de hiperparámetros, métricas, artefactos y gobernanza de modelos en el registro central con **MLflow**.

---

## 1. Configuración de Entorno y Buenas Prácticas

Todo script de experimentación debe iniciar configurando explícitamente el servidor de tracking y el nombre del experimento:

```python
import mlflow
import os

# 1. Configuración de URI (servidor remoto o ruta local)
TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
mlflow.set_tracking_uri(TRACKING_URI)

# 2. Experimento agrupado por dominio de negocio y caso de uso
EXPERIMENT_NAME = "churn_prediction_v2"
mlflow.set_experiment(EXPERIMENT_NAME)
```

---

## 2. Protocolo de Registro de Runs (Parámetros, Métricas y Artefactos)

Un run de MLflow debe ser 100% reproducible y auditable. Debe registrar:
1. **Tags de Contexto**: Autor, commit hash de Git, tipo de modelo, split temporal/estratificado.
2. **Hiperparámetros**: Diccionario completo de parámetros de preprocesamiento y del estimador.
3. **Métricas por Época o Step**: Para redes neuronales o boosting iterativo, registrar la pérdida y métricas con `step=epoch`.
4. **Métricas Finales**: Métricas sobre conjunto de validación y conjunto de prueba (Test).
5. **Artefactos Visuales**: Gráficos de evaluación guardados como imágenes (PR-Curve, Matriz de Confusión, SHAP summary plot).
6. **Firma del Modelo (Signature)**: Esquema estricto de tipos de entrada y salida inferido con `infer_signature`.

```python
# src/models/train_and_track.py
import mlflow
import mlflow.sklearn
from mlflow.models.signature import infer_signature
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import classification_report, average_precision_score, confusion_matrix

def train_and_track_model(pipeline, X_train, y_train, X_test, y_test, run_name: str):
    with mlflow.start_run(run_name=run_name):
        # 1. Tags de gobierno
        mlflow.set_tags({
            "framework": "lightgbm",
            "problem_type": "binary_classification",
            "eval_metric": "pr_auc",
        })

        # 2. Registrar hiperparámetros
        params = pipeline.named_steps["classifier"].get_params()
        mlflow.log_params(params)

        # 3. Entrenamiento
        pipeline.fit(X_train, y_train)

        # 4. Evaluación en Test Set
        y_prob = pipeline.predict_proba(X_test)[:, 1]
        y_pred = (y_prob >= 0.5).astype(int)

        pr_auc = average_precision_score(y_test, y_prob)
        mlflow.log_metric("test_pr_auc", pr_auc)

        # 5. Generar y registrar artefactos visuales
        cm = confusion_matrix(y_test, y_pred, normalize="true")
        plt.figure(figsize=(6, 5))
        sns.heatmap(cm, annot=True, fmt=".2f", cmap="Blues")
        plt.title("Normalized Confusion Matrix")
        cm_path = "confusion_matrix.png"
        plt.savefig(cm_path, bbox_inches="tight")
        plt.close()
        mlflow.log_artifact(cm_path)

        # 6. Reporte en texto/markdown
        report = classification_report(y_test, y_pred, output_dict=False)
        with open("classification_report.txt", "w") as f:
            f.write(report)
        mlflow.log_artifact("classification_report.txt")

        # 7. Firma y empaquetado del modelo
        signature = infer_signature(X_test, y_prob)
        
        mlflow.sklearn.log_model(
            sk_model=pipeline,
            artifact_path="model",
            signature=signature,
            registered_model_name="customer_churn_model",
        )
```

---

## 3. Gobernanza en MLflow Model Registry

El ciclo de vida del modelo utiliza alias y tags para la promoción segura:

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()

# Asignar alias al modelo campeón y retador
client.set_registered_model_alias(
    name="customer_churn_model",
    alias="champion",
    version="3",
)

client.set_registered_model_alias(
    name="customer_churn_model",
    alias="challenger",
    version="4",
)
```

**Guardarraíl de Calidad**: Ningún modelo puede promoverse a `champion` sin haber superado al modelo en producción en la métrica primaria acordada (ej: PR-AUC) evaluada sobre el mismo test set ciego o split temporal.
