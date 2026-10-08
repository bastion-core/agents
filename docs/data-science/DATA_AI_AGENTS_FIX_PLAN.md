# Plan de Solución: Inconsistencias, Bugs y Actualización de Agentes Data & AI

**Fecha:** Octubre 2026  
**Área:** Data & AI Platform Engineering  
**Objetivo:** Resolver las discrepancias entre agentes, modernizar el reviewer de Airflow para alinearlo a la tríada, y corregir los bugs detectados en las referencias de los skills.  
**Estado:** Propuesta de Solución / Aprobado para Implementación

---

## 1. Problema 1: El Reviewer de DAGs (`reviewer-airflow-dags-py`) Quedó Desalineado

### Diagnóstico
El agente revisor `reviewer-airflow-dags-py` (en `plugins/python-development/agents/reviewer-airflow-dags-py.md`) continúa exigiendo patrones del andamiaje legacy (`airflow-dags-scaffold`), tales como:
- Uso del **Pipeline framework** (`Step`, `Pipeline`, `StepContext`).
- Uso del **Queries Module**.
- Ejecución de transformaciones en pandas para poblar tablas `core.fact_*`.
- Patrones de pruebas unitarias rígidos (`test_should_*`, `From{ClassName}`, `folder_dag_name`).

Esto entra en **conflicto directo** con la directriz del nuevo skill `data-engineer-airflow` (líneas 16-17):
> *"PROHIBICIÓN: Transformar datos del warehouse fuera de dbt. Si los datos están en el warehouse, la transformación debe ser un modelo SQL en dbt."*

Actualmente, **un PR que cumple con las reglas del skill viola las del reviewer, y viceversa**.

### Plan de Solución
1. **Actualizar el Rol del Reviewer**: Redefinir `reviewer-airflow-dags-py` para que audite según los estándares del Modern Data Stack:
   - Validar que pandas se use **únicamente en los bordes** (extracción/limpieza inicial).
   - Validar que las transformaciones in-warehouse estén delegadas a **dbt**.
   - Validar que la orquestación de dbt en Airflow utilice **Astronomer Cosmos** (`DbtTaskGroup`).
2. **Eliminar Exigencias Obsoletas**:
   - Remover la obligatoriedad del `Queries Module` y de los `Steps` de transformación en pandas para capas `core`.
   - Reemplazar las reglas de testing procedural por la exigencia de:
     - Pruebas de integridad de DAGs con `DagBag`.
     - Pruebas unitarias de extractores de borde.
     - Contratos y pruebas declarativas de dbt en `schema.yml` (`unique`, `not_null`, `relationships`).

---

## 2. Problema 2: Inconsistencias y Contradicciones entre Skills Nuevos

### Diagnóstico y Matriz de Resolución

Se identificaron 8 contradicciones estructurales entre los skills `data-architecture-postgre`, `data-engineer-airflow` y `analytics-engineer`:

| Tema | Contradicción Detectada | Decisión / Solución Estandarizada | Justificación |
|---|---|---|---|
| **Prefijo de hechos** | `fct_` (DEA, AE) vs. `fact_` (data-architecture-postgre) | **Estandarizar en `fct_`** | Es la convención nativa y universal de dbt y Kimball moderno. |
| **Nombre en staging** | `stg.customers` vs. `stg.stg_stripe_charges` | **Estandarizar en `stg_<source>_<entity>`** | Evita colisiones de nombres al ingerir múltiples fuentes en la misma capa staging. |
| **Dónde carga el Data Engineer** | `stg.*` vs. `raw.*` (handoff del AE) | **Cargar en `raw.*`** | El Data Engineer aterriza datos crudos en `raw.*`. dbt lee de `raw.*` para construir vistas en `stg.*`. |
| **Manejo de Dinero** | `amount_cents` (BIGINT) vs. `NUMERIC` obligatorio | **`NUMERIC(18, 4)` obligatorio** | **Instrucción explícita del usuario**: el tipo `NUMERIC` preserva precisión decimal exacta sin forzar conversiones artificiales a centavos en toda la capa analítica. |
| **Uso de `CHAR(n)`** | Prohibido en general vs. `_record_hash CHAR(64)` | **Usar `VARCHAR(64)` o `TEXT` para hashes** | Mantiene la regla estricta de prohibir `CHAR(n)` en PostgreSQL (evita padding de espacios en blanco). |
| **Columna `status`** | Palabra reservada prohibida vs. Usado como columna | **Prohibir `status` genérico** | Renombrar siempre de forma contextual: `order_status`, `payment_status`, `driver_status`, etc. |
| **Surrogate Keys** | `BIGINT IDENTITY` vs. `md5` de `dbt_utils` (texto) | **`TEXT` / MD5 determinista en DWH** | En el Data Warehouse se debe usar `dbt_utils.generate_surrogate_key` para idempotencia y portabilidad. En OLTP se mantiene `BIGINT IDENTITY` o `UUIDv7`. |
| **`logical_date`** | `TIMESTAMPTZ` obligatorio vs. `VARCHAR(50)` en audit | **Diferenciar tipos según propósito** | `_ingested_at` debe ser `TIMESTAMPTZ`. `logical_date` en auditoría de pipelines es un identificador de intervalo (formato Airflow), representable como `VARCHAR(50)` o `DATE`. |

