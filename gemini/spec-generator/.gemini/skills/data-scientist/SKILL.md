---
name: data-scientist
description: Estándares de ciencia de datos: EDA híbrido, inferencia estadística con pruebas de hipótesis, modelado ML y Deep Learning, experiment tracking con MLflow y servido API.
---

# Data Scientist Skill (EDA, Inferencia, ML, DL & MLflow)

Este skill proporciona el conocimiento experto, rigor metodológico y estándares de ingeniería para desempeñar proyectos de ciencia de datos de nivel sénior: desde el análisis exploratorio e inferencia estadística rigurosa, hasta el entrenamiento de modelos de Machine Learning / Deep Learning, seguimiento de experimentos con **MLflow** y despliegue de inferencia de producción con **FastAPI** y **ONNX**.

---

## Restricciones Duras e Invariantes Metodológicas

1. **Prevención Hermética de Data Leakage**:
   - Todo escalado, imputación, codificación categórica o ingeniería de atributos DEBE ejecutarse dentro de un `Pipeline` o `ColumnTransformer` de Scikit-Learn ajustado (`fit`) exclusivamente sobre el conjunto de entrenamiento (`train`).
   - El esquema de validación cruzada debe respetar la naturaleza de los datos: `StratifiedKFold` para clasificación estándar, `TimeSeriesSplit` para series temporales y `GroupKFold` para entidades agrupadas.
