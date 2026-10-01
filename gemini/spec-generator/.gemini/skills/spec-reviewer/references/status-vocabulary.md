# Vocabulario de estados SDD (lista cerrada)

Documento canonico de los valores de `status` permitidos en las especificaciones SDD.
Los schemas (`*.schema.yaml`), el validador (`scripts/validate-specs.sh`), la skill
`spec-reviewer` y los agentes `product` y `architect` se remiten a este documento.

> **Regla de oro:** cualquier otro valor es invalido. No inventes estados ni cambies el
> casing. Un valor fuera de esta lista no se "aproxima" al mas parecido: se corrige al
> valor permitido que corresponda o se consulta con quien pide la spec.

## Por que existe

El registry de la plataforma sdd-flow-ai sincroniza las specs y rechaza los valores que no
conoce. Tasks con `status: DONE`, `PLANNED` o `BLOCKED` (cuando la plataforma aun no lo
aceptaba) y un `task` de 51 caracteres abortaron la sincronizacion completa. Para evitarlo
los estados son una lista cerrada, verificada por maquina antes de publicar.

## Dos vocabularios, a proposito

Los tres niveles comparten el **concepto** de ciclo de vida (nace pendiente, se ejecuta, se
cierra), pero **no comparten los valores ni el casing**. Se mantienen ambos vocabularios y
no se unifican:

- `task`: MAYUSCULAS con guion bajo (`IN_PROGRESS`).
- `feature` y `change`: minuscula con guion medio (`in-progress`).

## Tabla por tipo de spec

| Spec | Campo | Valores permitidos | Casing | Valor inicial | Obligatorio |
|------|-------|--------------------|--------|---------------|-------------|
| `task` (`tasks/NN-*.yaml`) | `status` | `PENDING`, `IN_PROGRESS`, `COMPLETED`, `BLOCKED` | MAYUSCULAS, `_` | `PENDING` | si |
| `change` (`change.yaml`) | `status` | `planned`, `in-progress`, `completed`, `cancelled` | minuscula, `-` | `planned` | si |
| `feature` (`feature.yaml`) | `status` | `planned`, `in-progress`, `completed`, `cancelled` | minuscula, `-` | `planned` | no |
| `technical` (`technical.yaml`) | no tiene `status` | no aplica | no aplica | no aplica | no aplica |

`change.dependencies.features[].status` es el estado **requerido** de la feature de la que
depende el cambio y usa el vocabulario de feature (`planned`, `in-progress`, `completed`,
`cancelled`).

Un `technical.yaml` no declara estado: no agregues `status` a nivel raiz. Los `status` que
aparecen dentro de `api_contract` son codigos HTTP, no estados de spec.

## Transiciones

### Task

```text
PENDING ──────► IN_PROGRESS ──────► COMPLETED   (terminal)
   │  ▲            │  ▲
   │  └────────────┘  │
   ▼                  │
BLOCKED ──────────────┘
```

| Desde | Hacia permitido |
|-------|-----------------|
| `PENDING` | `IN_PROGRESS`, `BLOCKED` |
| `IN_PROGRESS` | `COMPLETED`, `BLOCKED`, `PENDING` |
| `BLOCKED` | `PENDING`, `IN_PROGRESS` |
| `COMPLETED` | ninguno (terminal) |

Una task tiene exactamente 4 estados. No existe `CANCELLED` para tasks: una task que ya no
aplica se elimina del change o se reemplaza en una nueva version de cambios.

**Semantica de `BLOCKED`:** la tarea no puede avanzar por una dependencia externa a ella
(una decision pendiente, un acceso, un servicio de otro equipo, una task de otro change).
El motivo se documenta en `scope` o en las notas de la task; **no** existe un campo nuevo
para ello. Que una task dependa de otra del mismo change (`depends_on`) no la hace
`BLOCKED`: sigue `PENDING` hasta que sus dependencias se completan.

**Quien fija cada estado:** quien genera la spec (agente `architect`) escribe siempre
`PENDING` en las tasks nuevas. `IN_PROGRESS`, `BLOCKED` y `COMPLETED` solo los fija quien
ejecuta la tarea, nunca se generan al crear.

### Feature y change

```text
planned ──► in-progress ──► completed
   │             │
   └─────────────┴─────────► cancelled
```

Transiciones validas: `planned` -> `in-progress` -> `completed` | `cancelled`. Al crear una
spec nueva el estado inicial es siempre `planned`.

## Valores INVALIDOS comunes

Todos estos valores se rechazan (error de validacion, no se interpretan):

| Valor escrito | Donde aparece | Por que es invalido | Valor permitido que corresponde |
|---------------|---------------|---------------------|---------------------------------|
| `DONE` | task | no existe en el vocabulario | `COMPLETED` |
| `PLANNED` | task | es de feature/change, y en minuscula | `PENDING` |
| `TODO` | task | no existe en el vocabulario | `PENDING` |
| `IN-PROGRESS` | task | guion medio en un vocabulario de guion bajo | `IN_PROGRESS` |
| `CANCELLED` | task | las tasks no se cancelan | ninguno (retirar la task) |
| `Completed` | task, change, feature | casing mixto | `COMPLETED` (task) o `completed` (change/feature) |
| `in_progress` | change, feature | guion bajo en un vocabulario de guion medio | `in-progress` |
| `COMPLETED` / `PENDING` | change, feature | mayusculas en vocabulario de minuscula | `completed` / `planned` |
| `pending` | task | minuscula en vocabulario de mayusculas | `PENDING` |
| `blocked` | change, feature | `BLOCKED` solo existe para tasks | ninguno |

La columna "valor permitido que corresponde" es una ayuda para quien corrige: la
correccion debe respetar el estado real de la spec, no solo hacer pasar la validacion.

## Limite del campo `task` (identificador)

El campo `task` es snake_case y su longitud tiene dos niveles:

| Longitud | Resultado del validador | Motivo |
|----------|-------------------------|--------|
| 1 a 47 | OK | guia estricta del repo: deja espacio al prefijo `NN-` del nombre de archivo |
| 48 a 100 | AVISO | cabe en la plataforma, pero excede la guia; acortar |
| mas de 100 | ERROR | limite duro de la plataforma (`task_code`, sdd-flow-ai v28) |

El nombre de archivo de una task es `NN-accion-componente.yaml`: `NN` de dos digitos
(01-99), kebab-case y, sin la extension, maximo 50 caracteres.

## Como verificar

```bash
bash scripts/validate-specs.sh <directorio-o-archivos>
```

El validador lee los valores permitidos de los schemas de `context/sdd-specs/`, por lo que
este documento y los schemas deben cambiar juntos. La skill `spec-reviewer` ejecuta el
validador y revisa a mano lo que el script no puede comprobar.
