---
name: qa-airflow-dags-py
description: Estándares de testing para proyectos sobre el scaffold airflow-dags-scaffold. Exige pruebas unitarias para todo el código en scripts/ (Pipeline framework, Steps, queries, utils, config) y pruebas de integración para todo el código en dags/ (callables internos del DAG y bootstrap). Define el patrón de mirror del árbol de fuentes, naming AAA, mocking del DatabaseManager y cobertura mínima.
model: sonnet
color: blue
---
# QA Airflow DAGs Skill

Estándares y procedimientos para asegurar la calidad en proyectos construidos sobre el scaffold **`airflow-dags-scaffold`**. Define una arquitectura de pruebas rigurosa con **dos categorías obligatorias**:

| Categoría | Ámbito | Naturaleza |
|---|---|---|
| **Pruebas Unitarias** | Todo el código bajo `scripts/python/pipelines/` (Pipeline framework, Steps, queries, utils, config, migrate runner) | Aisladas: sin Airflow, sin DB real (mocks o SQLite in-memory). |
| **Pruebas de Integración** | Todo el código bajo `dags/` (callables internos del DAG, helpers, bootstrap, callbacks) | Ejercitan los callables que Airflow invocará en runtime, con `xcom_pull` y `context` mockeados. Skipeadas con `pytest.importorskip("airflow")` si Airflow no está instalado. |

> **Regla de oro**: cada archivo `.py` bajo `scripts/python/pipelines/` o `dags/` debe tener su directorio espejo bajo `tests/` con al menos un test por función/método público. La cobertura es exigida sobre ambos paquetes (`--cov=pipelines --cov=dags`).

## Tecnologías de Testing

- **pytest** + **pytest-cov**: framework principal y cobertura. Banner global `GLOBAL COVERAGE: XX.XX%` impreso al final por el `pytest_terminal_summary` hook en `tests/conftest.py`.
- **Apache Airflow**: las dependencias están disponibles en el entorno; tests de `dags/` usan `pytest.importorskip("airflow")` para tolerar entornos sin Airflow.
- **unittest.mock / pytest-mock**: aislamiento de Steps, queries, servicios externos y contexto de Airflow.
- **SQLite in-memory**: tests de queries y migraciones que requieren DB real sin levantar Postgres.
- **pandas**: comparaciones de DataFrames (`pd.testing.assert_frame_equal`).
- **sqlglot** (opcional): parseo y validación sintáctica de archivos `sql/`.

## Arquitectura de Pruebas: Mirror del Árbol de Fuentes

**Cada archivo de fuente tiene un directorio espejo bajo `tests/`**. Adentro, **un test file por función/método/clase pública**. No hay carpetas intermedias por "capa" — la capa está implícita en el path del módulo (`extractors/`, `transformations/`, `loaders/`, `queries/`, `utils/`, etc.).

### Mapping canónico

| Archivo de fuente | Directorio de tests | Test file |
|---|---|---|
| `dags/_bootstrap.py` | `tests/dags/bootstrap/` | `test_setup_python_path_from_bootstrap.py`, `test_default_on_failure_callback_from_bootstrap.py` |
| `dags/<dag_id>.py` | `tests/dags/<dag_id>/` | `test_<fn>_from_<dag_id>.py` (uno por función interna del DAG) |
| `scripts/python/pipelines/core/step.py` | `tests/scripts/python/pipelines/core/step/` | `test_step_from_step.py`, `test_extractor_from_step.py`, `test_transformer_from_step.py`, `test_loader_from_step.py`, `test_as_step_from_step.py` |
| `scripts/python/pipelines/core/pipeline.py` | `tests/scripts/python/pipelines/core/pipeline/` | `test_pipeline_from_pipeline.py`, `test_run_from_pipeline.py` |
| `scripts/python/pipelines/core/context.py` | `tests/scripts/python/pipelines/core/context/` | `test_step_context_from_context.py`, `test_set_artifact_from_context.py`, `test_get_artifact_from_context.py`, `test_record_metric_from_context.py` |
| `scripts/python/pipelines/extractors/sql.py` | `tests/scripts/python/pipelines/extractors/sql/` | `test_execute_from_sql.py`, `test_init_from_sql.py` |
| `scripts/python/pipelines/extractors/bigquery.py` | `tests/scripts/python/pipelines/extractors/bigquery/` | `test_execute_from_bigquery.py`, `test_init_from_bigquery.py` |
| `scripts/python/pipelines/extractors/__init__.py` | `tests/scripts/python/pipelines/extractors/init/` | `test_public_api_from_init.py` (exports del paquete) |
| `scripts/python/pipelines/loaders/postgres.py` | `tests/scripts/python/pipelines/loaders/postgres/` | `test_execute_from_postgres.py`, `test_init_from_postgres.py` |
| `scripts/python/pipelines/queries/<tabla>.py` | `tests/scripts/python/pipelines/queries/<tabla>/` | `test_<fn>_from_<tabla>.py` (uno por función pública) |
| `scripts/python/pipelines/utils/migrate.py` | `tests/scripts/python/pipelines/utils/migrate/` | `test_apply_migrations_from_migrate.py`, `test_checksum_from_migrate.py`, `test_discover_migrations_from_migrate.py`, `test_migration_drift_error_from_migrate.py`, etc. |
| `scripts/python/pipelines/utils/db/database_manager.py` | `tests/scripts/python/pipelines/utils/db/database_manager/` | `test_init_from_database_manager.py`, `test_singleton_from_database_manager.py`, `test_configure_engine_from_database_manager.py`, etc. |
| `scripts/python/pipelines/config/settings.py` | `tests/scripts/python/pipelines/config/settings/` | `test_settings_from_settings.py` |

