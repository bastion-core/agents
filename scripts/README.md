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

### validate-specs.sh

Validates SDD specs (`feature.yaml`, `change.yaml`, `technical.yaml` and `tasks/*.yaml`) against the schemas in `context/sdd-specs/`. It delegates to `validate_specs.py` and only needs Python 3 and PyYAML (`python3 -m pip install --user pyyaml`). The same validator is bundled with the `spec-reviewer` skill (see `sync-spec-validator.sh` below).

**Usage**:
```bash
./scripts/validate-specs.sh <directory-or-files...>
./scripts/validate-specs.sh context/sdd-specs docs/features
python3 -m unittest discover -s scripts/tests -v   # validator tests
```

**What it validates**:
- Required fields, types, `max_length` and enums (`valores_permitidos`, including the `L1: description` format)
- `status` as a closed list per spec type with exact casing: tasks use `PENDING`, `IN_PROGRESS`, `COMPLETED`, `BLOCKED`; feature and change use `planned`, `in-progress`, `completed`, `cancelled`; technical has no status (see `context/sdd-specs/status-vocabulary.md`)
- Task file name pattern `NN-action-component.yaml` (2-digit NN, at most 50 characters without extension)
- Task `task` length: OK up to 47, warning from 48 to 100, error above 100

**Output and exit code**: every finding shows the file, field, value and allowed values, as `ERROR` or `AVISO`. Exit codes: `0` ok (warnings do not fail), `1` invalid specs (any `ERROR`), `2` environment or usage error (missing PyYAML with install instructions, schemas not found, bad arguments). Legacy docs under `docs/features` (free `phase`, `NN_snake_case.yaml` names, older structure) only produce warnings, but enum violations and task limits remain errors.

**Used in CI/CD**: the `validate-specs` job in `.github/workflows/validate-agents.yml` runs the tests, `sync-spec-validator.sh --check` and the validator over `context/sdd-specs` and `docs/features`.

**Schema resolution** (`validate_specs.py`, works from any cwd): `--schemas DIR`, then `SDD_SCHEMAS_DIR`, then a `schemas/` directory next to the script (bundled layout), then `context/sdd-specs/` found by walking up from the script or the cwd (repo mode).

**Using it in another repo** (for example an SDD registry): run the bundled copy from the plugin, no repo files needed.
```bash
python3 -m pip install --user pyyaml
python3 ~/.claude/plugins/cache/seven-samurai-agents/general/<version>/skills/spec-reviewer/scripts/validate_specs.py features/
```
A CI example that pins the version is in `plugins/general/README.md`.

---

### sync-spec-validator.sh

Keeps the validator bundled with the `spec-reviewer` skill identical to the source of truth (`scripts/validate_specs.py`, `context/sdd-specs/{feature,change,technical,task}.schema.yaml` and `status-vocabulary.md`). It copies them into `plugins/general/skills/spec-reviewer/` and `gemini/spec-generator/.gemini/skills/spec-reviewer/` (`scripts/`, `schemas/`, `references/`).

```bash
./scripts/sync-spec-validator.sh           # copy source to both destinations
./scripts/sync-spec-validator.sh --check   # write nothing; exit 1 if any copy differs or is missing
```

Run it after editing the validator or any schema and commit the result. The `validate-specs` CI job runs `--check`, and `scripts/tests/test_packaged_validator.py` also compares the copies with the source.

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

### claude/setup-claude-vertex.sh

Configura Claude Code CLI para consumir los modelos de Anthropic a traves de Google Vertex AI, usando los creditos de GCP en lugar de una suscripcion de Claude.ai.

**Purpose**: Refrescar las Application Default Credentials, escribir las variables de entorno necesarias en el shell rc del usuario (`~/.zshrc` por defecto) y dejar listo Claude Code para apuntar a Vertex AI.

**Prerequisites**:
- gcloud CLI instalado y autenticado (`gcloud auth login`)
- Proyecto GCP con la API de Vertex AI habilitada (`aiplatform.googleapis.com`)
- Claude Code CLI instalado (`claude`) — opcional, solo necesario para validar `/status`

**Usage**:
```bash
# Setup con defaults (proyecto: still-smithy-407213, region: global, shell: ~/.zshrc)
./scripts/claude/setup-claude-vertex.sh

# Setup con parametros explicitos
./scripts/claude/setup-claude-vertex.sh --project my-project --region us-east5

# Usar bash en lugar de zsh
./scripts/claude/setup-claude-vertex.sh --shell-rc ~/.bashrc

# Saltar el login de ADC (si ya esta vigente)
./scripts/claude/setup-claude-vertex.sh --skip-adc

# Previsualizar cambios sin aplicarlos
./scripts/claude/setup-claude-vertex.sh --dry-run

# Revertir la configuracion (elimina solo el bloque administrado por el script)
./scripts/claude/setup-claude-vertex.sh --cleanup
```

