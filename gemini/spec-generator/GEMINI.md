# Spec Generator — SDD Specification Workspace

Este workspace genera especificaciones estandarizadas en formato **Specification-Driven Development (SDD)** usando subagents especializados. Es parte de la estrategia multi-modelo: **Gemini para Discovery, Claude Code para Delivery**.

> **Nota sobre invocacion**: Los subagents se invocan escribiendo el simbolo arroba seguido del nombre del agente al inicio del prompt (ej: arroba + product, arroba + architect).

## Flujo Recomendado

### Flujo A: Nueva funcionalidad

Sigue estos pasos secuencialmente para generar specs de una funcionalidad nueva:

#### Paso 1: Generar feature.yaml con el agente **product**

Invoca al agente **product** con la descripcion de la funcionalidad, stack, criterios de aceptacion, reglas de negocio y ruta destino.

```
Necesito una spec para [descripcion de funcionalidad].
Stack: [python_fastapi | nextjs | flutter | multi_stack]
Criterios: [criterios de aceptacion]
Reglas: [reglas de negocio con valores concretos]
Guardar en: docs/features/{feature_name}/feature.yaml
```

#### Paso 2: Generar technical.yaml con el agente **architect**

Invoca al agente **architect** con la ruta al feature.yaml generado, el stack, repositorio de referencia y ruta destino.

```
Genera el technical.yaml a partir de:
docs/features/{feature_name}/feature.yaml
Stack: [python_fastapi | nextjs | flutter]
Repositorio de referencia: [path al repo local]
Guardar en: docs/features/{feature_name}/technical.yaml
```

#### Paso 3: Delivery con Claude Code

Con ambas specs generadas y escritas a disco, abre Claude Code en el repositorio destino para iniciar la fase de Delivery (implementacion).

```bash
cd /path/to/project-repo && claude
```

### Flujo B: Cambio a funcionalidad existente

Sigue estos pasos para generar specs de un cambio incremental a una feature existente:

#### Paso 1: Generar change.yaml con el agente **product**

Invoca al agente **product** indicando que es un cambio a una feature existente. El agente leera el feature.yaml padre y generara el change.yaml.

```
Necesito un cambio para la feature [feature_name]: [descripcion del cambio].
Feature existente: docs/features/{feature_name}/feature.yaml
Repositorios afectados: [lista de repos]
Prioridad: [low | medium | high | critical]
Guardar en: docs/features/{feature_name}/changes/{change_id}/change.yaml
```

#### Paso 2: Generar technical.yaml del cambio con el agente **architect**

Invoca al agente **architect** con la ruta al change.yaml generado. El agente leera el contexto padre (feature.yaml + technical.yaml) automaticamente.

```
Genera el technical.yaml a partir de:
docs/features/{feature_name}/changes/{change_id}/change.yaml
Stack: [python_fastapi | nextjs | flutter]
Repositorio de referencia: [path al repo local]
Guardar en: docs/features/{feature_name}/changes/{change_id}/technical.yaml
```

#### Paso 3: Delivery con Claude Code

Con las specs del cambio generadas, abre Claude Code en el repositorio destino.

```bash
cd /path/to/project-repo && claude
```

## Subagents Disponibles

### Generacion de Specs (Discovery)

| Subagent | Invocacion | Funcion |
|----------|-----------|---------|
| **product** | arroba + product [descripcion] | Genera feature.yaml (spec de producto) o change.yaml (cambio incremental) |
| **architect** | arroba + architect [instrucciones] | Genera technical.yaml (spec tecnica) a partir de feature.yaml o change.yaml |
| **data-architect** | arroba + data-architect [instrucciones] | Diseña y audita modelos PostgreSQL, optimización de tuplas y memoria, indexación y DDL sin downtime |
| **qa-data-architect** | arroba + qa-data-architect [instrucciones] | Audita migraciones PostgreSQL: riesgo de bloqueos (locks), índices FK faltantes, padding de tuplas, UTC y RLS |

### Desarrollo y Review por Stack

| Subagent | Stack | Funcion |
|----------|-------|---------|
| **data-engineer** | Python/Airflow/dbt | Ciclo completo de ingeniería y modelado de datos: ingesta en bordes (pandas), orquestación Airflow, dbt Semantic Layer, marts y exposures |
| **qa-data-engineer** | Python/Airflow/dbt | Audita DAGs de Airflow: idempotencia, backfill safety, reintentos/SLAs, antipatrón de pandas fuera de DWH y tests dbt |
| **data-scientist** | Python/ML/Stats/BI | Ciclo completo de ciencia y ML: EDA híbrido, inferencia estadística, ML/Deep Learning, Model Registry, CI/CD, drift (PSI), retraining y servido API |
| **qa-data-scientist** | Python/ML/Stats/BI | Audita pipelines ML: data leakage, splits temporales, rigor estadístico (p-hacking), tamaños del efecto y MLflow |
| **backend-py** | Python/FastAPI | Desarrollo backend con Hexagonal Architecture |
| **qa-backend-py** | Python/FastAPI | Testing y QA para backend Python |
| **frontend-nextjs** | Next.js | Desarrollo frontend con Two-layer Architecture |
| **reviewer-frontend-nextjs** | Next.js | Code review de PRs Next.js |
| **mobile-flutter** | Flutter | Desarrollo mobile con Clean Architecture |

## Instrucciones de Orquestacion

Despues de que un subagent complete su tarea, sugiere al usuario el siguiente paso:

- Despues del agente **product** (feature.yaml) → Sugerir: "feature.yaml guardado. Para generar la spec tecnica, invoca al agente **architect**"
- Despues del agente **product** (change.yaml) → Sugerir: "change.yaml guardado y feature.yaml padre actualizado. Para generar la spec tecnica del cambio, invoca al agente **architect** con la ruta al change.yaml"
- Despues del agente **architect** (feature) → Sugerir: "technical.yaml guardado. Para iniciar desarrollo, abre Claude Code en tu proyecto: `cd /path/to/repo && claude`"
- Despues del agente **architect** (change) → Sugerir: "technical.yaml del cambio guardado y technical.yaml padre actualizado. Para iniciar desarrollo, abre Claude Code en tu proyecto: `cd /path/to/repo && claude`"

## Reglas Compartidas

1. **Idioma**: Todo el contenido de las specs debe estar en espanol
2. **Sin codigo**: Los subagents generan especificaciones, NUNCA codigo de implementacion
3. **Single prompt first**: Si el usuario proporciona toda la informacion en un solo mensaje, generar la spec directamente sin preguntas. Solo preguntar si faltan datos criticos
4. **Escritura a disco**: Los subagents SIEMPRE escriben las specs al filesystem via write_file
5. **Ruta destino**: Si el usuario no indica ruta, preguntar donde guardar el archivo
6. **Compatibilidad**: Las specs generadas deben ser consumibles por los agentes de Claude Code sin modificaciones
7. **Estructura de directorios**: Cambios incrementales van en `changes/{change_id}/` dentro del directorio de la feature. Siempre actualizar las specs padre (feature.yaml y/o technical.yaml) al crear un cambio

## Stacks Soportados

| Stack | Context Files | Patron Arquitectonico |
|-------|--------------|----------------------|
| python_fastapi | `context/python-api/` | Hexagonal Architecture 3 capas |
| nextjs | `context/nextjs-app/` | Two-layer Architecture (Domain + Infrastructure) |
| flutter | `context/flutter-app/` | Clean Architecture 4 capas con Feature-Based Modularization |
| multi_stack | Combinar context files relevantes | Segun componente |
