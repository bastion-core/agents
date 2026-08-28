# Schema: Branch Naming Format

Estructura estándar obligatoria para todos los nombres de rama del proyecto.

## Estructura (Structure)

El nombre debe seguir el formato:
`<type>/<short-summary>`

## Tipo (Type)

*Obligatorio.* Debe ser uno de los siguientes:

- `feat`: Nueva funcionalidad.
- `fix`: Corrección de un bug.
- `docs`: Cambios en la documentación.
- `style`: Cambios que no afectan el significado del código (espacios, formato, etc).
- `refactor`: Cambio de código que no corrige un bug ni añade una funcionalidad.
- `test`: Añadir o corregir pruebas existentes.
- `chore`: Tareas de mantenimiento (build, dependencias, CI).
- `hotfix`: Corrección crítica en producción que va directo a `master`.

El tipo debe coincidir con el `type` del commit principal de la rama.

## Separador

*Obligatorio.* Una única barra `/` entre el type y el summary. No se permiten
niveles adicionales (`feat/auth/jwt` es inválido).

## Resumen (Summary)

*Obligatorio.* Descripción corta del objetivo de la rama.

- **Límite**: Máximo 40 caracteres.
- **Idioma**: **INGLÉS**, siempre.
- **Formato**: `kebab-case` (minúsculas, dígitos y guiones `-`).
- **Regla 1**: No usar espacios, acentos, mayúsculas ni guion bajo `_`.
- **Regla 2**: Omitir artículos y palabras vacías (`the`, `a`, `for`).
- **Regla 3**: Ser específico; evitar `updates`, `changes`, `wip`.

## Referencia a Issue

*Opcional.* Se añade como sufijo numérico al final del summary.

- Ejemplo: `feat/jwt-refresh-123`.

## Destino del Pull Request

El type determina la rama destino y, por tanto, el template de PR a usar:

- `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore` → PR a **Staging (Develop)**.
- `hotfix` → PR a **Master**, con el template de Hotfix.

## Reglas Generales

1. Una rama debe representar una sola intención, igual que un commit atómico.
2. Evitar nombres genéricos como `fix/bug`, `chore/updates` o `feat/new`.
3. No incluir nombres de personas ni fechas en la rama.
4. Las ramas protegidas (`master`, `main`, `develop`, `staging`) no siguen este
   formato y nunca deben renombrarse.
