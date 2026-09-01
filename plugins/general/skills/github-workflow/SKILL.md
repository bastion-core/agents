---
name: github-workflow
description: Estándares y templates para el flujo de trabajo en GitHub, incluyendo nombres de rama, mensajes de commit, Pull Requests y Releases en inglés.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# GitHub Workflow Skill

Este skill proporciona el conocimiento experto para seguir los estándares de Git y GitHub del proyecto. Cuando este skill está activo, el agente debe seguir rigurosamente los formatos y reglas definidos en los templates de referencia.

## REGLA DE IDIOMA MANDATORIA
- **IDIOMA**: Todos los textos generados para GitHub (**nombres de rama, commits, Pull Requests y Releases**) deben redactarse exclusivamente en **INGLÉS**, independientemente del idioma en el que se esté comunicando el usuario o el idioma de las especificaciones locales.

## REGLA DE AUTORÍA MANDATORIA

- **PROHIBIDO** incluir cualquier referencia a la autoría del asistente o a la
  sesión de trabajo en textos destinados a GitHub (commits, PRs, releases,
  nombres de rama, comentarios de PR/issue).
- Textos explícitamente prohibidos (y cualquier variante):
  - `Co-Authored-By: Claude ...` / `Co-authored-by: ... <noreply@anthropic.com>`
  - `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
  - `Generated with Claude`, `Made with Claude`, `Assisted by Claude`
  - Menciones a Anthropic, Claude Code, IDs de sesión, IDs de tarea o enlaces
    a transcripciones.
- **Único autor**: el usuario que ejecuta el comando. No se añaden trailers
  `Co-Authored-By` de ningún tipo salvo que correspondan a personas reales del
  equipo y el usuario lo pida explícitamente.
- **Verificación obligatoria antes de ejecutar**: revisar el texto final y
  eliminar estas líneas antes de `git commit`, `gh pr create`, `gh pr edit` o
  la publicación de un release.
- **Corrección**: si un commit o PR ya se creó con estas firmas, corregirlo con
  `git commit --amend` o `gh pr edit` antes de continuar.

---

## 1. ESTÁNDAR DE COMMITS

Antes de realizar un commit, se deben seguir estas reglas:

### Estructura
`<type>(scope opcional): <summary>`

### Reglas
- **Types permitidos**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.
- **Summary**: Máximo 50 caracteres, usar verbo en imperativo, sin punto final, todo en **INGLÉS**.
- **Body/Footer**: Opcional, máximo 72 caracteres por línea, todo en **INGLÉS**.

### Ejemplos
- `feat(auth): add JWT refresh token support`
- `fix(api): handle null response in user endpoint`
- `chore(ci): update GitHub Actions to Node 20`

---

## 2. PULL REQUEST TEMPLATES

Cuando se prepare un PR, se debe identificar el destino y usar el template correspondiente completando toda la información en **INGLÉS**.

### PR a Staging (Develop)
Usa este formato para features, bugfixes y mejoras:

```markdown
<!-- DEVELOP PR (Feature, Bugfix e Improvement) -->
# [Title in English]

## Description
<!-- Provide a general summary and description in English -->

## How has this been tested?
<!-- Describe tests and environment in English -->

- [ ] I have added tests to cover my changes.
- [ ] All new and existing tests passed.

## QA Review
<!-- Add screenshots or coverage info -->

## Types of changes
- [ ] Docs change / refactoring / dependency upgrade.
- [ ] Deployment change.
- [ ] Bug fix.
- [ ] New feature.
- [ ] Improvement.
```

### PR a Master (Hotfix)
Usa este formato para correcciones críticas en producción:

```markdown
<!-- MASTER PR (Hotfix) -->
# Hotfix v...

## Description
<!-- Summary and detail in English -->

## How has this been tested?
<!-- Details in English -->

- [ ] I have added tests to cover my changes.
- [ ] All new and existing tests passed.

## QA Review
<!-- Relevant info for QA in English -->
```

---

## 3. RELEASE NOTES

Para generar una nota de lanzamiento, usa el siguiente formato en **INGLÉS**:

```markdown
# Release v...

## 🚀 Features:
- [Feature description]

## 🙌 Improvements:
- [Improvement description]

## 🐛 Bug Fixes:
- [Bug fix description]
```

---

## 4. BRANCH NAMING

Antes de crear una rama, se deben seguir estas reglas:

### Estructura
`<type>/<short-summary>`

### Reglas
- **Types permitidos**: los mismos del estándar de commits (`feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`) más `hotfix` para correcciones críticas que van a `master`.
- **Summary**: en **INGLÉS**, `kebab-case`, máximo 40 caracteres, descriptivo y sin artículos innecesarios.
- **Separador**: una única `/` entre el type y el summary. No se permiten `/` adicionales.
- **Caracteres**: sólo minúsculas, dígitos y guiones (`-`). Sin espacios, acentos, mayúsculas ni `_`.
- **Issue**: opcional, se añade como sufijo numérico (`feat/jwt-refresh-123`).

### Correspondencia con el destino del PR
- `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore` → PR a **Staging (Develop)**.
- `hotfix` → PR a **Master**, usando el template de Hotfix.

### Ejemplos
- `feat/jwt-refresh-token`
- `fix/null-user-endpoint`
- `chore/bump-actions-node-20`
- `hotfix/payment-rounding`

---

## PROCEDIMIENTO DE ACTIVACIÓN

Cuando necesites realizar una operación de Git/GitHub:
1. Activa este skill.
2. Lee los archivos de referencia en `references/` para ver ejemplos detallados si es necesario.
3. Propón el nombre de rama, el mensaje de commit o el contenido del PR/Release siempre en **INGLÉS**.
4. Valida que el formato cumple con el estándar antes de proceder.
5. Verifica que el texto no contiene firmas de atribución del asistente
   (ver REGLA DE AUTORÍA MANDATORIA) antes de ejecutar el comando.
