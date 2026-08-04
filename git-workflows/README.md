# GitHub Workflows Templates

Este directorio contiene plantillas de workflows de GitHub Actions reutilizables para proyectos que implementan agentes de Claude.

## 📋 Propósito

El directorio `git-workflows/` almacena workflows de GitHub Actions que pueden ser sincronizados a otros repositorios. Esto permite:

- **Reutilización**: Comparte workflows comunes entre múltiples proyectos
- **Consistencia**: Mantén estándares de CI/CD uniformes
- **Centralización**: Un solo lugar para mantener workflows actualizados
- **Separación**: Mantiene `.github/` específico para este repositorio

## 🔄 Workflows Disponibles

### code-review-backend-py.yml

Workflow de revisión de código automatizada usando Claude AI para proyectos Python backend.

**Características:**
- Revisa PRs automáticamente usando el agente `reviewer-backend-py`
- Valida arquitectura, calidad de código y testing
- Aprueba o solicita cambios basado en criterios de calidad
- Bloquea merge si no cumple con los estándares

**Triggers:**
- Pull requests en archivos `src/**/*.py` y `tests/**/*.py`
- Eventos: opened, synchronize, reopened

**Requisitos:**
- Secret: `ANTHROPIC_API_KEY`
- Permisos: write para pull-requests e issues

**Documentación completa:**
- [Architecture](../docs/CODE_REVIEW_AGENT_ARCHITECTURE.md)
- [Deployment](../docs/CI_CD_GUIDE_TO_CODE_REVIEW_AGENT.md)

### python/code-review-alembic-backend-py.yml

Workflow de revisión de código para proyectos **job de migraciones Alembic** (estilo `db-migrator-job`), usando el agente `reviewer-alembic-backend-py`.

**Características:**
- Aplica un estándar de calidad distinto por directorio en una sola revisión:
  - `alembic/versions/` → integridad de la cadena de revisiones y seguridad DDL, **sin pruebas unitarias**
  - `scripts/` → seguridad y documentación mínima, **sin pruebas unitarias**
  - `src/` → Clean Architecture y pruebas unitarias (>90% en archivos cambiados)
- Thresholds por defecto: arquitectura 8, calidad 8, testing 8

**Triggers:**
- Pull requests en `alembic/**`, `alembic.ini`, `src/**`, `scripts/**`, `tests/**`, `main.py`, `entrypoint.sh`, `Dockerfile`, `requirements.txt`, `Pipfile`
- Eventos: opened, synchronize, reopened

**Requisitos:**
- Secrets: `ANTHROPIC_API_KEY`, `AGENTS_GITHUB_TOKEN`
- Permisos: write para pull-requests e issues

**⚠️ Importante:** este workflow **reemplaza** a `code-review-backend-py.yml` en un repositorio de migraciones. El agente ya cubre `src/`, `scripts/` y `tests/`, así que mantener ambos activos genera dos revisiones y dos quality gates sobre el mismo PR.

## 🚀 Instalación

### Opción 1: Script de Sincronización (Recomendada)

Usa el script interactivo para instalar workflows:

```bash
# Desde el repositorio de destino
./scripts/sync-workflows.sh

# O especificando un repositorio custom
./scripts/sync-workflows.sh https://github.com/tu-usuario/tu-repo.git

# O usando variable de entorno
WORKFLOWS_REPO=https://github.com/tu-usuario/tu-repo.git ./scripts/sync-workflows.sh
```

El script te permitirá:
1. Ver todos los workflows disponibles
2. Seleccionar cuáles instalar (todos o personalizado)
3. Copiarlos automáticamente a `.github/workflows/`
4. Ver qué secrets necesitas configurar

### Opción 2: Copia Manual

```bash
# Copiar un workflow específico
cp git-workflows/code-review-backend-py.yml .github/workflows/

# O copiar todos los workflows
cp git-workflows/*.yml .github/workflows/
```

### Opción 3: Git Remote (Para equipos)

Si trabajas en un equipo, puedes clonar este repo como submódulo:

```bash
git submodule add https://github.com/Grinest/agents.git .claude-workflows
ln -s .claude-workflows/git-workflows git-workflows
```

## ⚙️ Configuración Post-Instalación

Después de instalar un workflow:

### 1. Configurar Secrets

Cada workflow puede requerir secrets específicos. Ve a:
```
Repositorio → Settings → Secrets and variables → Actions → New repository secret
```

Para `code-review-backend-py.yml`:
- `ANTHROPIC_API_KEY`: Tu API key de Anthropic