### Reglas del mirror

1. **Conserva el path completo** del módulo: `scripts/python/pipelines/foo/bar.py` → `tests/scripts/python/pipelines/foo/bar/`.
2. **Strip de underscore inicial** en el nombre del directorio del archivo: `_bootstrap.py` → `tests/dags/bootstrap/` (no `tests/dags/_bootstrap/`). El segmento `_from_bootstrap` en los test files también va sin underscore.
3. **Una clase de test por archivo**: `Test{FunctionOrClass}From{SourceFile}`.
4. **`__init__.py` vacío** en cada nivel de `tests/` para que pytest descubra los paquetes.

## 1. Pruebas de Integración (código bajo `dags/`)

**Ámbito**: cualquier archivo Python bajo `dags/` — incluyendo el bootstrap (`_bootstrap.py`), DAG files (`<dag_id>.py`), helpers internos, callbacks, y funciones invocadas vía `PythonOperator` o `@task`.

**Naturaleza**: integración porque ejercitan los callables que Airflow invocará en runtime. Mockean el contexto de Airflow (`ti`, `xcom_pull`, `dag_run`, `params`) y validan el comportamiento end-to-end de cada función dentro del DAG.

**Skip safety**: usar `pytest.importorskip("airflow")` al inicio para que el test set sea ejecutable también en entornos sin Airflow instalado.

### Ejemplo: testing de un callable de DAG

```python
# tests/dags/example_python_etl/test_clean_from_example_python_etl.py
"""Tests for ``dags.example_python_etl.clean``."""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest

pytest.importorskip("airflow")

from dags import example_python_etl  # noqa: E402


class TestCleanFromExamplePythonEtl:
    def test_should_remove_duplicates_and_clean_nulls_when_called(self) -> None:
        # Arrange
        raw_records = [
            {"id": 1, "name": "Product A", "revenue": 1500.0},
            {"id": 2, "name": "Product B", "revenue": 2300.0},
            {"id": 2, "name": "Product B", "revenue": 2300.0},
            {"id": 4, "name": None, "revenue": None},
        ]
        ti_mock = MagicMock()
        ti_mock.xcom_pull.return_value = json.dumps(raw_records)
        context = {"ti": ti_mock}

        # Act
        result = example_python_etl.clean(**context)

        # Assert
        cleaned = json.loads(result)
        assert len(cleaned) == 2

    def test_should_pull_xcom_from_extract_task_when_called(self) -> None:
        # Arrange
        ti_mock = MagicMock()
        ti_mock.xcom_pull.return_value = json.dumps([{"id": 1, "name": "A", "revenue": 100.0}])
        context = {"ti": ti_mock}

        # Act
        example_python_etl.clean(**context)

        # Assert
        ti_mock.xcom_pull.assert_called_once_with(task_ids="extract")
```

### Ejemplo: testing de bootstrap

