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
