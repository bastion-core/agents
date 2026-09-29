# MLflow Model Registry: Gobernanza, Estados y Promoción Canónica

Este documento define las políticas operativas para gobernar el ciclo de vida de los modelos registrados en MLflow y ejecutar transiciones de promoción de forma controlada y reproducible.

---

## 1. Ciclo de Vida y Alias en Model Registry

A partir de MLflow 2.x, se utilizan **Model Aliases** y **Tags** en lugar de etapas rígidas (`Stages`):

| Alias / Etiqueta | Significado Operativo | Criterio de Asignación |
|---|---|---|
| `@champion` | Modelo oficial activo respondiendo tráfico de producción | Superó al champion previo en el test set ciego y pasó el pipeline de CI/CD. |
| `@challenger` | Modelo candidato evaluado en paralelo (shadow deployment) | Cumple criterios mínimos de performance y firma tipada. |
| `@staging` | Modelo desplegado en ambiente de integración/QA | Valida latencia y contratos de API con servicios consumidores. |
| `@archived` | Modelo histórico retirado | Deprecado tras promoción de un nuevo champion. |

---

## 2. Script de Promoción Automatizada con Gates de Calidad

```python
"""Script de promoción de modelos con evaluación de gates."""

from mlflow import MlflowClient


def promote_model_to_champion(
    model_name: str,
    candidate_version: str,
    metric_name: str = "test_pr_auc",
    min_improvement_pct: float = 0.01,
) -> bool:
    client = MlflowClient()

    # 1. Obtener la versión del champion actual
    try:
        champion = client.get_model_version_by_alias(model_name, "champion")
        champion_run = client.get_run(champion.run_id)
        current_metric = champion_run.data.metrics.get(metric_name, 0.0)
    except Exception:
        # Primer modelo en el registry
        client.set_registered_model_alias(model_name, "champion", candidate_version)
        print(f"Modelo v{candidate_version} promovido a @champion inicial.")
        return True

    # 2. Evaluar candidato
    candidate_run = client.get_run(
        client.get_model_version(model_name, candidate_version).run_id
    )
    candidate_metric = candidate_run.data.metrics.get(metric_name, 0.0)

    # 3. Gate de rendimiento
    threshold = current_metric * (1.0 + min_improvement_pct)
    if candidate_metric >= threshold:
        # Asignar alias champion al nuevo modelo
        client.set_registered_model_alias(model_name, "champion", candidate_version)
        client.set_model_version_tag(
            model_name, candidate_version, "status", "PROMOTED_CHAMPION"
        )
        print(
            f"Éxito: v{candidate_version} ({candidate_metric:.4f}) superó "
            f"a v{champion.version} ({current_metric:.4f}). Promovido a @champion."
        )
        return True
    else:
        client.set_registered_model_alias(model_name, "challenger", candidate_version)
        print(
            f"Rechazado: v{candidate_version} ({candidate_metric:.4f}) no superó "
            f"el umbral ({threshold:.4f}). Asignado como @challenger."
        )
        return False
```
