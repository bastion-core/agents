# Bloque routing en el frontmatter

El bloque `routing` es metadata opcional en el frontmatter de un agente (`plugins/*/agents/*.md`) o de un
skill (`plugins/*/skills/*/SKILL.md`). La plataforma SDD lo lee al sincronizar el catalogo de agentes y lo usa
para filtrar candidatos antes de recomendar un sub-agente y sus skills para una tarea.

Claude Code no usa este bloque: ignora las claves del frontmatter que no conoce, asi que agregarlo no cambia
como se carga ni como se invoca el agente.

## Ejemplo

```yaml
---
name: backend-py
description: Backend Python Development Agent specializing in Clean Architecture ...
model: inherit
color: green
skills:
- github-workflow
routing:
  stacks:
  - python
  - fastapi
  - sqlalchemy
  path_globs:
  - "**/*.py"
  - "!**/tests/**"
  - "!**/alembic/versions/**"
  task_kinds:
  - implementation
  pairs_with_skills:
  - "python-development:backend-py"
  - "general:github-workflow"
---
```

## Claves

Todas las claves son opcionales y todas son listas de textos. No se aceptan otras claves dentro de `routing`.

| Clave | Que indica | Valores |
|---|---|---|
| `stacks` | Tecnologias que el agente domina. Se comparan con el campo `stack` de la tarea. | Texto en minusculas, por ejemplo `python`, `fastapi`, `nextjs`, `flutter`, `sdd`. |
| `path_globs` | Rutas que el agente sabe tocar. Se comparan con `files_to_create` y `files_to_modify` de la tarea. | Globs relativos a la raiz del repo destino. Un glob que empieza con `!` excluye rutas. |
| `task_kinds` | Tipos de tarea que el agente atiende. | `implementation`, `tests`, `review`, `migration`, `docs`. |
| `pairs_with_skills` | Skills que conviene cargar junto al agente. | `plugin:skill`, por ejemplo `python-development:qa-backend-py`. |

### stacks

Usar el nombre corto de la tecnologia, en minusculas y sin version. Listar primero el lenguaje y despues los
frameworks o librerias que el agente conoce a fondo. Un agente generalista no debe listar todo lo que podria
tocar, solo lo que domina.

### path_globs

- Los globs se evaluan contra las rutas de la tarea relativas a la raiz del repositorio destino.
- `**` cruza directorios; `*` no. Empezar con `**/` hace que el glob funcione tambien en monorepos.
- Un glob con `!` al inicio excluye: una ruta es candidata si coincide con al menos un glob positivo y con
  ningun glob de exclusion.
- Escribir los globs entre comillas dobles, porque `*` y `!` tienen significado especial en YAML.

### task_kinds

| Valor | Uso |
|---|---|
| `implementation` | Escribir o cambiar codigo de produccion. |
| `tests` | Escribir o cambiar pruebas. |
| `review` | Revisar un PR o un cambio sin implementarlo. Todos los reviewers usan este valor. |
| `migration` | Migraciones de base de datos o de datos. |
| `docs` | Especificaciones y documentacion (por ejemplo feature.yaml, technical.yaml, tareas). |

### pairs_with_skills

Cada valor usa el formato canonico `plugin:skill` (el mismo de `assigned_skills` en las tareas SDD). El
plugin es el nombre del plugin del marketplace donde vive el skill, no necesariamente el del agente. Ejemplo:
`general:github-workflow` desde un agente de `python-development`.

## Agentes sin el bloque

El bloque es opcional. Un agente o skill sin `routing` sigue apareciendo en el catalogo y sigue siendo
candidato para cualquier tarea. Como la plataforma no puede comprobar su stack, la tarea recomendada con ese
agente queda marcada para revisar y sin preseleccion.

## Validacion

`scripts/validate-agents.sh` acepta archivos sin `routing`. Cuando el bloque existe comprueba que:

- el frontmatter completo sea YAML valido;
- `routing` sea un mapa con solo las cuatro claves conocidas;
- cada clave sea una lista de textos no vacios;
- `task_kinds` use solo los cinco valores de la tabla;
- `pairs_with_skills` use el formato `plugin:skill`.

Al agregar o cambiar el bloque, subir la version del plugin en su `plugin.json` y en
`.claude-plugin/marketplace.json`.
