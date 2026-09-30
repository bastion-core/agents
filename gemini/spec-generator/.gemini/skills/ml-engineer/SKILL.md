---
name: ml-engineer
description: "Estándares de ML Engineering y MLOps: promoción en Model Registry, CI/CD para modelos, monitoreo continuo de drift (PSI), pipelines de reentrenamiento y feature stores."
---

# ML Engineer & MLOps Skill (Registry Promotion, CI/CD, Drift, Retraining & Feature Store)

Este skill define los estándares de ingeniería de machine learning en producción (**MLOps**). Establece la frontera clara entre la experimentación científica y la operación de modelos a escala: **los científicos de datos experimentan; los ingenieros de ML operan y mantienen los modelos en producción**.

---

## División de Responsabilidades (Data Scientist vs ML Engineer)

| Rol / Capacidad | Propiedad (Ownership) | Entregables Clave |
|---|---|---|
| **Data Scientist** | **Experimentación & Prototipado** | EDA híbrido, pruebas de hipótesis, ingeniería de features preliminar, entrenamiento de modelos candidatos, registro de corridas y artefactos en MLflow. |
| **ML Engineer / MLOps** | **Producción & Operaciones de ML** | Promoción en Model Registry (`champion`/`challenger`), CI/CD de modelos (gates de performance), monitoreo de drift (PSI/Wasserstein), pipelines de reentrenamiento y feature store (Feast/Hopsworks). |

---

## Capacidades Principales

1. **Promoción y Gobernanza en Model Registry**:
   - Transición automatizada o auditada de modelos entre estados y alias (`challenger` $\to$ `champion` $\to$ `archived`).
   - Evaluación contra suites de validación antes de reemplazo del baseline en producción (regresión de métricas no permitida).
2. **CI/CD para Machine Learning (Continuous Integration & Delivery)**:
   - Pruebas automatizadas de comportamiento de modelo: pruebas de invarianza, direccionales (Morphic tests) y paridad de datos.
   - Contenedorización reproducible con Docker y serialización optimizada (ONNX Runtime, Triton Inference Server).
   - Estrategias de despliegue seguro: Shadow Deployments (Dark traffic) y Canary Releases.
3. **Monitoreo Continuo de Drift y Salud de Modelos**:
   - Cálculo periódico de Data Drift sobre variables predictoras mediante el Population Stability Index (PSI) y distancia Wasserstein.
   - Monitoreo de Concept Drift (degradación de métricas de negocio o relación $P(Y|X)$).
   - Generación de alertas automáticas (Slack/PagerDuty) ante desvíos críticos.
4. **Pipelines de Reentrenamiento Automatizado**:
   - Orquestación de reentrenamiento continuo basado en tiempo (cron diario/semanal) o disparado por alertas de drift.
   - Cierre del ciclo con validación automatizada contra el baseline actual.
5. **Feature Store y Consistencia Train-Serve**:
   - Definición de entidades y vistas de features en Feature Store (ej: Feast).
   - Garantía de consistencia temporal (Point-in-Time Correctness) para evitar data leakage histórico y proveer baja latencia online (Redis/Bigtable).

---

## Recursos de Referencia Especializados

Consultar los módulos en `references/`:

- **Model Registry & Promoción**: `references/model_registry_and_promotion.md` — Ciclo de vida en MLflow Model Registry, gobernanza de firmas y tags.
- **CI/CD para Modelos**: `references/ci_cd_for_models.md` — Pruebas unitarias de modelos, empaquetado Docker y canary releases.
- **Monitoreo de Drift y Alertas**: `references/drift_monitoring_and_alerting.md` — Métricas de drift (PSI, KS, Wasserstein), cálculo por ventana y alertas.
- **Reentrenamiento y Feature Store**: `references/retraining_pipelines_and_feature_store.md` — Orquestación de reentrenamiento y arquitectura Feature Store.
- **Handoff Scientist vs MLOps**: `references/scientist_vs_mlops_handoff.md` — Contrato formal de entrega entre Data Science y MLOps.

---

## Checklist de Producción MLOps

Antes de autorizar el paso a producción de un modelo, verificar:

- [ ] El modelo tiene firma explícita (`infer_signature`) con tipos tipados estrictamente.
- [ ] La promoción a `champion` está respaldada por una evaluación cuantitativa superior al baseline actual.
- [ ] La pipeline de inferencia valida esquemas de entrada mediante Pydantic v2.
- [ ] El monitoreo de drift (PSI) está configurado con umbrales de alerta ($PSI \ge 0.25$).
- [ ] Las features se extraen con consistencia temporal (Point-in-Time) sin data leakage.
- [ ] Existe un pipeline automatizado o script reproducible para reentrenamiento ante drift.
- [ ] Se probó la latencia P95/P99 del endpoint contra los SLAs operativos.
