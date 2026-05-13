---
name: qa-airflow-dags-py
description: Estándares de testing para DAGs de Airflow construidos sobre el scaffold airflow-dags-scaffold (Pipeline framework, Queries Module, migraciones SQL planas). Cubre arquitectura de tests, mocking del DatabaseManager, AAA y nomenclatura.
model: sonnet
color: blue
---
# QA Airflow DAGs Skill

Estándares y procedimientos para asegurar la calidad en proyectos de Apache Airflow construidos sobre el scaffold **`airflow-dags-scaffold`**. Define una arquitectura de pruebas rigurosa para el **Pipeline framework** (Step / Pipeline / StepContext), el **Queries Module**, los **Reusable Steps** y las **migraciones SQL planas** (`sql/`).

## Tecnologías de Testing

- **Apache Airflow**: `DagBag` testing para integridad de orquestación.
- **pytest**: Framework principal de pruebas (configurado en `pyproject.toml`).
- **pytest-cov**: Cobertura. Banner global `GLOBAL COVERAGE: XX.XX%` impreso al final.
- **unittest.mock / pytest-mock**: Aislamiento de Steps y servicios externos.
- **SQLite in-memory**: Para tests de Queries Module sin Postgres.
- **pandas**: Comparaciones de DataFrames (`pd.testing.assert_frame_equal`).

## Arquitectura de Pruebas Obligatoria

### 1. Pruebas de Integración (Integridad del DAG)

Validan que el DAG sea parseable, no tenga ciclos y cumpla las **reglas CI obligatorias** del scaffold (snake_case ID, owner ≠ `airflow`, tags, `catchup=False`, description).

- **Ubicación**: `tests/dags/{folder_dag_name}/test_{dag_id}.py`
- **Patrón**: `DagBag` para verificar `import_errors == {}` y assertear metadatos.

```python
# tests/dags/drivers_sync/test_drivers_sync.py
from airflow.models import DagBag


class TestDriversSyncDag:
    def test_should_have_no_import_errors_when_loaded(self):
        # Arrange
        dag_bag = DagBag(dag_folder="dags/", include_examples=False)

        # Act
        errors = dag_bag.import_errors

        # Assert
        assert errors == {}

    def test_should_have_required_metadata_when_loaded(self):
        # Arrange
        dag_bag = DagBag(dag_folder="dags/", include_examples=False)

        # Act
        dag = dag_bag.get_dag("drivers_sync")

        # Assert
        assert dag is not None
        assert dag.catchup is False
        assert dag.tags
        assert dag.default_args["owner"] != "airflow"
        assert dag.description
```

### 2. Pruebas Unitarias (Lógica por Capas)

Toda la lógica vive **fuera del DAG** (en `scripts/python/pipelines/`) y se testea unitariamente sin Airflow ni DB. Los tests se organizan obligatoriamente siguiendo la estructura de capas del Pipeline framework.

- **Ubicación**: `tests/scripts/python/{folder_dag_name}/{layer}/{file_name}/test_{function_name}_from_{class_name}.py`
- **Capas Definidas**:
  * `extraction` — Lógica de obtención de datos (Steps de `pipelines/extractors/`).
  * `transformation` — Lógica de limpieza, agregación y cálculo (Steps de `pipelines/transformations/`).
  * `load` — Lógica de persistencia y carga (Steps de `pipelines/loaders/`).
  * `queries` — Funciones de `pipelines/queries/<tabla>.py`.
  * `core` — Pipeline framework propio (raramente requerido por proyectos consumidores).
  * `orchestration` — Lógica de soporte a la ejecución (bootstrap, runtime helpers).
  * `common` — Utilidades compartidas y manejo de excepciones.

### 3. Pruebas de Steps (Unidad mínima del Pipeline framework)

Los Steps puros (Transformers y Loaders mockeables) se testean instanciando la clase, preparando un `StepContext` con `set_artifact(...)` para los inputs upstream, y aserteando el output:

