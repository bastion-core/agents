# Spec Generator — SDD Specification Workspace

Este workspace genera especificaciones estandarizadas en formato **Specification-Driven Development (SDD)** usando subagents especializados. Es parte de la estrategia multi-modelo: **Gemini para Discovery, Claude Code para Delivery**.

## Flujo Recomendado

Sigue estos pasos secuencialmente para generar specs completas:

### Paso 1: Generar feature.yaml con @product

Invoca `@product` con la descripcion de la funcionalidad, stack, criterios de aceptacion, reglas de negocio y ruta destino.

```
@product Necesito una spec para [descripcion de funcionalidad].
Stack: [python_fastapi | nextjs | flutter | multi_stack]
Criterios: [criterios de aceptacion]
Reglas: [reglas de negocio con valores concretos]
Guardar en: docs/features/{feature_name}/feature.yaml
```

### Paso 2: Generar technical.yaml con @architect

Invoca `@architect` con la ruta al feature.yaml generado, el stack, repositorio de referencia y ruta destino.

```
@architect Genera el technical.yaml a partir de:
docs/features/{feature_name}/feature.yaml
Stack: [python_fastapi | nextjs | flutter]
Repositorio de referencia: [path al repo local]
Guardar en: docs/features/{feature_name}/technical.yaml
```

### Paso 3: Delivery con Claude Code

Con ambas specs generadas y escritas a disco, abre Claude Code en el repositorio destino para iniciar la fase de Delivery (implementacion).

```bash
cd /path/to/project-repo && claude
```

## Subagents Disponibles

| Subagent | Invocacion | Funcion |
|----------|-----------|---------|
| @product | `@product [descripcion]` | Genera feature.yaml (spec de producto) |
| @architect | `@architect [instrucciones]` | Genera technical.yaml (spec tecnica) |

## Instrucciones de Orquestacion

Despues de que un subagent complete su tarea, sugiere al usuario el siguiente paso:

- Despues de `@product` → Sugerir: "feature.yaml guardado. Para generar la spec tecnica, usa: `@architect`"
- Despues de `@architect` → Sugerir: "technical.yaml guardado. Para iniciar desarrollo, abre Claude Code en tu proyecto: `cd /path/to/repo && claude`"

## Reglas Compartidas

1. **Idioma**: Todo el contenido de las specs debe estar en espanol
2. **Sin codigo**: Los subagents generan especificaciones, NUNCA codigo de implementacion
3. **Single prompt first**: Si el usuario proporciona toda la informacion en un solo mensaje, generar la spec directamente sin preguntas. Solo preguntar si faltan datos criticos
4. **Escritura a disco**: Los subagents SIEMPRE escriben las specs al filesystem via write_file
5. **Ruta destino**: Si el usuario no indica ruta, preguntar donde guardar el archivo
6. **Compatibilidad**: Las specs generadas deben ser consumibles por los agentes de Claude Code sin modificaciones

## Stacks Soportados

| Stack | Context Files | Patron Arquitectonico |
|-------|--------------|----------------------|
| python_fastapi | `context/python-api/` | Hexagonal Architecture 3 capas |
| nextjs | `context/nextjs-app/` | Two-layer Architecture (Domain + Infrastructure) |
| flutter | `context/flutter-app/` | Clean Architecture 4 capas con Feature-Based Modularization |
| multi_stack | Combinar context files relevantes | Segun componente |
