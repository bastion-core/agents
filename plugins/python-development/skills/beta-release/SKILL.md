---
name: beta-release
description: Publica o actualiza una prerelease beta (tag+release) de una librería Python compartida desde una rama feature, y actualiza el pin en un consumidor (requirements.txt + pip install + docker).
model: inherit
color: purple
allowed-tools: Read, Bash, Grep, Glob
---

# Beta Release Skill

Este skill automatiza el flujo de trabajo de "no hacer PR a main, sino publicar
prereleases beta desde la rama de trabajo" usado para librerías compartidas
(`common-structure-library` y análogas: `telemetry-kit-library`,
`voltop-bi-library`, `voltop-python-logger-library`, `ai-toolkit-library`,
etc.). Existen dos scripts, en `scripts/` junto a este archivo:

- `publish-beta.sh` — se corre en el repo de la librería, en la rama de
  feature, con los cambios ya commiteados.
- `bump-consumer.sh` — se corre en el repo consumidor (api, job, etc.) para
  apuntar `requirements.txt` a la nueva beta y reinstalar.

**No calcules manualmente el número de beta ni edites tags/releases a mano.**
La lógica de "cuál es el beta actual, hay que borrarlo, subir el número" es
mecánica y propensa a error si se hace por razonamiento en cada turno — para
eso están los scripts.

## PROCEDIMIENTO: publicar/actualizar una beta de la librería

1. Verifica que los cambios relevantes ya estén commiteados en la rama de
   feature (usa el skill `github-workflow` para el formato del mensaje de
   commit si aún no se ha commiteado).
2. Corre desde la raíz del repo de la librería:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/beta-release/scripts/publish-beta.sh"
   ```
3. El script:
   - Se niega a correr en `main`/`master` o con el working tree sucio.
   - Corre los tests (`make test` si existe ese target, si no `pytest`) y
     aborta si fallan.
   - Hace `git push` de la rama actual.
   - Detecta la versión del paquete (literal `VERSION =` en `setup.py`, o
     `__version__` en un `_version.py` como fallback).
   - Si ya existe un tag `v.<version>.beta.<n>` para esa versión, borra ese
     release+tag (para no ensuciar el registro) y crea `beta.<n+1>`; si no
     existe ninguno, crea `beta.1`.
   - Publica el tag y crea el GitHub Release como prerelease.
4. Reporta al usuario la URL del release que quedó publicado (el script la
   imprime).

## PROCEDIMIENTO: actualizar un consumidor con la nueva beta

Solo cuando el usuario lo pida explícitamente (no es automático tras publicar
la beta, porque no todos los consumidores necesitan actualizarse a la vez).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/beta-release/scripts/bump-consumer.sh" <nuevo-tag> \
  --package <nombre-paquete-en-la-url-git>   # default: common-structure-library
  [--service <servicio-docker-compose>]      # solo si aplica (ej. api, no jobs)
```

El script reemplaza únicamente la línea de `requirements.txt` que pinea
`github.com/<org>/<package>.git@<tag>` (cuidado: paquetes con nombres
parecidos, ej. `voltop-serverless-common-structure-library`, no se confunden
porque el match exige un `/` justo antes del nombre del paquete), corre
`pip install -r requirements.txt` (usa `.venv/bin/pip3` si existe), y solo
reconstruye Docker si se pasó `--service`.

## Notas

- El formato de tag estándar es `v.<version>.beta.<n>` (con punto antes de
  "beta"). El historial de tags en estos repos está mezclado con otros
  formatos (`-beta.N`, sin prefijo `v`, etc.) — el script no intenta migrar
  el pasado, solo estandariza hacia adelante.
- Requiere `gh` autenticado (`gh auth status`) con permisos sobre el repo de
  la librería.
- Verificado de extremo a extremo (creación, bump con borrado del tag
  anterior, y validaciones de rama/working-tree) contra un repositorio real
  descartable antes de integrarse a este plugin.
