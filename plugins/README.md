# Plugin System

This directory contains all claude-agents organized in a plugin-based architecture. Each plugin represents a technology domain or ecosystem with its own collection of agents and skills.

## Architecture

The plugin system separates agents into two categories:

- **Agents**: Instruction sets and personality configurations for specialized tasks (stored as `.md` files in `agents/` subdirectories)
- **Skills**: Executable capabilities with tools and functions (stored as `skills/<skill-name>/SKILL.md` directories)

## Directory Structure

```
plugins/
├── general/                    # Language-agnostic agents
│   ├── README.md
│   └── agents/
│       └── architect.md
├── python-development/         # Python ecosystem
│   ├── README.md
│   ├── agents/
│   │   ├── backend-py.md
│   │   ├── qa-backend-py.md
│   │   ├── reviewer-backend-py.md
│   │   └── reviewer-library-py.md
│   └── skills/
│       └── backend-py-celery/
│           └── SKILL.md
└── flutter-development/        # Flutter/Dart ecosystem
    ├── README.md
    └── agents/
        └── reviewer-flutter-app.md
```

## Plugin Conventions

Each plugin follows these conventions:

### 1. Directory Naming
- Use kebab-case: `python-development`, `flutter-development`
- Name should clearly indicate the technology domain
- Suffix with `-development` for broad ecosystems

### 2. Required Files
- `README.md`: Plugin documentation with agent descriptions and usage
- `agents/`: Directory containing agent `.md` files
- `skills/`: Directory containing one subdirectory per skill, each with a `SKILL.md` (if applicable)

### 3. Agent Files
- Use kebab-case: `backend-py.md`, `reviewer-flutter-app.md`
- File name should match agent name
- Must contain valid agent YAML frontmatter
- Stored in `agents/` subdirectory

### 4. Skill Files
- Each skill is a directory: `skills/backend-py-celery/SKILL.md`
- Claude Code only discovers skills in this layout. A flat `skills/<name>.md`
  is copied when the plugin is installed but never loaded.
- Directory name in kebab-case, and must match the `name` in the frontmatter
- Frontmatter carries `name`, `description` and optionally `allowed-tools`.
  `model`, `color` and `argument-hint` are agent-only fields and must not appear
- Any supporting files the skill reads (templates, examples) must live inside the
  skill directory, e.g. `skills/github-workflow/references/`, so they ship with the plugin

## Adding New Plugins

To create a new plugin:

1. **Create directory structure**:
   ```bash
   mkdir -p plugins/your-plugin-name/agents
   mkdir -p plugins/your-plugin-name/skills/your-skill-name  # If needed
   ```

2. **Create README.md**:
   - Document the plugin's purpose
   - List all agents and skills
   - Provide usage examples

3. **Add agents/skills**:
   - Place `.md` files in appropriate subdirectories
   - Ensure valid YAML frontmatter
   - Follow naming conventions

4. **Test discovery**:
   ```bash
   ./scripts/validate-agents.sh
   ./scripts/sync-agents.sh
   ```

## Plugin Organization

### General Plugin
Language-agnostic agents that work across all technologies.

### Technology Plugins
Ecosystem-specific plugins (e.g., `python-development`, `flutter-development`) containing:
- Development agents for building features
- QA agents for testing
- Review agents for code review workflows
- Skills for executable capabilities

## Discovery and Installation

The sync scripts automatically discover all plugins by:
1. Scanning `plugins/` directory
2. Finding `agents/*.md` files and `skills/*/SKILL.md` files
3. Excluding `README.md` files
4. Presenting agents with plugin context: `[plugin-name/type] agent-name`

Example display:
```
[general/agents] architect
[python-development/agents] backend-py
[python-development/skills] backend-py-celery
[flutter-development/agents] reviewer-flutter-app
```

## Benefits

The plugin architecture provides:

- **Modularity**: Easy to add/remove entire technology domains
- **Clarity**: Clear separation between agents and skills
- **Scalability**: Supports unlimited plugins and agents
- **Organization**: Technology-specific grouping
- **Discoverability**: Automatic discovery by sync scripts
- **Maintainability**: Isolated plugin documentation and structure
