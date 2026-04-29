# Architecture - Airflow DAGs

Este documento describe la arquitectura y organización del repositorio de DAGs de Apache Airflow en el proyecto Voltop.

## Estructura del Repositorio

El repositorio sigue una estructura modular orientada a dominios de datos y procesos ETL.

```text
/
├── dags/                   # Directorio raíz de DAGs de Airflow
│   ├── metrics_pipelines/  # DAGs para pipelines de métricas de negocio
│   ├── voltop_app_metrics/ # DAGs específicos de métricas de la aplicación
│   └── _templates/         # Plantillas para la creación de nuevos DAGs
├── alembic/                # Migraciones de base de datos (SQLAlchemy)
│   ├── env.py
│   └── versions/           # Definiciones de tablas de KPIs, métricas y auditoría
├── scripts/                # Scripts de apoyo para administración y entorno local
├── tests/                  # Pruebas unitarias e integración para lógica de DAGs
├── pyproject.toml          # Configuración de dependencias y herramientas (Poetry/Black)
└── requirements.txt        # Dependencias de Python para el entorno de Airflow
```

## Organización de DAGs

Los DAGs no se encuentran en la raíz de `dags/`, sino que se agrupan en subdirectorios por **dominio de datos** o **propósito funcional**.

1. **Dominios**: Cada carpeta dentro de `dags/` representa un dominio (ej. `metrics_pipelines`).
2. **Templates**: Se utiliza la carpeta `_templates/` para asegurar que los nuevos DAGs sigan la estructura estándar definida por el equipo.

## Relación con Alembic

El repositorio gestiona su propio esquema de base de datos para tablas de soporte (staging, fact tables, registries) mediante **Alembic**.

- **Migraciones**: Antes de que un DAG que dependa de una nueva tabla sea desplegado, la migración correspondiente en `alembic/versions/` debe ser ejecutada.
- **Entidades**: Los DAGs interactúan con tablas definidas y versionadas en este repositorio, asegurando la integridad entre la lógica de transformación y el esquema de datos.