```python
# tests/dags/bootstrap/test_setup_python_path_from_bootstrap.py
"""Tests for ``dags._bootstrap.setup_python_path``."""

import sys
from pathlib import Path

import pytest

from dags import _bootstrap


class TestSetupPythonPathFromBootstrap:
    @pytest.fixture
    def fake_repo(self, tmp_path: Path) -> Path:
        repo_root = tmp_path / "repo"
        (repo_root / "scripts" / "python").mkdir(parents=True)
        (repo_root / "dags").mkdir(parents=True)
        (repo_root / "dags" / "example_dag.py").write_text("# fake dag\n")
        return repo_root

    @pytest.fixture
    def isolated_sys_path(self, monkeypatch: pytest.MonkeyPatch) -> list[str]:
        snapshot = list(sys.path)
        monkeypatch.setattr(sys, "path", snapshot)
        return snapshot

    def test_should_insert_scripts_python_in_sys_path_when_repo_root_resolved(
        self, fake_repo: Path, isolated_sys_path: list[str], monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Arrange
        target = fake_repo / "scripts" / "python"
        dag_file = fake_repo / "dags" / "example_dag.py"
        monkeypatch.setattr(_bootstrap, "__file__", str(dag_file))
        monkeypatch.setenv("AIRFLOW_HOME", str(fake_repo / "no_airflow_home"))

        # Act
        _bootstrap.setup_python_path()

        # Assert
        assert sys.path[0] == str(target)

    def test_should_be_idempotent_when_called_twice(
        self, fake_repo: Path, isolated_sys_path: list[str], monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Arrange
        target = fake_repo / "scripts" / "python"
        dag_file = fake_repo / "dags" / "example_dag.py"
        monkeypatch.setattr(_bootstrap, "__file__", str(dag_file))
        monkeypatch.setenv("AIRFLOW_HOME", str(fake_repo / "no_airflow_home"))

        # Act
        _bootstrap.setup_python_path()
        _bootstrap.setup_python_path()

        # Assert
        occurrences = [p for p in sys.path if p == str(target)]
        assert len(occurrences) == 1
```

### Test de DagBag (recomendado, no obligatorio)

Para DAGs nuevos, agregar opcionalmente un test de DagBag que valide que el archivo no tenga `import_errors` y cumpla las reglas CI obligatorias del scaffold:

```python
# tests/dags/<dag_id>/test_dag_bag_from_<dag_id>.py
import re
import pytest

pytest.importorskip("airflow")

from airflow.models import DagBag


class TestDagBagFromMyDag:
    def test_should_have_no_import_errors_when_loaded(self):
        dag_bag = DagBag(dag_folder="dags/", include_examples=False)
        assert dag_bag.import_errors == {}

    def test_should_comply_with_ci_rules_when_loaded(self):
        dag_bag = DagBag(dag_folder="dags/", include_examples=False)
        dag = dag_bag.get_dag("my_dag_id")

        assert dag is not None
        assert re.match(r"^[a-z][a-z0-9_]*$", dag.dag_id)
        assert dag.catchup is False
        assert dag.tags
        assert dag.default_args["owner"] != "airflow"
        assert dag.description
```

## 2. Pruebas Unitarias (código bajo `scripts/python/pipelines/`)

**Ámbito**: todo el código bajo `scripts/python/pipelines/` — incluyendo el framework `core/` (Step, Pipeline, StepContext, exceptions, logging_utils), Reusable Steps (`extractors/`, `loaders/`), Steps custom de proyectos (`transformations/`), queries (`queries/`), utilidades (`utils/db/`, `utils/logger/`, `utils/migrate.py`, `utils/s3_client.py`), config (`config/settings.py`), y pipeline builders (`examples/`, `<dominio>/`).

**Naturaleza**: aisladas. **Sin Airflow, sin Postgres real, sin BigQuery real, sin S3 real**. Mockear todo lo externo.

### Sub-categoría 2.1: Tests de Steps

Los Steps puros (Transformers, Loaders mockeables, Extractors con `db_manager` mockeado) se testean instanciando la clase, preparando un `StepContext` con `set_artifact(...)` para los inputs upstream, y aserteando el output:

