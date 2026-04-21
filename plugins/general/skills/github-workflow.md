---
name: github-workflow
description: Estándares y templates para el flujo de trabajo en GitHub, incluyendo mensajes de commit, Pull Requests y Releases en inglés.
model: inherit
color: blue
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# GitHub Workflow Skill

Este skill proporciona el conocimiento experto para seguir los estándares de Git y GitHub del proyecto. Cuando este skill está activo, el agente debe seguir rigurosamente los formatos y reglas definidos en los templates de referencia.

## REGLA DE IDIOMA MANDATORIA
- **IDIOMA**: Todos los textos generados para GitHub (**commits, Pull Requests y Releases**) deben redactarse exclusivamente en **INGLÉS**, independientemente del idioma en el que se esté comunicando el usuario o el idioma de las especificaciones locales.

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

## PROCEDIMIENTO DE ACTIVACIÓN

Cuando necesites realizar una operación de Git/GitHub:
1. Activa este skill.
2. Lee los archivos de referencia en `gemini/spec-generator/.gemini/skills/github-workflow/references/` para ver ejemplos detallados si es necesario.
3. Propón el mensaje de commit o contenido del PR/Release siempre en **INGLÉS**.
4. Valida que el formato cumple con el estándar antes de proceder.
