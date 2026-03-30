# Claude Agents Scripts

Utility scripts for Claude Code agents and workflows management.

## 📦 Available Scripts

### validate-agents.sh

Validates the structure and format of agent files in the repository.

**Purpose**: Ensure all agents meet quality standards before publishing.

**Usage**:
```bash
./scripts/validate-agents.sh
```

**What it validates**:
- ✅ Plugin directory structure exists
- ✅ Agent files have YAML frontmatter
- ✅ Required fields: name, description, model, color
- ✅ Name follows kebab-case convention
- ✅ File encoding is UTF-8
- ✅ No excessively long lines

**Output**:
- Passes: ✓ Green checkmarks
- Fails: ✗ Red errors
- Warnings: ⚠ Yellow warnings
- Summary report with counts

**Used in CI/CD**: This script runs automatically in GitHub Actions on pull requests.

---

### sync-workflows.sh

Synchronizes GitHub Actions workflows from this repository to your projects.

**Purpose**: Install reusable workflows for automated code review.

**Usage**:
```bash
# Interactive mode
./scripts/sync-workflows.sh

# From remote repository
./scripts/sync-workflows.sh https://github.com/your-org/workflows.git

# With environment variable
WORKFLOWS_REPO=https://github.com/company/workflows.git ./scripts/sync-workflows.sh
```

**What it does**:
1. Lists available workflows (Python backend review, Flutter app review, etc.)
2. Lets you select which workflows to install
3. Copies workflows to `.github/workflows/` in your project
4. Shows configuration instructions (secrets, permissions)

**Available workflows**:
- `code-review-backend-py.yml` - Automated Python backend PR reviews
- `code-review-flutter-app.yml` - Automated Flutter app PR reviews

---

### gemini/setup-gemini.sh

Automatiza la configuracion de Service Account Impersonation en GCP para usar Gemini CLI con Vertex AI sin re-autenticarse diariamente.

**Purpose**: Crear un Service Account dedicado por desarrollador, asignar permisos de Vertex AI, configurar impersonation y generar ADC. Se ejecuta una sola vez.

**Prerequisites**:
- gcloud CLI instalado y autenticado (`gcloud auth login`)
- Proyecto GCP con API de Vertex AI habilitada

**Usage**:
```bash
# Setup con defaults (proyecto: still-smithy-407213, region: global, email y dev-name del usuario activo)
./scripts/gemini/setup-gemini.sh

# Setup con parametros explicitos
./scripts/gemini/setup-gemini.sh --project my-project --email dev@empresa.com --dev-name juan

# Previsualizar comandos sin ejecutar
./scripts/gemini/setup-gemini.sh --dry-run

# Revertir toda la configuracion
./scripts/gemini/setup-gemini.sh --cleanup --dev-name juan

# Previsualizar cleanup
./scripts/gemini/setup-gemini.sh --cleanup --dry-run --dev-name juan
```

**Flags**:

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--project` | `-p` | `still-smithy-407213` | ID del proyecto GCP |
| `--email` | `-e` | Email del usuario activo | Email del desarrollador |
| `--dev-name` | `-n` | Username del email | Identificador para el Service Account |
| `--region` | `-r` | `global` | Region de Vertex AI |
| `--dry-run` | `-d` | `false` | Previsualizar sin ejecutar |
| `--cleanup` | `-c` | `false` | Revertir configuracion |
| `--help` | `-h` | - | Mostrar ayuda |

**What it does (setup)**:
1. Valida prerequisitos (gcloud, autenticacion, proyecto, API de Vertex AI, permisos IAM)
2. Crea Service Account `gemini-{dev-name}@{project}.iam.gserviceaccount.com`
3. Asigna rol `roles/aiplatform.user` al Service Account
4. Otorga `roles/iam.serviceAccountTokenCreator` al usuario sobre el SA
5. Configura `gcloud config set auth/impersonate_service_account`
6. Genera Application Default Credentials con impersonation
7. Verifica acceso a Vertex AI (usa `us-central1` si la region es `global`)

**What it does (cleanup)**: Revierte en orden inverso (unset config, revocar permisos, eliminar SA).

**Idempotent**: El script verifica la existencia de cada recurso antes de crearlo. Se puede re-ejecutar sin errores.

**Sin permisos de IAM Admin**: Si el desarrollador no tiene permisos para crear Service Accounts o asignar roles IAM (`resourcemanager.projects.setIamPolicy`), el script detecta esto automaticamente y muestra los comandos exactos que el admin de GCP debe ejecutar. Despues de que el admin ejecute los comandos, el desarrollador vuelve a correr el script y los pasos 1-3 se saltan por idempotencia.

---

### gemini/sync-agents.sh

Sincroniza los subagents de Gemini CLI a la configuracion global del usuario.

**Purpose**: Habilitar los subagents (`@product`, `@architect`, etc.) globalmente para invocarlos desde cualquier repositorio.

**Usage**:
```bash
./scripts/gemini/sync-agents.sh
```

**What it does**:
1. Crea el directorio `~/.gemini/agents/` si no existe
2. Copia los agentes de `gemini/spec-generator/.gemini/agents/` a la configuracion global
3. Copia archivos de soporte (convenciones, esquemas, ejemplos)
4. Configura `~/.gemini/GEMINI.md` con las instrucciones de orquestacion

**Re-run**: Ejecutar de nuevo para actualizar los agentes despues de cambios en el repositorio.

---

## 🗑️ Removed Scripts

### ~~sync-agents.sh~~ (REMOVED)

**Status**: ❌ Removed in favor of modern plugin system

**Migration**: Use Claude Code's built-in plugin system instead:

```bash
# Old way (removed)
./scripts/sync-agents.sh