```python
# tests/scripts/python/pipelines/transformations/drivers_transformer/test_execute_from_drivers_transformer.py
import pandas as pd

from pipelines.core import StepContext
from pipelines.transformations.drivers_transformer import DriversTransformer


class TestExecuteFromDriversTransformer:
    def test_should_titlecase_full_name_when_input_is_lowercase(self):
        # Arrange
        ctx = StepContext()
        ctx.set_artifact("extract_drivers", pd.DataFrame([{"id": 1, "full_name": " juan perez "}]))
        transformer = DriversTransformer()

        # Act
        out = transformer.execute(ctx)

        # Assert
        assert out.iloc[0]["full_name"] == "Juan Perez"
```

Para Steps que tocan DB, mockear `db_manager` directamente sobre el módulo:

```python
# tests/scripts/python/pipelines/extractors/sql/test_execute_from_sql.py
from unittest.mock import MagicMock, patch

from pipelines.core import StepContext
from pipelines.extractors import sql as sql_module
from pipelines.extractors.sql import SqlExtractor


class TestExecuteFromSql:
    def test_should_use_db_manager_engine_for_configured_db_name(self):
        # Arrange
        engine = MagicMock(name="engine")
        conn = MagicMock(name="conn")
        engine.connect.return_value.__enter__.return_value = conn

        with (
            patch.object(sql_module, "db_manager") as db_manager_mock,
            patch.object(sql_module.pd, "read_sql") as read_sql_mock,
        ):
            db_manager_mock.get_engine.return_value = engine
            read_sql_mock.return_value = MagicMock(name="dataframe")

            extractor = SqlExtractor(name="extract", query="SELECT 1", db_name="org_dwh")

            # Act
            extractor.execute(StepContext())

        # Assert
        db_manager_mock.get_engine.assert_called_once_with("org_dwh")
```

Cubrir siempre con tests separados:
- `test_init_from_<file>.py` — validación de parámetros del constructor.
- `test_execute_from_<file>.py` — happy path + edge cases del método principal.

### Sub-categoría 2.2: Tests del Pipeline framework (core)

```python
# tests/scripts/python/pipelines/core/pipeline/test_run_from_pipeline.py
from pipelines.core import Pipeline, Step, StepContext


class FakeExtract(Step):
    name = "extract"

    def execute(self, ctx):
        return [1, 2, 3]


class FakeLoad(Step):
    name = "load"
    inputs = ["extract"]

    def execute(self, ctx):
        return len(self.get_input(ctx, "extract"))


class TestRunFromPipeline:
    def test_should_propagate_artifacts_through_steps_when_run(self):
        # Arrange
        pipeline = Pipeline(name="test", steps=[FakeExtract(), FakeLoad()])

        # Act
        result = pipeline.run(StepContext())

        # Assert
        assert result.artifacts["extract"] == [1, 2, 3]
        assert result.metrics["load"] == 3
```

### Sub-categoría 2.3: Tests de Queries Module

Las funciones planas en `pipelines/queries/<tabla>.py` se testean con `Session` mockeado (preferido) o SQLite in-memory:

```python
# tests/scripts/python/pipelines/queries/sample_lookup/test_get_category_thresholds_from_sample_lookup.py
from decimal import Decimal
from unittest.mock import MagicMock

from pipelines.queries.sample_lookup import get_category_thresholds


def _make_session(rows):
    session = MagicMock()
    result = MagicMock()
    result.fetchall.return_value = rows
    session.execute.return_value = result
    return session


class TestGetCategoryThresholdsFromSampleLookup:
    def test_should_return_empty_list_when_no_rows_found(self):
        # Arrange
        session = _make_session([])

        # Act
        result = get_category_thresholds(session)

        # Assert
        assert result == []

    def test_should_convert_threshold_to_float_and_return_label_unchanged(self):
        # Arrange
        session = _make_session([(Decimal("100.50"), "premium"), (10, "basic")])

        # Act
        result = get_category_thresholds(session)

        # Assert
        assert result == [(100.50, "premium"), (10.0, "basic")]
```

Alternativamente, para tests más profundos, SQLite in-memory:

```python
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker


def test_should_return_mapping_when_active_drivers_exist(self):
    # Arrange
    engine = create_engine("sqlite:///:memory:")
    Session = sessionmaker(bind=engine)
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE dim_driver (uber_driver_id TEXT, driver_sk INT, is_current INT)"))
        conn.execute(text("INSERT INTO dim_driver VALUES ('ABC-123', 42, 1)"))
    session = Session()

    # Act
    result = dim_driver.get_uber_id_map(session)

    # Assert
    assert result == {"abc-123": 42}
```