2. **Rigor Estadístico en Pruebas de Hipótesis**:
   - Jamás seleccionar un test de hipótesis a ciegas sin verificar previamente sus supuestos (normalidad con Shapiro-Wilk/D'Agostino-Pearson y homocedasticidad con Levene).
   - Un $p$-valor menor a 0.05 no es suficiente para declarar significancia práctica: es MANDATORIO reportar el **tamaño del efecto** (Cohen's $d$, Eta al cuadrado $\eta^2$ u Odds Ratio) junto al estimador puntual y sus intervalos de confianza del 95%.
   - Si se evalúan múltiples variantes o subgrupos, aplicar corrección de Benjamini-Hochberg (FDR) o Bonferroni.
3. **Arquitectura Híbrida de Código**:
   - Las funciones de extracción, limpieza, feature engineering, inferencia estadística y modelado deben residir en módulos de Python (`src/features/`, `src/models/`, `src/serving/`).
   - Los Jupyter Notebooks (`notebooks/*.ipynb`) actúan exclusivamente como compañeros de presentación, visualización narrativa y storytelling ejecutivo.
4. **Trazabilidad y Gobernanza con MLflow**:
   - Ningún modelo se considera finalizado sin registrar sus parámetros, métricas por split, artefactos visuales (curvas PR, matrices de confusión normalizadas, plots de SHAP) y su firma estricta (`infer_signature`) en MLflow.
   - Solo se promueve un modelo al alias `champion` en el Model Registry si supera de forma estadísticamente significativa al modelo actual en la métrica primaria acordada.
5. **Métricas Honestas según Problema**:
   - Prohibido optimizar o evaluar modelos desbalanceados con Accuracy. Usar **PR-AUC (Average Precision)**, F1-Macro o MCC.
   - Todo modelo probabilístico debe evaluar su calibración (Brier Score).
6. **Despliegue e Inferencia Segura**:
   - Los endpoints de inferencia deben validar entradas con esquemas tipados de Pydantic v2.
   - Se debe monitorear activamente la deriva de datos (Data Drift) utilizando el Population Stability Index (PSI).

---

## Recursos de Referencia Especializados

Para directrices técnicas detalladas, consultar los módulos en `references/`:

- **EDA y Perfilamiento**: `references/eda_and_data_profiling.md` — Metodología en 4 fases, diagnóstico de valores faltantes (MCAR, MAR, MNAR), detección multivariada de anomalías con Isolation Forest, matrices de asociación y arquitectura híbrida `.py` + `.ipynb`.
- **Inferencia y Pruebas de Hipótesis**: `references/statistical_inference_and_hypothesis_testing.md` — Árbol de decisión de pruebas estadísticas (Student, Welch, Mann-Whitney U, ANOVA, Kruskal-Wallis, Chi-cuadrado, Fisher), tamaño del efecto (Cohen's $d$), corrección por comparaciones múltiples (FDR) y modelos explicativos OLS/GLM en Statsmodels.
- **Machine Learning & Deep Learning**: `references/machine_learning_tabular_and_deep_learning.md` — Pipelines libres de data leakage, ensembles tabulares (LightGBM, XGBoost, CatBoost), arquitecturas modulares PyTorch, early stopping, selección de métricas y explicabilidad con SHAP.
- **Experiment Tracking y MLflow**: `references/experiment_tracking_and_mlflow.md` — Registro canónico de runs, tracking de hiperparámetros, métricas por step, logging de artefactos visuales, firma de modelo e integración con MLflow Model Registry (`champion` / `challenger`).
- **Empaquetado y Servido**: `references/model_packaging_and_serving.md` — Exportación de alto rendimiento con ONNX (`skl2onnx`, `torch.onnx`), servicio de baja latencia con FastAPI y eventos `lifespan`, batch inference por bloques y auditoría de drift (PSI).

---

## Workflow del Científico de Datos (6 Fases)

```
1. Entendimiento ➔ 2. EDA Híbrido ➔ 3. Inferencia ➔ 4. Modelado ML/DL ➔ 5. Tracking MLflow ➔ 6. Servido API
```

### Fase 1: Entendimiento del Problema y Contrato de Datos
1. Definir el objetivo de negocio, la variable objetivo y la función de pérdida alineada al impacto económico.
2. Formular hipótesis de partida y acuerdos de nivel de servicio (SLA de latencia en inferencia).

### Fase 2: EDA Híbrido y Perfilamiento
1. Implementar funciones en `src/features/` para calcular distribuciones, cardinalidad y varianza.
2. Auditar valores faltantes y clasificarlos (MCAR, MAR, MNAR).
3. Detectar anomalías univariadas y multivariadas.
4. Generar companion notebook con visualizaciones ejecutivas y reporte en Markdown.

### Fase 3: Inferencia Estadística y Pruebas de Hipótesis
1. Comprobar supuestos distribucionales de normalidad y homocedasticidad.
2. Ejecutar la prueba paramétrica o no paramétrica correspondiente según el árbol de decisión.
3. Calcular e interpretar el tamaño del efecto (Cohen's $d$, Odds Ratio).
4. Si corresponde, ajustar regresiones OLS/GLM con errores estándar robustos en Statsmodels para aislar efectos causales.

### Fase 4: Modelado Predictivo (ML Tabular y/o Deep Learning)
1. Dividir el dataset preservando la estructura temporal o agrupada antes de cualquier transformación.
2. Construir el preprocesamiento dentro de un `Pipeline` o `ColumnTransformer`.
3. Entrenar y comparar modelos de referencia (baseline) contra algoritmos ensemble (LightGBM/XGBoost) o redes neuronales en PyTorch.
4. Evaluar con métricas rigurosas (PR-AUC, MCC, RMSE, Brier Score).
5. Generar gráficos de explicabilidad global y local con SHAP.

### Fase 5: Experiment Tracking y Registro con MLflow
1. Loguear hiperparámetros, métricas de validación/test y gráficos en el servidor de MLflow.
2. Inferir y adjuntar la firma del modelo (`infer_signature`).
3. Registrar el modelo candidato en el Model Registry y etiquetarlo como `challenger`.

### Fase 6: Empaquetado y Servido de Inferencia (FastAPI & ONNX)
1. Exportar el modelo optimizado a ONNX o serializar con Joblib/TorchScript.
2. Implementar endpoint `/predict` y `/health` en FastAPI con schemas Pydantic v2.
3. Crear script de scoring batch para inferencia masiva si se requiere.
4. Establecer monitor de Data Drift con Population Stability Index (PSI).

---

## Entregables Obligatorios por Proyecto

1. **Módulos de Código en `src/`**: Funciones desacopladas y tipadas de preprocesamiento, inferencia y modelado.
2. **Companion Notebook**: Notebook interactivo en `notebooks/` con gráficos y conclusiones de negocio.
3. **Reporte Estadístico**: Documento en Markdown resumiendo pruebas de hipótesis, $p$-valores, tamaños de efecto e intervalos de confianza.
4. **Run de MLflow**: Identificador del run con parámetros, métricas, artefactos (SHAP, matrices de confusión) y modelo registrado.
5. **Servicio o Script de Inferencia**: Código de FastAPI (`app.py`) con schemas de entrada/salida o script de batch scoring.

---

## Checklist de Aprobación de Data Science

- [ ] Todo el preprocesamiento y escalado vive dentro de un `Pipeline` hermético sin data leakage.
- [ ] La partición de datos respetó la dimensión temporal o agrupamiento por entidad.
- [ ] Se validaron los supuestos de normalidad y varianza antes de aplicar pruebas de hipótesis.
- [ ] Se reportó el tamaño del efecto (Cohen's $d$, etc.) y no solo el $p$-valor.
- [ ] No se evaluaron clases desbalanceadas utilizando Accuracy (se utilizó PR-AUC / MCC).
- [ ] Se generaron explicaciones locales y globales con SHAP o Permutation Importance.
- [ ] El run de MLflow incluye parámetros, métricas, artefactos visuales y firma de modelo (`signature`).
- [ ] La API de inferencia en FastAPI valida estrictamente los payloads mediante Pydantic v2.
- [ ] La carga del modelo en memoria se realiza en el arranque (`lifespan`) y no en cada request.
- [ ] Se incluye mecanismo de detección de drift poblacional (PSI).