**Flags**:

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--project` | `-p` | `still-smithy-407213` | ID del proyecto GCP |
| `--region` | `-r` | `global` | Region de Vertex AI |
| `--shell-rc` | `-s` | `~/.zshrc` | Archivo de configuracion del shell a modificar |
| `--skip-adc` | - | `false` | Omite `gcloud auth application-default login` |
| `--dry-run` | `-d` | `false` | Previsualizar sin ejecutar |
| `--cleanup` | `-c` | `false` | Remueve el bloque de configuracion del shell rc |
| `--help` | `-h` | - | Mostrar ayuda |

**What it does (setup)**:
1. Valida prerequisitos (gcloud, claude, sesion activa, proyecto accesible, API de Vertex AI habilitada)
2. Muestra el `claude /status` actual (si `claude` esta instalado) para confirmar la auth previa
3. Ejecuta `gcloud auth application-default login`, verifica el token ADC y fija el proyecto activo
4. Escribe un bloque delimitado en el shell rc con las variables:
   - `CLAUDE_CODE_USE_VERTEX=1`
   - `ANTHROPIC_VERTEX_PROJECT_ID`
   - `CLOUD_ML_REGION`
   - `ANTHROPIC_DEFAULT_OPUS_MODEL` (`claude-opus-4-7`)
   - `ANTHROPIC_DEFAULT_SONNET_MODEL` (`claude-sonnet-4-6`)
   - `ANTHROPIC_DEFAULT_HAIKU_MODEL` (`claude-haiku-4-5@20251001`)
5. Imprime las instrucciones para `source` el shell rc y validar `/status` dentro de Claude

**What it does (cleanup)**: Remueve unicamente el bloque delimitado por `# >>> claude-code vertex-ai setup >>>` ... `# <<< claude-code vertex-ai setup <<<`, sin tocar el resto del shell rc.

**Idempotent**: Cada ejecucion reemplaza el bloque previo en lugar de duplicarlo, por lo que el script puede correrse multiples veces sin acumular entradas.

**Validacion final**: Despues de aplicar la configuracion (`source ~/.zshrc`), abrir Claude Code y ejecutar `/status`. Debe mostrar:

```
Auth:    Google Vertex AI
Project: still-smithy-407213
Region:  global
Model:   claude-sonnet-4-6
```

---

## 🗑️ Removed Scripts

### ~~sync-agents.sh~~ (REMOVED)

**Status**: ❌ Removed in favor of modern plugin system

**Migration**: Use Claude Code's built-in plugin system instead:

```bash
# Old way (removed)
./scripts/sync-agents.sh

# New way (2026)
/plugin marketplace add bastion-core/agents
/plugin install python-development@seven-samurai-agents
```

**See**: [MIGRATION.md](../MIGRATION.md) for complete migration guide.

---

## 🏗️ Plugin System (Recommended)

As of 2026, agent installation uses Claude Code's native plugin system:

### Installation
```bash
# Add marketplace
/plugin marketplace add bastion-core/agents

# Install plugins
/plugin install general@seven-samurai-agents
/plugin install python-development@seven-samurai-agents
/plugin install flutter-development@seven-samurai-agents
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
chmod +x scripts/claude/setup-claude-vertex.sh
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

### setup-claude-vertex.sh: `/status` sigue mostrando `Claude.ai (subscription)`

Despues de ejecutar el script hay que recargar las variables y reiniciar Claude:
```bash
source ~/.zshrc
# Cerrar la sesion activa de Claude y volver a abrir
claude
/status
```
Si persiste, verifica que las variables se exportaron en la sesion actual:
```bash
echo $CLAUDE_CODE_USE_VERTEX $ANTHROPIC_VERTEX_PROJECT_ID $CLOUD_ML_REGION
```

### setup-claude-vertex.sh: error `PERMISSION_DENIED` al llamar a Vertex AI

Verifica que tu cuenta tenga el rol `roles/aiplatform.user` en el proyecto y que el ADC token este vigente:
```bash
gcloud auth application-default print-access-token
```
Si el token falla, vuelve a correr el script sin `--skip-adc`.

### Reverting setup-claude-vertex.sh configuration

```bash
./scripts/claude/setup-claude-vertex.sh --cleanup
source ~/.zshrc
```
Esto remueve solo el bloque agregado por el script; el resto de tu shell rc queda intacto.

---

## 📄 License

MIT License - See [LICENSE](../LICENSE) for details.
