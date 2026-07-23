---
name: beta-release
description: Publica o actualiza una prerelease beta de una librería Python compartida (common-structure-library y similares) desde una rama de feature, y actualiza el pin en un proyecto consumidor (requirements.txt + pip install + docker build opcional).
---

# Beta Release Skill

Este skill automatiza el flujo de "no hacer PR a main, sino publicar
prereleases beta desde la rama de trabajo" usado para librerías compartidas
(`common-structure-library` y análogas: `telemetry-kit-library`,
`voltop-bi-library`, `voltop-python-logger-library`, `ai-toolkit-library`,
etc.). Trae dos scripts en `scripts/`:

- `scripts/publish-beta.sh` — se corre en el repo de la librería, en la rama
  de feature, con los cambios ya commiteados.
- `scripts/bump-consumer.sh` — se corre en el repo consumidor (api, job, etc.)
  para apuntar `requirements.txt` a la nueva beta y reinstalar.

**No calcules manualmente el número de beta ni edites tags/releases a mano.**
Esa lógica ("cuál es el beta actual, hay que borrarlo, subir el número") es
mecánica y propensa a error si se hace por razonamiento en cada turno — para
eso están los scripts.

## Instrucciones de uso

### 1. Publicar/actualizar una beta de la librería

1. Verifica que los cambios ya estén commiteados en la rama de feature (usa
   el skill `github-workflow` para el formato del commit si aún no se ha
   commiteado).
2. Corre desde la raíz del repo de la librería:
   ```bash
   bash ~/.gemini/skills/beta-release/scripts/publish-beta.sh
   ```
3. El script se niega a correr en `main`/`master` o con el working tree
   sucio, corre los tests (`make test` si existe ese target, si no
   `pytest`), hace `git push` de la rama, detecta la versión (`VERSION =`
   literal en `setup.py`, o `__version__` en `_version.py` como fallback),
   borra el tag/release beta anterior para esa versión si existe y sube el
   número, o crea `beta.1` si es la primera vez. Publica el tag y crea el
   GitHub Release como prerelease.
4. Reporta al usuario la URL del release que imprime el script.

### 2. Actualizar un consumidor con la nueva beta

Solo cuando el usuario lo pida explícitamente — no es automático tras
publicar la beta, porque no todos los consumidores se actualizan a la vez.

```bash
bash ~/.gemini/skills/beta-release/scripts/bump-consumer.sh <nuevo-tag> \
  --package <nombre-paquete-en-la-url-git>   # default: common-structure-library
  [--service <servicio-docker-compose>]      # solo si aplica (ej. api, no jobs)
```

Reemplaza únicamente la línea de `requirements.txt` que pinea
`github.com/<org>/<package>.git@<tag>` (paquetes con nombres parecidos, ej.
`voltop-serverless-common-structure-library`, no se confunden porque el
match exige un `/` justo antes del nombre del paquete), corre
`pip install -r requirements.txt` (usa `.venv/bin/pip3` si existe), y solo
reconstruye Docker si se pasó `--service`.

## Notas

- El formato de tag estándar es `v.<version>.beta.<n>` (con punto antes de
  "beta"). El historial de tags en estos repos está mezclado con otros
  formatos — el script no migra el pasado, solo estandariza hacia adelante.
- Requiere `gh` autenticado (`gh auth status`) con permisos sobre el repo de
  la librería.