```python
# tests/scripts/python/drivers_sync/transformation/drivers_transformer/test_execute_from_drivers_transformer.py
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

### 4. Pruebas del Pipeline end-to-end (con Steps fake)

Para validar que la composición del Pipeline funciona, usar Steps fake que retornan datos fijos:

```python
from pipelines.core import Pipeline, Step, StepContext


class FakeExtract(Step):
    name = "extract_drivers"

    def execute(self, ctx):
        return [1, 2, 3]


class TestBuildDriversSyncPipeline:
    def test_should_propagate_artifacts_through_steps_when_run(self):
        # Arrange
        pipeline = Pipeline(name="test", steps=[FakeExtract(), DriversTransformer(), DriversLoader()])

        # Act
        result = pipeline.run(StepContext())

        # Assert
        assert "load_drivers" in result.metrics
```

### 5. Pruebas de Queries Module

Las queries en `pipelines/queries/<tabla>.py` se testean de **dos formas válidas**, ambas igual de simples:

#### Opción A — monkeypatch del módulo (sin DB)
Útil cuando se está testeando el Step que consume la query, no la query en sí:

```python
from pipelines.queries import dim_driver


def test_should_resolve_driver_sk_when_uber_id_matches(monkeypatch):
    # Arrange
    monkeypatch.setattr(dim_driver, "get_uber_id_map", lambda s: {"abc-123": 42})
    ...
```

#### Opción B — SQLite in-memory (con DB real)
Útil cuando se quiere testear la query directamente:

```python
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from pipelines.queries import dim_driver


class TestGetUberIdMapFromDimDriver:
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

> El scaffold incluye un ejemplo runnable de la opción B en `pipelines/examples/sample_pipeline.py` (el `SampleTransformer` consume `pipelines.queries.sample_lookup.get_category_thresholds` contra una SQLite seeded para que el ejemplo no requiera Postgres).

### 6. Pruebas de Reusable Steps (SqlExtractor, PostgresLoader, etc.)

Cuando se usa un Reusable Step pre-construido, **no hace falta** testearlo en el proyecto consumidor (ya tiene tests propios en el scaffold). Solo testear:
- Que el builder del Pipeline lo instancia con los parámetros correctos.
- Que las queries SQL pasadas como string son sintácticamente válidas (opcional: parsear con `sqlglot`).

### 7. Pruebas de Migraciones SQL (`sql/`)

Para `.sql` nuevos en `sql/raw/`, `sql/stg/`, `sql/core/`, validar:
- **Idempotencia**: aplicar dos veces el mismo archivo no debe fallar (test runneando contra SQLite o Postgres ephemeral).
- **Sintaxis**: parsear con `sqlglot.parse(open(path).read(), read='postgres')`.
- **Header obligatorio**: assertear que las primeras líneas matcheen `-- Owner: ...` y `-- Purpose: ...`.

```python
import re
from pathlib import Path

import pytest


@pytest.mark.parametrize("sql_file", Path("sql").rglob("*.sql"))
class TestSqlMigrations:
    def test_should_have_owner_and_purpose_header_when_parsed(self, sql_file):
        # Arrange
        content = sql_file.read_text()

        # Act / Assert
        assert re.search(r"^-- Owner:\s+\S+", content, re.MULTILINE)
        assert re.search(r"^-- Purpose:\s+\S+", content, re.MULTILINE)
```

## Bootstrap del entorno de tests (`tests/conftest.py`)

El scaffold provee fixtures reutilizables. Para garantizar aislamiento del singleton `DatabaseManager`:

```python
# tests/conftest.py (referencia del scaffold)
from unittest.mock import MagicMock, patch
import pytest

from pipelines.utils.db import database_manager as dm_module
from pipelines.utils.db.database_manager import DatabaseManager, db_manager


def _reset_db_manager_state():
    db_manager._engines = {}
    db_manager._session_factories = {}
    db_manager._default_db_name = None


@pytest.fixture(autouse=True)
def reset_database_manager_singleton():
    DatabaseManager._instance = None
    _reset_db_manager_state()
    yield
    DatabaseManager._instance = None
    _reset_db_manager_state()


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

Si tu test toca la cadena de conexión de DB pero no necesita una DB real, usar `mocked_engine_factories`. Si necesita una DB real de prueba, usar SQLite in-memory (no Postgres real).

## Patrón de Diseño: AAA (Arrange-Act-Assert)

Todos los tests deben seguir obligatoriamente la estructura **AAA**:

1.  **Arrange (Organizar)**: Configurar el entorno, instanciar Steps, preparar `StepContext` con artefactos upstream, configurar Mocks.
2.  **Act (Actuar)**: Ejecutar la función o método que se está probando (`step.execute(ctx)`, `pipeline.run(ctx)`, `dim_driver.get_uber_id_map(session)`).
3.  **Assert (Afirmar)**: Verificar el resultado y las interacciones con los mocks.

### Ejemplo con AAA

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

- **Archivo**: `test_{function_name}_from_{class_name}.py`
  - Para Steps: `test_execute_from_{class_name}.py`.
  - Para Queries: `test_{function_name}_from_{table_name}.py`.
- **Clase**: `Test{FunctionName}From{ClassName}`
- **Función**: `test_should_{expected_behavior}_when_{condition}`

## Requerimientos de Calidad

| Área | Mínimo |
|---|---|
| **Aislamiento** | No se permiten conexiones reales a Postgres / BigQuery / APIs en tests unitarios. Usar `mocked_engine_factories` o SQLite in-memory. |
| **Cobertura `transformation`** | ≥ 90% |
| **Cobertura `extraction`** | ≥ 90% |
| **Cobertura `queries`** | ≥ 90% |
| **Cobertura global del proyecto** | ≥ 80% (visible en banner `GLOBAL COVERAGE: XX.XX%`) |
| **Integridad DAG** | 100% de los DAGs deben pasar el DagBag test sin `import_errors`. |
| **Reglas CI por DAG** | DagBag test debe assertear: `catchup=False`, `tags` no vacío, owner ≠ `airflow`, description presente, snake_case ID. |
| **`sql/` migrations** | Cada archivo nuevo debe tener test de idempotencia + parseo + header `Owner/Purpose`. |

## Validación local antes del PR

```bash
# Lint
ruff check dags/ scripts/python/ tests/
ruff format --check dags/ scripts/python/ tests/

# Tests + cobertura
pytest tests/ -v --cov=scripts/python/pipelines --cov-report=term-missing

# DAG validation rápida (sin pytest)
python -c "from airflow.models import DagBag; bag = DagBag(dag_folder='dags/', include_examples=False); print(bag.import_errors or 'OK')"
```

## Checklist por tipo de cambio

### PR que agrega un DAG nuevo
- [ ] `tests/dags/<dag_id>/test_<dag_id>.py` con DagBag + assertions de metadata.
- [ ] Test del builder del Pipeline correspondiente.
- [ ] Tests unitarios por capa para cada Step custom nuevo.

### PR que agrega un Step custom (Extractor / Transformer / Loader)
- [ ] `tests/scripts/python/<folder>/{extraction|transformation|load}/<file>/test_execute_from_<class>.py`.
- [ ] Tests con `StepContext.set_artifact(...)` cuando el Step tiene `inputs`.
- [ ] Mock de `get_db` o uso de `mocked_engine_factories` si el Step toca DB.

### PR que agrega una query a `pipelines/queries/<tabla>.py`
- [ ] Test con SQLite in-memory **o** consumido a través del Step con monkeypatch.
- [ ] Cobertura ≥ 90% del módulo de queries.

### PR que agrega/modifica `sql/<schema>/*.sql`
- [ ] Si es archivo nuevo: idempotencia + parseo + header `Owner/Purpose`.
- [ ] Si modifica un archivo existente: **REQUEST_CHANGES** y pedir un nuevo archivo `NNN_<tabla>_<descripcion>.sql`.

### PR que agrega una conexión a DB
- [ ] `.env.example` actualizado.
- [ ] Campo en `Settings` (Pydantic).
- [ ] Registro en `postgresql_connect.py`.
- [ ] Fixture o mock que cubra la nueva conexión en `conftest.py` si afecta tests existentes.