# New way (2026)
/plugin marketplace add Grinest/agents
/plugin install python-development@agents
```

**See**: [MIGRATION.md](../MIGRATION.md) for complete migration guide.

---

## 🏗️ Plugin System (Recommended)

As of 2026, agent installation uses Claude Code's native plugin system:

### Installation
```bash
# Add marketplace
/plugin marketplace add Grinest/agents

# Install plugins
/plugin install general@agents
/plugin install python-development@agents
/plugin install flutter-development@agents
```

### Benefits over bash scripts
- ✅ Version control and auto-updates
- ✅ One-command installation
- ✅ Namespace isolation
- ✅ Team configuration via `.claude/settings.json`
- ✅ No manual file copying

### Documentation
- [Plugin System Guide](./../.claude-plugin/README.md)
- [Migration Guide](../MIGRATION.md)
- [Main README](../README.md)

---

## 🛠️ Development

### Running Validation Locally

Before submitting a PR, validate your changes:

```bash
./scripts/validate-agents.sh
```

Fix any errors or warnings before committing.

### Adding New Workflows

1. Create workflow in `git-workflows/[technology]/`
2. Add documentation in `git-workflows/README.md`
3. Test workflow in a sample project
4. Update `sync-workflows.sh` if needed

### CI/CD Integration

The validation script runs automatically in GitHub Actions:

```yaml
# .github/workflows/validate-agents.yml
- name: Validate agents
  run: ./scripts/validate-agents.sh
```

This ensures all agents meet quality standards before merging.

---

## 📚 Additional Resources

- [Main README](../README.md) - Complete project documentation
- [Plugin README](../plugins/README.md) - Plugin architecture guide
- [Workflows README](../git-workflows/README.md) - GitHub Actions workflows
- [Migration Guide](../MIGRATION.md) - Migrate from bash scripts to plugins

---

## 🐛 Troubleshooting

### Validation fails on valid agent

Check that your agent file has:
- Proper YAML frontmatter with `---` delimiters
- All required fields: name, description, model, color
- Valid model value: `inherit`, `sonnet`, `opus`, or `haiku`
- kebab-case name format

### Workflow sync script doesn't find workflows

Ensure:
- You're in the repository root
- `git-workflows/` directory exists
- Workflow files have `.yml` extension

### Permission denied when running scripts

Make scripts executable:
```bash
chmod +x scripts/validate-agents.sh
chmod +x scripts/sync-workflows.sh
chmod +x scripts/gemini/setup-gemini.sh
chmod +x scripts/gemini/sync-agents.sh
```

### setup-gemini.sh shows "Share the following commands with your GCP admin"

El desarrollador no tiene permisos de IAM Admin. El script muestra los comandos que el admin debe ejecutar. Copiar el bloque completo y enviarselo al admin. Despues de que el admin lo ejecute, correr el script de nuevo:
```bash
./scripts/gemini/setup-gemini.sh --dev-name your-name
```
Los pasos 1-3 se saltaran (ya configurados por el admin) y solo se ejecutaran los pasos 4-7.

### setup-gemini.sh fails at "Vertex AI API not enabled"

Enable the API first:
```bash
gcloud services enable aiplatform.googleapis.com --project=YOUR_PROJECT_ID
```

### setup-gemini.sh fails at Step 6 with "404 Not Found"

La region configurada no soporta el endpoint de Vertex AI para listar modelos. El default `global` se maneja automaticamente (usa `us-central1` para verificacion). Si usas otra region, verificar que sea valida para Vertex AI.

### Reverting setup-gemini.sh configuration

```bash
./scripts/gemini/setup-gemini.sh --cleanup --dev-name your-name
```

---

## 📄 License

MIT License - See [LICENSE](../LICENSE) for details.
