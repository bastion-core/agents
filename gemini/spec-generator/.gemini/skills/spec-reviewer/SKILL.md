---
name: spec-reviewer
description: "Revisa specs SDD (feature, change, technical, tasks) con el validador y a mano; rechaza estados fuera de la lista cerrada de status-vocabulary.md."
---

# Spec Reviewer Skill

Revisa especificaciones SDD (`feature.yaml`, `change.yaml`, `technical.yaml` y `tasks/*.yaml`) antes de que se sincronicen con el registry de la plataforma. Combina el validador automatico del repo con una revision manual de lo que un script no puede comprobar.

## Regla estricta: estados como lista cerrada

**RECHAZAR cualquier estado (`status`) que no este en `context/sdd-specs/status-vocabulary.md`**, sin excepciones y sin "interpretar" la intencion. Al rechazar, reportar siempre el archivo, el valor encontrado y los valores permitidos para ese tipo de spec.

| Spec | Valores permitidos (casing exacto) |
|------|------------------------------------|
| `task` | `PENDING`, `IN_PROGRESS`, `COMPLETED`, `BLOCKED` |
| `change` | `planned`, `in-progress`, `completed`, `cancelled` |
| `feature` (opcional) | `planned`, `in-progress`, `completed`, `cancelled` |
| `technical` | no tiene `status` |

- Se mantienen dos vocabularios: tasks en MAYUSCULAS, feature/change en minuscula con guion. No se unifican ni se mezclan.
- `DONE`, `TODO`, `PLANNED` en una task, `CANCELLED` en una task, `IN-PROGRESS` en una task, `in_progress` en un change o `Completed` en cualquier spec son errores, no variantes aceptables.
- Aplica tambien a `change.dependencies.features[].status` (vocabulario de feature).
- No corregir un estado "para que pase": la correccion debe reflejar el estado real. Si no esta claro cual es, preguntar a quien pide la revision.

## Procedimiento

1. **Identificar las specs** a revisar (directorio de la feature/change o archivos indicados). Leer `context/sdd-specs/status-vocabulary.md` y los `*.schema.yaml` correspondientes.
2. **Ejecutar el validador** desde la raiz del repo (requiere PyYAML):

   ```bash
   bash scripts/validate-specs.sh <directorio-o-archivos>
   ```

   Si el repo revisado no contiene el script, usar el de este repo de agentes o aplicar a mano las reglas de esta skill y de los schemas, y decirlo en el informe. El validador verifica campos obligatorios, tipos, `max_length`, enums, estados por tipo con casing exacto, patron del nombre de archivo de las tasks y longitud del campo `task`.
3. **Trasladar al informe** cada `ERROR` y `AVISO` del validador sin suavizarlos. Un `ERROR` bloquea la aprobacion.
4. **Revision manual** de lo que el script no cubre (ver abajo).
5. **Emitir el informe** con el formato de salida.

## Revision manual

- **Coherencia change - tasks**: cada elemento de `scope.in_scope` del change queda cubierto por al menos una task, y ninguna task implementa algo de `out_of_scope`. El campo `feature` coincide entre `feature.yaml`, `change.yaml` y `technical.yaml`, y `change_id` coincide con el directorio en `changes/`.
- **Estados coherentes con el ciclo de vida**: una spec recien generada nace en `planned` (feature/change) y sus tasks en `PENDING`; `IN_PROGRESS`, `BLOCKED` y `COMPLETED` solo aparecen si alguien ya ejecuto trabajo. Una task `BLOCKED` explica el motivo (dependencia externa) en `scope` o notas. Un change `completed` no tiene tasks `PENDING`, `IN_PROGRESS` ni `BLOCKED`.
- **`depends_on` validos**: cada referencia es el campo `task` de otra task del mismo change, sin ciclos ni autodependencias, y el orden de los numeros `NN` es compatible con las dependencias.
- **`acceptance` verificable**: minimo 2 criterios por task, cada uno comprobable con un test o inspeccion objetiva (sin "funciona bien", "es rapido"). Los criterios del change/feature no mencionan tecnologias.
- **Nombres**: `task` en snake_case y coincidente con el archivo sin contador; archivo `NN-accion-componente.yaml` (NN de 2 digitos, maximo 50 caracteres sin extension, maximo 99 tasks por change). El `task` tiene guia de 47 caracteres; el validador avisa de 48 a 100 y falla por encima de 100.
- **Campos fuera de schema**: no hay campos inventados en tasks (`feature`, `title`, `assigned_to`, `repo`, `implementation_steps`, `blocked_reason`, etc.); el motivo de un bloqueo va en `scope`.
- **`assigned_subagent`**: slug `plugin:agent`, sin prosa.
- **Idioma**: contenido descriptivo en espanol y claves en ingles.

## Formato de salida

```text
## Revision de specs SDD

Alcance: <rutas revisadas>
Validador: <exit code, N specs, N errores, N avisos>

### Errores (bloquean)
- <archivo> [campo]: valor `<valor>` no permitido. Permitidos: <lista>. Accion: <correccion>

### Avisos
- <archivo> [campo]: <observacion>

### OK
- <comprobaciones que pasaron>

Veredicto: APROBADA | APROBADA CON AVISOS | RECHAZADA
```

Reglas del veredicto: cualquier error (incluido cualquier estado fuera de la lista cerrada) da `RECHAZADA`; solo avisos da `APROBADA CON AVISOS`; sin hallazgos da `APROBADA`. Los documentos legados bajo `docs/features` pueden generar avisos estructurales y de nombre de archivo (`NN_snake_case`); se reportan sin bloquear, pero los enums y los limites de `task` siguen siendo errores.

## Limites de esta skill

- Revisa y reporta; no modifica specs salvo que quien la invoca lo pida de forma explicita.
- No genera specs: eso lo hacen los agentes `product` (feature/change) y `architect` (technical/tasks).
