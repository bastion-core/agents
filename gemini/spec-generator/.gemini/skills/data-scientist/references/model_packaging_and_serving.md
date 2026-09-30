# Model Packaging & Serving (FastAPI, ONNX & Batch Inference)

Este documento define los estándares para la serialización, exportación de alto rendimiento y servido de inferencia (tiempo real y batch) con **FastAPI** y **ONNX Runtime**.

---

## 1. Estrategia de Serialización y Exportación

| Tipo de Modelo | Formato de Producción | Herramienta | Caso de Uso |
|---|---|---|---|
| **Scikit-Learn / LightGBM** | `.onnx` o `.joblib` | `skl2onnx`, `joblib` | Endpoints de ultra baja latencia (<10ms) |
| **PyTorch Deep Learning** | `.onnx` o TorchScript | `torch.onnx.export`, `torch.jit` | Inferencia en CPU/GPU sin runtime de Python |
| **Pesos y Checkpoints** | `.safetensors` | `safetensors.torch` | Almacenamiento seguro sin riesgo de código arbitrario |

```python
# src/serving/export_onnx.py
import onnxruntime as ort
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

def export_pipeline_to_onnx(pipeline, num_features: int, output_path: str):
    """Convierte un pipeline de Scikit-Learn a formato estándar ONNX."""
    initial_type = [("float_input", FloatTensorType([None, num_features]))]
    onx = convert_sklearn(pipeline, initial_types=initial_type)
    with open(output_path, "wb") as f:
        f.write(onx.SerializeToString())
```

---

## 2. Servicio de Inferencia en Tiempo Real con FastAPI

El servicio debe usar esquemas estrictos de Pydantic v2 y cargar los artefactos una sola vez mediante el evento `lifespan`:

```python
# src/serving/app.py
from contextlib import asynccontextmanager
import time
import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

class PredictionRequest(BaseModel):
    age: int = Field(..., ge=18, le=100, description="Edad del cliente")
    account_balance: float = Field(..., description="Saldo de cuenta en USD")
    active_products: int = Field(..., ge=0, description="Número de productos activos")
    has_credit_card: bool = Field(..., description="Tenencia de tarjeta de crédito")

    model_config = {
        "json_schema_extra": {
            "examples": [{
                "age": 35,
                "account_balance": 15420.50,
                "active_products": 2,
                "has_credit_card": True
            }]
        }
    }

class PredictionResponse(BaseModel):
    prediction: int = Field(..., description="Etiqueta predicha (0 o 1)")
    probability: float = Field(..., ge=0.0, le=1.0, description="Probabilidad de la clase positiva")
    latency_ms: float = Field(..., description="Latencia de inferencia en milisegundos")
    model_version: str

ml_artifacts = {}

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Carga eficiente del modelo en memoria en el arranque
    ml_artifacts["pipeline"] = joblib.load("models/champion_pipeline.joblib")
    ml_artifacts["version"] = "v2.1.0"
    yield
    ml_artifacts.clear()

app = FastAPI(title="ML Inference Service", version="1.0.0", lifespan=lifespan)

@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    return {"status": "healthy", "model_version": ml_artifacts.get("version")}

@app.post("/predict", response_model=PredictionResponse)
async def predict_single(payload: PredictionRequest):
    pipeline = ml_artifacts.get("pipeline")
    if pipeline is None:
        raise HTTPException(status_code=500, detail="El modelo no se encuentra disponible")

    start_time = time.perf_counter()
    input_df = pd.DataFrame([payload.model_dump()])

    try:
        prob = float(pipeline.predict_proba(input_df)[:, 1][0])
        pred = int(prob >= 0.5)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error durante la inferencia: {str(e)}")

    latency = (time.perf_counter() - start_time) * 1000.0

    return PredictionResponse(
        prediction=pred,
        probability=round(prob, 4),
        latency_ms=round(latency, 2),
        model_version=ml_artifacts["version"],
    )
```

---

## 3. Pipeline de Inferencia en Lotes (Batch Scoring)

Para procesar millones de registros periódicamente desde bases de datos o almacenamiento columnar (Parquet):

```python
# src/serving/batch_inference.py
import pandas as pd
import joblib

def run_batch_inference(
    input_parquet_path: str, output_parquet_path: str, model_path: str, batch_size: int = 50_000
):
    """Ejecuta inferencia por bloques para optimizar el uso de RAM."""
    model = joblib.load(model_path)
    
    # Procesamiento por chunks
    reader = pd.read_parquet(input_parquet_path, engine="pyarrow")
    scored_chunks = []

    for i in range(0, len(reader), batch_size):
        chunk = reader.iloc[i : i + batch_size].copy()
        probs = model.predict_proba(chunk)[:, 1]
        chunk["predicted_score"] = probs
        chunk["scored_at"] = pd.Timestamp.now(tz="UTC")
        scored_chunks.append(chunk)

    final_df = pd.concat(scored_chunks, ignore_index=True)
    final_df.to_parquet(output_parquet_path, index=False)
```

---

## 4. Detección de Data Drift (Deriva de Datos)

En producción, se auditan las variables de entrada contra el baseline de entrenamiento utilizando el **Índice de Estabilidad Poblacional (PSI)**:

$$PSI = \sum \left( Actual\% - Expected\% \right) \times \ln\left(\frac{Actual\%}{Expected\%}\right)$$

- $PSI < 0.1$: No hay cambio significativo en la distribución.
- $0.1 \le PSI < 0.25$: Cambio moderado; requiere alerta preventiva.
- $PSI \ge 0.25$: Desvío severo (Data Drift); reentrenamiento obligatorio.
