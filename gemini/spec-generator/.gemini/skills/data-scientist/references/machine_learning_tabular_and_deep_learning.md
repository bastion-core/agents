# Machine Learning: Tabular Ensembles & Deep Learning

Este documento define los estándares para el diseño, entrenamiento, validación y explicabilidad de modelos de Machine Learning (Scikit-Learn, LightGBM, XGBoost, CatBoost) y Deep Learning (PyTorch, Hugging Face).

---

## 1. Prevención Estricta de Data Leakage (Fuga de Datos)

El Data Leakage es la causa número uno de modelos que rinden excelente en validación pero fallan en producción.
1. **Encapsulamiento en Pipeline**: Todo preprocesamiento (escalado, imputación, One-Hot Encoding, Target Encoding) DEBE ejecutarse dentro de un `Pipeline` o `ColumnTransformer` de Scikit-Learn.
2. **Validación Cruzada Adecuada**:
   - **Datos tabulares estándar (IID)**: `StratifiedKFold` para clasificación; `KFold` para regresión.
   - **Datos temporales**: `TimeSeriesSplit` (entrenar siempre en el pasado y evaluar en el futuro; jamás usar random split).
   - **Datos agrupados**: `GroupKFold` o `StratifiedGroupKFold` (si un cliente tiene múltiples filas, todas sus filas deben estar exclusivamente en Train o en Test).

```python
# src/models/tabular_pipeline.py
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
import lightgbm as lgb

def build_lgbm_pipeline(
    numeric_features: list[str], categorical_features: list[str]
) -> Pipeline:
    """Construye un pipeline hermético libre de data leakage."""
    num_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler", StandardScaler()),
    ])

    cat_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="constant", fill_value="missing")),
        ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
    ])

    preprocessor = ColumnTransformer(transformers=[
        ("num", num_transformer, numeric_features),
        ("cat", cat_transformer, categorical_features),
    ])

    model = lgb.LGBMClassifier(
        n_estimators=500,
        learning_rate=0.03,
        num_leaves=31,
        random_state=42,
        importance_type="gain",
    )

    return Pipeline(steps=[
        ("preprocessor", preprocessor),
        ("classifier", model),
    ])
```

---

## 2. Deep Learning Modular con PyTorch

Para arquitecturas de redes neuronales, el código debe seguir un patrón modular y reproducible:

```python
# src/models/neural_net.py
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader

class TabularDataset(Dataset):
    """Dataset tipado para datos tabulares en PyTorch."""
    def __init__(self, X: torch.Tensor, y: torch.Tensor):
        self.X = X
        self.y = y

    def __len__(self) -> int:
        return len(self.X)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return self.X[idx], self.y[idx]

class MultiLayerPerceptron(nn.Module):
    """MLP con regularización (Dropout, BatchNorm) para clasificación/regresión."""
    def __init__(self, input_dim: int, hidden_dim: int, output_dim: int, dropout: float = 0.2):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.BatchNorm1d(hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.BatchNorm1d(hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim // 2, output_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)
```

### Bucle de Entrenamiento y Validación con Early Stopping
- Calcular pérdida y métricas en validación al final de cada época.
- Implementar **Early Stopping** (paciencia entre 5 y 10 épocas) monitoreando la pérdida de validación.
- Aplicar Gradient Clipping (`torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)`) para prevenir explosión de gradientes.

---

## 3. Matriz de Selección de Métricas de Evaluación

Nunca evaluar modelos utilizando métricas engañosas (ej: Accuracy en datasets desbalanceados):

| Tipo de Problema | Métrica Primaria | Métricas Secundarias | Métricas de Diagnóstico |
|---|---|---|---|
| **Clasificación Desbalanceada** | **PR-AUC (Average Precision)** | F1-Macro, Matthews Corr (MCC) | Brier Score, Curva Precision-Recall |
| **Clasificación Balanceada** | **ROC-AUC** | Accuracy, F1-Weighted | Matriz de Confusión normalizada |
| **Regresión Continua** | **RMSE / MAE** | WAPE (Weighted Absolute %) | $R^2$, Residuos vs Predichos |
| **Rankings / Recomendación** | **NDCG@k** | MAP@k, MRR | Hit Rate@k |

---

## 4. Interpretabilidad y Explicabilidad (SHAP & Permutation Importance)

Todo modelo predictivo que afecte decisiones de negocio debe ser interpretable:
1. **SHAP (SHapley Additive exPlanations)**:
   - Modelos de árboles: `shap.TreeExplainer(model)`.
   - Redes neuronales / pipelines genéricos: `shap.Explainer` o `shap.KernelExplainer`.
   - Entregables: **Summary Plot (Beeswarm)** para impacto global de variables y **Waterfall Plot** para explicaciones locales fila por fila.
2. **Permutation Feature Importance**:
   - Evaluar siempre sobre el conjunto de test/validación independiente, nunca sobre train.