### 2. Configurar Permisos

Ve a: `Settings → Actions → General → Workflow permissions`

Selecciona:
- ✅ Read and write permissions
- ✅ Allow GitHub Actions to create and approve pull requests

### 3. Personalizar (Opcional)

Puedes editar los workflows copiados en `.github/workflows/` según las necesidades específicas de tu proyecto:

- Cambiar paths que activan el workflow
- Ajustar timeouts
- Modificar modelos de Claude
- Agregar pasos adicionales

## 📁 Estructura de Directorios

```
tu-proyecto/
├── .github/
│   └── workflows/              # Workflows activos (gitignored por default)
│       └── code-review-backend-py.yml  # Copiado desde git-workflows/
├── git-workflows/              # Plantillas (puede ser sincronizado)
│   ├── README.md
│   └── code-review-backend-py.yml
└── scripts/
    └── sync-workflows.sh       # Script de sincronización
```

## 🔄 Actualización de Workflows

Para actualizar workflows ya instalados:

```bash
# Opción 1: Re-ejecutar el script de sync
./scripts/sync-workflows.sh

# Opción 2: Copiar manualmente las versiones nuevas
cp git-workflows/code-review-backend-py.yml .github/workflows/
```

**Nota**: Si personalizaste workflows en `.github/workflows/`, revisa los cambios antes de sobrescribir.

## 🛠️ Desarrollo de Nuevos Workflows

Si quieres crear workflows reutilizables:

### 1. Crear el Workflow

Crea el archivo en `git-workflows/`:

```bash
touch git-workflows/mi-nuevo-workflow.yml
```

### 2. Seguir Mejores Prácticas

- Usa nombres descriptivos
- Documenta triggers y requisitos
- Lista todos los secrets necesarios en comentarios
- Incluye timeout razonables
- Usa variables de entorno cuando sea posible

### 3. Probar Localmente

```bash
# Copiar a .github/workflows/ para probar
cp git-workflows/mi-nuevo-workflow.yml .github/workflows/

# Hacer commit y push para probar en GitHub Actions
git add .github/workflows/mi-nuevo-workflow.yml
git commit -m "test: nuevo workflow"
git push
```

### 4. Documentar

Actualiza este README con:
- Descripción del workflow
- Requisitos (secrets, permisos)
- Triggers
- Ejemplos de uso

## ❓ FAQ

### ¿Por qué no usar `.github/workflows/` directamente?

`.github/workflows/` es específico del repositorio actual. Al usar `git-workflows/`:
- Puedes sincronizar workflows a múltiples proyectos
- Mantienes `.github/` limpio y específico
- Facilitas la gestión centralizada de workflows

### ¿Debo versionar `.github/workflows/` en git?

Depende de tu caso de uso:

**SI** (agregar a git):
- Workflows son específicos de este proyecto
- Quieres historial de cambios
- No planeas sincronizar desde otro repo

**NO** (agregar a .gitignore):
- Sincronizas workflows desde repo central
- Workflows son compartidos entre proyectos
- Prefieres gestión centralizada

Ejemplo `.gitignore`:
```bash
# Ignorar workflows sincronizados
.github/workflows/code-review-*.yml
```

### ¿Cómo actualizo el script de sincronización?

El script `sync-workflows.sh` está en `scripts/`. Para actualizarlo:

```bash
# Si sincronizas desde un repo remoto, re-ejecuta:
./scripts/sync-workflows.sh

# El script se auto-actualiza si está en el repo remoto
```

### ¿Puedo usar workflows de otro repositorio?

Sí, especifica la URL del repo:

```bash
./scripts/sync-workflows.sh https://github.com/otro-usuario/workflows.git
```

El repo debe tener la estructura:
```
repo/
├── git-workflows/
│   └── *.yml
└── scripts/
    └── sync-workflows.sh
```

## 🤝 Contribuir

Para contribuir nuevos workflows:

1. Crea el workflow en `git-workflows/`
2. Pruébalo en un proyecto real
3. Documéntalo en este README
4. Crea un PR con descripción detallada

## 📚 Recursos

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)
- [Claude API Documentation](https://docs.anthropic.com/)
- [Repository Documentation](../README.md)

## 📄 Licencia

Los workflows en este directorio están disponibles bajo la misma licencia que el proyecto principal.

---

**Nota**: Este directorio es parte del proyecto [claude-agents](https://github.com/Grinest/agents) y está diseñado para facilitar la adopción de agentes de Claude en tus proyectos.