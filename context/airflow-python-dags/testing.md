# Testing - Airflow DAGs

Resumen del estándar de pruebas. El detalle completo (ejemplos, fixtures, checklists por tipo de cambio) está en la skill `qa-airflow-dags-py`.

## Categorías

| Categoría | Ámbito | Naturaleza |
|---|---|---|
| Unitarias | Todo `scripts/python/pipelines/` (core, Steps, queries, utils, config) | Sin Airflow ni base de datos real: mocks o SQLite in-memory |
| Integración | Todo `dags/` (callables del DAG, `_bootstrap.py`) | `pytest.importorskip("airflow")`, `xcom_pull` y contexto mockeados |

## Estructura Espejo

Cada archivo fuente tiene un directorio espejo bajo `tests/` con un archivo de test por función o método público:

```text
scripts/python/pipelines/transformations/drivers.py
  → tests/scripts/python/pipelines/transformations/drivers/test_execute_from_drivers.py
dags/_bootstrap.py
  → tests/dags/bootstrap/test_setup_python_path_from_bootstrap.py
dags/<dag_id>.py
  → tests/dags/<dag_id>/test_<fn>_from_<dag_id>.py
```

## Nomenclatura

- Archivo: `test_{funcion_o_metodo}_from_{archivo_fuente}.py`.
- Clase: `Test{Funcion}From{ArchivoFuente}`.
- Método: `test_should_{comportamiento}_when_{condicion}`.
- Patrón AAA (Arrange-Act-Assert) en cada test.

## Pruebas de Confiabilidad

Además de la cobertura funcional, los Steps nuevos deben probar:

- **Idempotencia** del Loader: ejecutar dos veces con el mismo input no duplica filas (SQLite in-memory o assert sobre el SQL generado).
- **Fail-Fast** del Transformer: input sin una columna obligatoria lanza excepción.
- **UTC**: los timestamps de salida tienen zona horaria UTC.
- **Ventana determinista**: el Extractor usa `ctx.params["window_start"]` / `["window_end"]` y no la hora actual.

## Cobertura Mínima

- `extractors`, `transformations`, `loaders`, `queries`, `core`, `utils`: ≥ 90%.
- `dags/`: ≥ 80%.
- Global: ≥ 85%.
