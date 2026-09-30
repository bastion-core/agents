# Statistical Inference & Hypothesis Testing

Este documento establece el marco riguroso para la selección de pruebas de hipótesis, estimación de tamaño del efecto y modelado estadístico explicativo con `scipy.stats` y `statsmodels`.

---

## 1. Árbol de Decisión para Pruebas de Hipótesis

Antes de ejecutar cualquier prueba estadística, **es obligatorio validar los supuestos distribucionales**:
1. **Normalidad**: Prueba de Shapiro-Wilk (`scipy.stats.shapiro`, para $N < 5000$) o D'Agostino-Pearson omnibus (`scipy.stats.normaltest`). Complementar siempre con inspección visual de Q-Q plots.
2. **Homocedasticidad (Igualdad de varianzas)**: Prueba de Levene (`scipy.stats.levene`, centrada en la mediana, robusta a no-normalidad).

```
                            ¿Cuántos grupos a comparar?
                                       │
                 ┌─────────────────────┴─────────────────────┐
             2 Grupos                                    > 2 Grupos
                 │                                           │
       ¿Muestras pareadas?                          ¿Normalidad y Varianza?
        ┌────────┴────────┐                         ┌────────┴────────┐
        Sí                No                       Sí                 No
        │                 │                        │                  │
    ¿Normal?          ¿Normal?                  One-Way           Kruskal-Wallis
   ┌────┴────┐       ┌────┴────┐                 ANOVA             (No paramétrico)
  Sí         No     Sí         No                  │                  │
Paired    Wilcoxon  │      Mann-Whitney         Post-hoc:          Post-hoc:
t-test     signed-  │        U test            Tukey HSD          Dunn + FDR
            rank    │
                    ▼
          ¿Varianzas iguales?
             ┌──────┴──────┐
            Sí             No
             │             │
          Student's     Welch's
           t-test        t-test
                       (Recomendado)
```

---

## 2. Implementación Canónica de Pruebas de Comparación

```python
# src/features/hypothesis_testing.py
from dataclasses import dataclass
import numpy as np
import scipy.stats as stats
from statsmodels.stats.multitest import multipletests

@dataclass
class ComparisonResult:
    test_name: str
    statistic: float
    p_value: float
    effect_size: float
    effect_size_metric: str
    interpretation: str

def compare_two_independent_groups(
    group_a: np.ndarray, group_b: np.ndarray, alpha: float = 0.05
) -> ComparisonResult:
    """Ejecuta la prueba estadística adecuada (paramétrica o no) validando supuestos."""
    # 1. Validación de normalidad
    _, p_norm_a = stats.shapiro(group_a) if len(group_a) < 5000 else stats.normaltest(group_a)
    _, p_norm_b = stats.shapiro(group_b) if len(group_b) < 5000 else stats.normaltest(group_b)
    is_normal = (p_norm_a > 0.05) and (p_norm_b > 0.05)

    # 2. Validación de homocedasticidad
    _, p_homo = stats.levene(group_a, group_b)
    is_homoscedastic = p_homo > 0.05

    if is_normal and is_homoscedastic:
        stat, p_val = stats.ttest_ind(group_a, group_b, equal_var=True)
        test_name = "Student's t-test (Two-sample)"
    elif is_normal and not is_homoscedastic:
        stat, p_val = stats.ttest_ind(group_a, group_b, equal_var=False)
        test_name = "Welch's t-test (Heteroscedastic)"
    else:
        stat, p_val = stats.mannwhitneyu(group_a, group_b, alternative="two-sided")
        test_name = "Mann-Whitney U test (Non-parametric)"

    # 3. Cálculo de Tamaño del Efecto (Cohen's d)
    diff = np.mean(group_a) - np.mean(group_b)
    pooled_std = np.sqrt(
        ((len(group_a) - 1) * np.var(group_a, ddof=1) + (len(group_b) - 1) * np.var(group_b, ddof=1))
        / (len(group_a) + len(group_b) - 2)
    )
    cohens_d = diff / pooled_std if pooled_std > 0 else 0.0

    interpretation = (
        f"Diferencia estadísticamente significativa (p={p_val:.4e} < {alpha}) "
        f"con efecto d={cohens_d:.2f}."
        if p_val < alpha
        else f"No se encontró evidencia de diferencia significativa (p={p_val:.4e} >= {alpha})."
    )

    return ComparisonResult(
        test_name=test_name,
        statistic=stat,
        p_value=p_val,
        effect_size=cohens_d,
        effect_size_metric="Cohen's d",
        interpretation=interpretation,
    )
```

---

## 3. Pruebas para Variables Categóricas (Tablas de Contingencia)

1. **Chi-cuadrado ($\chi^2$) de Independencia**:
   - `scipy.stats.chi2_contingency(contingency_table)`.
   - **Regla estricta de Cochran**: Las frecuencias esperadas en cada celda deben ser $\ge 5$ en al menos el 80% de las celdas, y ninguna celda debe tener frecuencia esperada cero.
2. **Test Exacto de Fisher**:
   - `scipy.stats.fisher_exact(table_2x2)`.
   - Obligatorio para tablas $2 \times 2$ cuando las frecuencias esperadas son menores a 5.

---

## 4. Corrección por Múltiples Comparaciones (FDR & Bonferroni)

Cuando se ejecutan múltiples pruebas simultáneas (ej: A/B testing multi-variante, análisis de subgrupos):
- **Bonferroni**: $\alpha_{ajustado} = \frac{\alpha}{m}$. Altamente conservadora, controla el FWER (Family-Wise Error Rate).
- **Benjamini-Hochberg (FDR)**: Controla la tasa de falsos descubrimientos. Estándar recomendado en ciencia de datos moderna.

```python
# Ejemplo de ajuste Benjamini-Hochberg con statsmodels
reject, pvals_corrected, _, _ = multipletests(p_values_list, alpha=0.05, method="fdr_bh")
```

---

## 5. Modelado Estadístico Explicativo con `statsmodels`

Para cuantificar relaciones causales o controlar por covariables de confusión:

```python
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.outliers_influence import variance_inflation_factor

# 1. Regresión Lineal OLS con fórmulas
model = smf.ols("conversion_rate ~ C(treatment) + age + account_balance", data=df).fit()

# Resumen con coeficientes, errores estándar robustos (HC3 para heterocedasticidad)
robust_model = model.get_robustcov_results(cov_type="HC3")
print(robust_model.summary())

# 2. Diagnóstico de Multicolinealidad (VIF)
def compute_vif(X: pd.DataFrame) -> pd.DataFrame:
    vif_data = pd.DataFrame()
    vif_data["feature"] = X.columns
    vif_data["VIF"] = [variance_inflation_factor(X.values, i) for i in range(len(X.columns))]
    return vif_data.sort_values(by="VIF", ascending=False)
```

**Guardarraíl de Calidad**: Nunca concluir causalidad basada exclusivamente en correlación estadística. Reportar siempre los intervalos de confianza del 95% junto al estimador puntual.
