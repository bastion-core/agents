---
name: airflow-dags-py
description: Estándares de arquitectura y patrones de desarrollo para DAGs de Apache Airflow en Python.
---

# Airflow DAGs Development Skill

Este skill proporciona el conocimiento experto para diseñar e implementar pipelines de datos utilizando Apache Airflow, siguiendo los estándares de arquitectura y desarrollo del proyecto Voltop.

## Recursos Disponibles

- **Arquitectura**:
  - `references/architecture.md`: Organización del repositorio, dominios de datos y relación con Alembic.
- **Patrones de Desarrollo**:
  - `references/dev_patterns.md`: Uso de TaskFlow API, estándares de nomenclatura y mejores prácticas.
- **Gestión de Estado**:
  - `references/state_management.md`: Uso de XComs, variables de Airflow y persistencia en base de datos.

## Instrucciones de Uso

### 1. Diseño de Arquitectura
Al diseñar un nuevo pipeline o modificar uno existente, el agente debe:
1. Consultar `references/architecture.md` para asegurar que el DAG se ubique en el subdirectorio de dominio correcto dentro de `dags/`.
2. Validar que cualquier cambio en el esquema de datos esté soportado por una migración en `alembic/versions/`.

### 2. Implementación de DAGs
Al escribir código para un DAG:
1. Priorizar el uso de la **TaskFlow API** (`@dag`, `@task`) según se detalla en `references/dev_patterns.md`.
2. Seguir estrictamente los estándares de nomenclatura para DAG IDs (`{dominio}_{proceso}_dag`) y archivos (`_dag.py`).
3. Asegurar que todas las tareas sean **idempotentes** y utilicen conexiones gestionadas por Airflow (no credenciales hardcodeadas).

### 3. Manejo de Datos y Estado
Para la comunicación entre tareas y persistencia:
1. Seguir las guías de `references/state_management.md` para el uso de XComs (metadatos únicamente).
2. Utilizar variables de Airflow para configuraciones dinámicas.
3. Asegurar que los resultados finales (KPIs/Métricas) se persistan en las tablas de base de datos correspondientes.

## Reglas de Trabajo – Ingeniería de Datos

### Construir únicamente lo que el pipeline necesita ahora
Nunca crear tablas, funciones, DAGs o columnas a menos que el stack completo exista hoy: extractor + transformación + loader + DAG. No crear dimensiones placeholder, ni tablas solo con seeds, ni esquemas especulativos. Si se discute una integración futura, dejar una nota `## Próximos pasos` en la conversación — no tocar el código.

### Usar lo que Postgres ya ofrece
Evitar recrear funcionalidad nativa. Las fechas y timestamps viven en columnas `DATE` / `TIMESTAMP` — no en una tabla `dim_date`. Usar `DATE_TRUNC`, `EXTRACT`, `TO_CHAR`, `GENERATE_SERIES` directamente en las consultas. Añadir una tabla de lookup solo cuando contenga datos que no puedan derivarse (p. ej. `dim_driver`, `dim_fleet`).

### Usar la estructura ya existente
Antes de diseñar algo nuevo, leer el DDL, loaders y transformaciones existentes. Reutilizar `upsert_df`, `get_engine` y el patrón de capas `raw → stg → core` ya establecido. Respetar los nombres de columnas, claves de conflicto y lógica de upsert que ya están en el repositorio.

### Probar cada join y cada columna que debería tener datos
Después de escribir una transformación o loader, verificar el conteo de filas y la tasa de valores no nulos en las columnas clave antes de declararlo terminado:

```sql
-- patrón rápido de sanity check
SELECT
    COUNT(*)                          AS total_rows,
    COUNT(driver_sk)                  AS driver_sk_filled,
    COUNT(activity_date)              AS date_filled,
    MIN(activity_date),
    MAX(activity_date)
FROM core.fact_driver_activity;
```

Si se espera que un join haga match (p. ej. resolución de driver), verificar la tasa de match explícitamente:

```sql
SELECT match_status, COUNT(*) FROM stg.uber_driver_activity GROUP BY 1;
```

Una columna que siempre es `NULL` es un bug, no un estado válido — investigar antes de continuar.

### Visibilizar datos vacíos o faltantes inmediatamente
Si una tabla, columna o lookup no tiene datos cuando debería tenerlos, detenerse y reportarlo:

- Mostrar al usuario la consulta exacta y el resultado.
- Pedir los datos fuente o credenciales faltantes si ese es el bloqueante.
- Si el usuario no puede proveerlo en la sesión actual, añadir una nota `## Bloqueado / próximos pasos` listando exactamente qué se necesita y por qué, y continuar con el trabajo no bloqueado.

Nunca aceptar silenciosamente resultados vacíos ni saltar una capa porque los datos "vendrán después".

### Probar — o indicar al usuario exactamente cómo probar
Después de cada cambio, ejecutar la tarea del DAG o la función de Python correspondiente y revisar el output. Si la ejecución directa no es posible (sin acceso a DB, sin Airflow, sin archivo), decirlo explícitamente y entregar al usuario el comando o consulta exacta a ejecutar:

```
No puedo conectarme a la instancia de Airflow desde aquí.
Ejecuta esto para verificar:
  docker exec -it <container> airflow tasks test <dag_id> <task_id> <date>
Luego revisa:
  SELECT COUNT(*) FROM core.fact_driver_activity WHERE activity_date = '<date>';
```

Nunca marcar una tarea como completa sin haberla ejecutado tú mismo o entregar al usuario un paso de verificación concreto.
