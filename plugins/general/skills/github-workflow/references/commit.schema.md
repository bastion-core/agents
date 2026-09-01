# Schema: Commit Message Format

Estructura estándar obligatoria para todos los mensajes de commit en el proyecto.

## Estructura (Structure)

El mensaje debe seguir el formato:
`<type>(scope opcional): <summary>`
`[body opcional]`
`[footer opcional]`

## Cabecera (Header)

### Type (Tipo)
*Obligatorio.* Debe ser uno de los siguientes:
- `feat`: Nueva funcionalidad.
- `fix`: Corrección de un bug.
- `docs`: Cambios en la documentación.
- `style`: Cambios que no afectan el significado del código (espacios, formato, etc).
- `refactor`: Cambio de código que no corrige un bug ni añade una funcionalidad.
- `test`: Añadir o corregir pruebas existentes.
- `chore`: Tareas de mantenimiento (build, dependencias, CI).

### Scope (Alcance)
*Opcional.* Módulo o contexto afectado encerrado entre paréntesis.
- Ejemplos: `(auth)`, `(api)`, `(ui)`, `(db)`.

### Summary (Resumen)
*Obligatorio.* Descripción corta del cambio.
- **Límite**: Máximo 50 caracteres.
- **Regla 1**: Usar verbo en imperativo (ej: "add" no "added").
- **Regla 2**: No usar punto final.
- **Regla 3**: Ser claro y conciso.

## Cuerpo (Body)
*Opcional.* Explicación detallada del cambio.
- **Límite**: Máximo 72 caracteres por línea.
- **Regla 1**: Explicar qué y por qué se cambió, no el "cómo".
- **Regla 2**: Usar párrafos cortos y claros.

## Pie (Footer)
*Opcional.* Información adicional o metadatos.
- **BREAKING CHANGE**: Descripción de cambios que rompen la compatibilidad.
- **Issue Reference**: Referencia a tickets o issues (ej: `Closes #123`).
- **Contenido permitido**: únicamente `BREAKING CHANGE` e `Issue Reference`.
- **PROHIBIDO**: trailers de atribución del asistente o de la sesión, tales como
  `Co-Authored-By: Claude ... <noreply@anthropic.com>`,
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`,
  `Generated with Claude` y cualquier variante que mencione Claude, Claude Code,
  Anthropic o identificadores de sesión.

## Reglas Generales
1. Un commit debe representar una sola intención (cambio atómico).
2. Evitar mensajes genéricos como "fix bug" o "update".
3. Mantener consistencia en el idioma definido para el equipo.
4. El commit no debe contener referencias a la autoría del asistente ni a la
   sesión (ver REGLA DE AUTORÍA MANDATORIA en SKILL.md).
