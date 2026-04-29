# [python_skills] - Propuesta Tecnica de Solucion

**Fecha**: 2024-07-31
**Estado**: Draft

---

## 1. Resumen de la Solucion

### Problema
Se necesita encapsular el conocimiento sobre el desarrollo de DAGs de Airflow en una skill de Gemini para que los agentes de IA puedan generar especificaciones técnicas consistentes y de alta calidad para los pipelines de datos.

### Solucion Propuesta
Se creará una nueva skill de Gemini llamada `airflow-dags-py`. Esta skill incluirá los documentos de arquitectura, patrones de desarrollo y manejo de estado como archivos de referencia. Se creará un archivo `SKILL.md` que servirá como punto de entrada para que Gemini utilice este conocimiento.

### Alcance
- **Incluido**:
  - Creación de la estructura de directorios para la nueva skill.
  - Creación del archivo `SKILL.md`.
  - Copia de los documentos de referencia de Airflow.
- **Excluido**:
  - Implementación de los agentes que consumirán esta skill.
  - Modificación de los archivos de contexto originales.

---

## 2. Arquitectura de Componentes

### Diagrama de Componentes
```mermaid
graph TD
    subgraph "Inputs"
        A["`context/airflow-python-dags/*.md`"]
        B["`plugins/general/skills/github-workflow.md` (Template)"]
    end

    subgraph "Process"
        C["Define Skill Structure & Content"]
    end

    subgraph "Output"
        D["`gemini/spec-generator/.gemini/skills/airflow-dags-py/` (Directory)"]
        E["`gemini/spec-generator/.gemini/skills/airflow-dags-py/SKILL.md`"]
        F["`gemini/spec-generator/.gemini/skills/airflow-dags-py/references/*.md`"]
    end

    A --> C
    B --> C
    C --> D
    C --> E
    C --> F
```

### Descripcion de Componentes

| Componente | Responsabilidad | Capa | Dependencias |
|-----------|----------------|------|-------------|
| `airflow-dags-py` skill | Encapsular el conocimiento sobre el desarrollo de DAGs de Airflow. | Agent | Gemini CLI |

---

## 5. Archivos Involucrados

### Archivos a Crear

| Archivo | Proposito | Capa |
|---------|----------|------|
| `gemini/spec-generator/.gemini/skills/airflow-dags-py/references/` | Directorio para los archivos de referencia. | Agent |
| `gemini/spec-generator/.gemini/skills/airflow-dags-py/references/architecture.md` | Documento de arquitectura de Airflow. | Agent |
| `gemini/spec-generator/.gemini/skills/airflow-dags-py/references/dev_patterns.md` | Patrones de desarrollo para Airflow. | Agent |
| `gemini/spec-generator/.gemini/skills/airflow-dags-py/references/state_management.md` | Manejo de estado en Airflow. | Agent |
| `gemini/spec-generator/.gemini/skills/airflow-dags-py/SKILL.md` | Punto de entrada para la skill de Gemini. | Agent |

---

## 6. Fases de Implementacion

| Fase | Descripcion | Dependencias |
|------|-------------|-------------|
| 1 - Foundation | Crear la estructura de directorios. | Ninguna |
| 2 - Core Logic | Copiar los archivos de referencia. | Fase 1 |
| 3 - Integration | Crear el archivo `SKILL.md`. | Fase 2 |