---

## 3. Problema 3: Corrección de los 6 Bugs en Referencias de Agentes

Se corregirán los siguientes 6 errores puntuales en los archivos de referencia de los skills:

### Bug 1: `KeyError` en el Loader (`postgres_loading_patterns.md:126`)
- **Problema**: El código de carga selecciona `df["record_hash"]`, pero la función de transformación previa nunca genera esa columna.
- **Solución**: Asegurar que el DataFrame devuelto por el transformer calcule e incluya explícitamente `_record_hash` (usando SHA-256 sobre las columnas relevantes) antes de pasarlo al loader.

### Bug 2: Dataset Completo por XCom (`cosmos_airflow_orchestration.md:94-101`)
- **Problema**: El ejemplo del DAG de Cosmos retorna y transfiere un DataFrame/dataset completo a través de XCom, violando la regla explícita de "Prohibido transmitir DataFrames pesados por XCom".
- **Solución**: Modificar la tarea `@task` para que guarde los datos en staging/disco y retorne únicamente un diccionario escalar con metadatos de auditoría: `{"rows_ingested": count, "batch_id": id}`.

### Bug 3: Punto y Coma en Modelos dbt (`dbt_transformation_patterns.md:109, 155`)
- **Problema**: Los ejemplos de modelos dbt finalizan con `select * from final;`. En dbt, el punto y coma final causa errores de sintaxis al ser compilado como una subconsulta CTE.
- **Solución**: Remover el `;` al final de todas las sentencias select en las plantillas y referencias de dbt.

### Bug 4: `select *` en el Import CTE (`dbt_transformation_patterns.md:71`)
- **Problema**: La primera CTE contiene `select * from {{ source(...) }}`, contradiciendo la regla del mismo documento de proyectar explícitamente las columnas.
- **Solución**: Reemplazar `select *` por la proyección explícita de campos en la CTE de importación.

### Bug 5: DAG de Retraining sin `owner` ni `tags` (`retraining_pipelines_and_feature_store.md:50-56`)
- **Problema**: El DAG de reentrenamiento continuo de `ml-engineer` no define `owner` en `default_args` ni `tags`, lo que provocaría que falle las pruebas de validación de `DagBag` del propio skill.
- **Solución**: Añadir `default_args={"owner": "ml-engineer", ...}` y `tags=["ml", "retraining", "feast"]` a la definición del `@dag`.

### Bug 6: Confusión entre Fecha de Ingesta y Fecha Lógica (`transformation_patterns.md:95`)
- **Problema**: El código asigna `_ingested_at = logical_date`, lo cual mezcla el concepto del instante real de ejecución/carga con la ventana de datos que se está procesando.
- **Solución**: Establecer `_ingested_at = pd.Timestamp.now(tz="UTC")` para registrar el momento físico de carga, y usar `logical_date` únicamente para filtros de partición temporal o auditoría.

---

## 4. Plan de Ejecución y Pasos a Seguir

1. **Fase 1 (Reviewer)**: Refactorizar `plugins/python-development/agents/reviewer-airflow-dags-py.md`.
2. **Fase 2 (Skills y Referencias)**: Aplicar las correcciones de inconsistencias en `data-architecture-postgre`, `data-engineer-airflow` y `analytics-engineer`.
3. **Fase 3 (Corrección de Bugs)**: Modificar los snippets de código erróneos en los archivos de referencia identificados.
4. **Fase 4 (Validación)**: Ejecutar `./scripts/validate-agents.sh` para certificar la integridad de los agentes y frontmatters YAML.