### Sub-categoría 2.4: Tests del runner de migraciones (`utils/migrate.py`)

Cubrir cada función pública (`apply_migrations`, `discover_migrations`, `checksum`, `ensure_tracking_table`, `load_applied`, etc.) en su propio test file. Usar SQLite in-memory para validar idempotencia, drift detection y orden de aplicación raw → stg → core.

### Sub-categoría 2.5: Tests del DatabaseManager y conexiones

`database_manager`, `db_connect`, `postgresql_connect`, `session_manager` — todos requieren tests por método público. Usar el fixture `mocked_engine_factories` del scaffold para evitar conexiones reales:

```python
# Disponible en tests/conftest.py
@pytest.fixture
def mocked_engine_factories():
    with (
        patch.object(dm_module, "create_engine") as create_engine_mock,
        patch.object(dm_module, "sessionmaker") as sessionmaker_mock,
    ):
        create_engine_mock.side_effect = lambda *args, **kwargs: MagicMock(name=f"engine[{args[0]}]")
        sessionmaker_mock.side_effect = lambda **kwargs: MagicMock(name="session_factory")
        yield create_engine_mock, sessionmaker_mock
```

### Sub-categoría 2.6: Tests del settings (Pydantic)

```python
# tests/scripts/python/pipelines/config/settings/test_settings_from_settings.py
from pipelines.config.settings import Settings


class TestSettingsFromSettings:
    def test_should_load_dwh_uris_from_environment_when_initialized(self, monkeypatch):
        # Arrange
        monkeypatch.setenv("AIRFLOW_CONN_ORG_DWH_RAW", "postgresql://raw")
        monkeypatch.setenv("AIRFLOW_CONN_ORG_DWH_STG", "postgresql://stg")
        monkeypatch.setenv("AIRFLOW_CONN_ORG_DWH_CORE", "postgresql://core")

        # Act
        settings = Settings()

        # Assert
        assert settings.org_dwh_raw_url == "postgresql://raw"
```

### Sub-categoría 2.7: Tests de migraciones SQL (`sql/`)

Para archivos nuevos en `sql/raw/`, `sql/stg/`, `sql/core/`, validar:
- **Idempotencia**: aplicar dos veces el mismo archivo no debe fallar.
- **Sintaxis**: parsear con `sqlglot.parse(open(path).read(), read='postgres')`.
- **Header obligatorio**: assertear que las primeras líneas matcheen `-- Owner: ...` y `-- Purpose: ...`.

```python
# tests/sql/test_migrations_headers.py
import re
from pathlib import Path

import pytest


@pytest.mark.parametrize("sql_file", Path("sql").rglob("*.sql"))
class TestSqlMigrations:
    def test_should_have_owner_and_purpose_header_when_parsed(self, sql_file):
        content = sql_file.read_text()
        assert re.search(r"^-- Owner:\s+\S+", content, re.MULTILINE)
        assert re.search(r"^-- Purpose:\s+\S+", content, re.MULTILINE)
```

## Bootstrap del entorno de tests (`tests/conftest.py`)

El scaffold ya provee fixtures clave en `tests/conftest.py`:

```python
import pytest
from unittest.mock import MagicMock, patch

from pipelines.utils.db import database_manager as dm_module
from pipelines.utils.db.database_manager import DatabaseManager, db_manager


def _reset_db_manager_state():
    db_manager._engines = {}
    db_manager._session_factories = {}
    db_manager._default_db_name = None


@pytest.fixture(autouse=True)
def reset_database_manager_singleton():
    """Garantiza aislamiento del singleton entre tests."""
    DatabaseManager._instance = None
    _reset_db_manager_state()
    yield
    DatabaseManager._instance = None
    _reset_db_manager_state()


@pytest.fixture
def mocked_engine_factories():
    """Mockea create_engine y sessionmaker para evitar conexiones reales."""
    with (
        patch.object(dm_module, "create_engine") as create_engine_mock,
        patch.object(dm_module, "sessionmaker") as sessionmaker_mock,
    ):
        create_engine_mock.side_effect = lambda *args, **kwargs: MagicMock(name=f"engine[{args[0]}]")
        sessionmaker_mock.side_effect = lambda **kwargs: MagicMock(name="session_factory")
        yield create_engine_mock, sessionmaker_mock
```

