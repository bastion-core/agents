# Testing - Airflow DAGs

Resumen del estándar de pruebas. El detalle completo (ejemplos, fixtures, checklists por tipo de cambio) está en la skill `qa-airflow-dags-py`.

## Categorías

| Categoría | Ámbito | Naturaleza |
|---|---|---|
| Unitarias | Todo `scripts/python/pipelines/` (core, Steps, queries, utils, config) | Sin Airflow ni base de datos real: mocks o SQLite in-memory |
| Integración | Todo `dags/` (callables del DAG, `_bootstrap.py`) | `pytest.importorskip("airflow")`, `xcom_pull` y contexto mockeados |
| Integración con Postgres | Loaders, Extractors y runner de migraciones que dependen del motor | Marker `postgres` + fixture `pg_db`: Postgres real del compose o del CI, schema temporal por test |

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

## Tests de Integración contra Postgres

Lo que SQLite no reproduce (`ON CONFLICT` sobre constraints reales, `TIMESTAMPTZ`, `SET LOCAL lock_timeout`) se prueba contra Postgres:

- Archivo en el mismo mirror con sufijo `_integration`: `test_execute_integration_from_postgres.py`.
- `pytestmark = pytest.mark.postgres` y el fixture `pg_db` (`db_name`, `schema`, `engine`), que crea y borra un schema `it_<hex>` por test.
- Corren cuando existe `PIPELINES_TEST_DATABASE_URL`: `make test` la define para el Postgres del compose y el CI levanta un Postgres 15. Sin ella se marcan `skipped`.
- No hardcodear nombres que cada org puede cambiar; leerlos del módulo (p. ej. `_TRACKING_TABLE_PG`).

Detalle y ejemplo completo en la skill `qa-airflow-dags-py` (Sub-categoría 2.9).

## Cobertura Mínima

- `extractors`, `transformations`, `loaders`, `queries`, `core`, `utils`: ≥ 90%.
- `dags/`: ≥ 80%.
- Global: ≥ 85%.
