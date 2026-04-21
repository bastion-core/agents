---
name: github-workflow
description: Estándares y templates para el flujo de trabajo en GitHub, incluyendo mensajes de commit, Pull Requests y Releases.
---

# GitHub Workflow Skill

Este skill proporciona el conocimiento experto para seguir los estándares de Git y GitHub del proyecto. Cuando este skill está activo, el agente debe seguir rigurosamente los formatos y reglas definidos en `references/`.

## Regla de Idioma Mandatoria
- **IDIOMA**: Todos los textos generados para GitHub (**commits, Pull Requests y Releases**) deben redactarse exclusivamente en **INGLÉS**, independientemente del idioma en el que se esté comunicando el usuario.

## Recursos Disponibles

- **Commits**:
  - `references/commit.schema.md`: Reglas y estructura de mensajes.
  - `references/commit.example.md`: Ejemplos de uso.
- **Pull Requests**:
  - `references/pr-staging.template.md`: Template para PRs a staging/develop.
  - `references/pr-hotfix.template.md`: Template para PRs de hotfix a master.
- **Releases**:
  - `references/release.template.md`: Template para notas de lanzamiento.

## Instrucciones de Uso

### 1. Mensajes de Commit
Antes de realizar un commit, el agente debe:
1. Leer `references/commit.schema.md`.
2. Proponer un mensaje en **inglés** que siga estrictamente el formato `<type>(scope): <summary>`.
3. Validar que el resumen no exceda los 50 caracteres y use verbos en imperativo.

### 2. Creación de Pull Requests
Cuando se prepare un PR:
1. Identificar si es para **Staging** (desarrollo normal) o **Master** (hotfix).
2. Leer el template correspondiente en **inglés** (`references/pr-staging.template.md` o `references/pr-hotfix.template.md`).
3. Completar todas las secciones en **inglés**, incluyendo descripción, pruebas realizadas y evidencias.

### 3. Notas de Release
Para generar un Release:
1. Leer `references/release.template.md`.
2. Clasificar los cambios en Features, Improvements o Bug Fixes basándose en el historial de commits, redactando todo en **inglés**.