Adicionalmente, el `conftest.py` mantiene el path de `scripts/python` en `sys.path` y publica el banner global de cobertura via `pytest_terminal_summary`.

## Configuración de pytest y cobertura

`pyproject.toml` del scaffold:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
addopts = "--cov=pipelines --cov=dags --cov-report=term --cov-report=html:coverage/html"
```

**La cobertura cubre AMBOS paquetes**: `pipelines` (código de scripts/python/) y `dags` (código de DAGs). El banner `GLOBAL COVERAGE: XX.XX%` se imprime al final de la corrida.

Ejecución:

```bash
# Con coverage (default por addopts)
pytest tests/ -v

# Lint + format
ruff check .
ruff format --check .

# Wrapper del scaffold
./tests/run_tests.sh python   # corre pytest
./tests/run_tests.sh lint     # corre ruff check + format
```

## Patrón de Diseño: AAA (Arrange-Act-Assert)

Todos los tests deben seguir obligatoriamente la estructura **AAA**:

1. **Arrange**: configurar el entorno, instanciar Steps, preparar `StepContext` con artefactos upstream, configurar Mocks (incluyendo `xcom_pull` para tests de `dags/`).
2. **Act**: ejecutar la función o método que se está probando.
3. **Assert**: verificar el resultado y las interacciones con los mocks.

```python
def test_should_calculate_sum_when_valid_input(self):
    # Arrange
    data = [10, 20, 30]
    expected_result = 60
    calculator = MetricsCalculator()

    # Act
    result = calculator.sum_values(data)

    # Assert
    assert result == expected_result
```

## Reglas de Nomenclatura

### Archivos de test
`test_{function_or_method_or_class}_from_{source_file_basename}.py`

- `{source_file_basename}` es el nombre del archivo de fuente sin `.py` y sin underscore inicial (`_bootstrap.py` → `bootstrap`).
- Si el archivo de fuente define varias funciones públicas, **un test file por función** dentro del directorio espejo.

Ejemplos válidos:
- `test_setup_python_path_from_bootstrap.py` (función `setup_python_path` en `_bootstrap.py`)
- `test_execute_from_sql.py` (método `execute` en `extractors/sql.py`)
- `test_get_category_thresholds_from_sample_lookup.py` (función en `queries/sample_lookup.py`)
- `test_apply_migrations_from_migrate.py` (función en `utils/migrate.py`)
- `test_clean_from_example_python_etl.py` (callable en `dags/example_python_etl.py`)

### Clase de test
`Test{FunctionOrClassPascalCase}From{SourceFilePascalCase}`

Ejemplos:
- `TestExecuteFromSql`
- `TestSetupPythonPathFromBootstrap`
- `TestCleanFromExamplePythonEtl`
- `TestGetCategoryThresholdsFromSampleLookup`

> El **"From"** se refiere al **archivo de fuente**, no a la clase. Para archivos que definen una sola clase con un solo método público, suele coincidir; para archivos con múltiples funciones planas (queries, utils), el "From" sigue siendo el archivo.

### Métodos de test
`test_should_{expected_behavior}_when_{condition}`

Ejemplos:
- `test_should_remove_duplicates_and_clean_nulls_when_called`
- `test_should_use_db_manager_engine_for_configured_db_name`
- `test_should_be_idempotent_when_called_twice`

## Requerimientos de Calidad

| Área | Mínimo |
|---|---|
| **Aislamiento `scripts/`** | Sin conexiones reales a Postgres / BigQuery / S3 / APIs. Usar `mocked_engine_factories` o SQLite in-memory. |
| **Aislamiento `dags/`** | Mockear `xcom_pull`, `dag_run`, `task_instance`. `pytest.importorskip("airflow")` para tolerar ausencia de Airflow. |
| **Cobertura `pipelines/extractors`, `pipelines/loaders`, `pipelines/transformations`** | ≥ 90% |
| **Cobertura `pipelines/queries`** | ≥ 90% |
| **Cobertura `pipelines/core`, `pipelines/utils/db`, `pipelines/utils/migrate`** | ≥ 90% |
| **Cobertura `dags/`** | ≥ 80% (cada callable interno del DAG con al menos un happy-path test) |
| **Cobertura global** | ≥ 85% (visible en banner `GLOBAL COVERAGE: XX.XX%`) |
| **Estructura de mirror** | Cada `.py` bajo `scripts/python/pipelines/` o `dags/` tiene su directorio espejo bajo `tests/`. |
| **Reglas CI por DAG** | Cuando se incluye DagBag test, debe assertear: `import_errors == {}`, `catchup=False`, `tags` no vacío, owner ≠ `airflow`, description presente, snake_case ID. |
| **`sql/` migrations** | Cada archivo nuevo debe tener test de header `Owner/Purpose`; idempotencia validable via `python -m pipelines.utils.migrate --dry-run`. |

## Validación local antes del PR

```bash
# Lint
ruff check .
ruff format --check .

# Tests + cobertura (la config en pyproject.toml ya incluye --cov)
pytest tests/ -v

# Wrapper del scaffold (equivalente)
./tests/run_tests.sh python
./tests/run_tests.sh lint

# Migraciones SQL (dry-run para validar pendientes)
python -m pipelines.utils.migrate --dry-run

# DAG validation rápida (sin pytest)
python -c "from airflow.models import DagBag; bag = DagBag(dag_folder='dags/', include_examples=False); print(bag.import_errors or 'OK')"
```

## Checklist por tipo de cambio

### PR que agrega un DAG nuevo (archivo en `dags/`)
- [ ] Directorio `tests/dags/<dag_id>/` con `__init__.py`.
- [ ] Un test file por **callable interno** del DAG: `test_<fn>_from_<dag_id>.py`. Cada uno mockea `xcom_pull` / `context` y valida la lógica.
- [ ] (Opcional pero recomendado) `test_dag_bag_from_<dag_id>.py` con DagBag + assertions de reglas CI.
- [ ] Cobertura del DAG ≥ 80%.

### PR que agrega un Step custom en `scripts/python/pipelines/{extractors,transformations,loaders}/`
- [ ] Directorio `tests/scripts/python/pipelines/<misma_ruta>/<file>/` con `__init__.py`.
- [ ] `test_init_from_<file>.py` para el constructor.
- [ ] `test_execute_from_<file>.py` con `StepContext.set_artifact(...)` para los inputs upstream.
- [ ] Mockear `db_manager` o `get_db` si el Step toca DB.
- [ ] Cobertura ≥ 90%.

### PR que agrega una query en `scripts/python/pipelines/queries/<tabla>.py`
- [ ] Directorio `tests/scripts/python/pipelines/queries/<tabla>/`.
- [ ] Un `test_<fn>_from_<tabla>.py` por función pública.
- [ ] Mock de `Session` o SQLite in-memory.
- [ ] Cobertura ≥ 90%.

### PR que agrega una utilidad en `scripts/python/pipelines/utils/`
- [ ] Directorio espejo bajo `tests/scripts/python/pipelines/utils/<sub>/<file>/`.
- [ ] Un test file por función/método público.
- [ ] Para `migrate.py`: cubrir idempotencia, drift detection, orden de aplicación raw→stg→core.
- [ ] Para `db/`: usar `mocked_engine_factories` y `reset_database_manager_singleton`.

### PR que agrega/modifica `sql/<schema>/*.sql`
- [ ] Si es archivo nuevo: header `Owner/Purpose` validado por test parametrizado.
- [ ] Idempotencia validada via `python -m pipelines.utils.migrate --dry-run`.
- [ ] Si modifica un archivo existente: **REQUEST_CHANGES** y pedir un nuevo archivo `NNN_<tabla>_<descripcion>.sql`.

### PR que agrega una conexión a DB
- [ ] Test del campo nuevo en `Settings` (Pydantic).
- [ ] Test del registro en `postgresql_connect.py` (verificar `configure_database` llamado con la URI esperada).
- [ ] Si rompe fixtures existentes, actualizar `conftest.py`.

### PR que agrega `dags/_bootstrap.py` helpers nuevos o modifica los existentes
- [ ] Test en `tests/dags/bootstrap/test_<fn>_from_bootstrap.py`.
- [ ] Cubrir resolución del repo root, fallback a `AIRFLOW_HOME`, idempotencia, casos donde directorios faltan.
