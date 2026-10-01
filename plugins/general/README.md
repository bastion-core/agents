# General Plugin

Language-agnostic agents that work across all technologies and programming languages.

## Available Agents

### Architecture & Design

- **architect.md**: Software Architecture Agent (v2.0) that accepts a `feature.yaml` (product specification) as primary input and generates a `technical.yaml` (technical specification), `technical-proposal.md`, and `infrastructure-proposal.md` as outputs. Includes validation of input completeness, missing data flow, conditional diagram generation (ER, sequence, infrastructure AWS/GCP), solution alternatives with decision matrix, and three-point time estimation. Never generates implementation code.

### Product Specification

- **product.md**: Product Specification Agent that analyzes documents, images, and business context to generate standardized `feature.yaml` files. The generated specification serves as a Definition of Ready (DoR) for engineering teams, ensuring all product requirements are clear, complete, and actionable before implementation begins.

## Available Skills

- **spec-reviewer**: Reviews SDD specs (`feature.yaml`, `change.yaml`, `technical.yaml` and `tasks/*.yaml`). Runs the validator bundled with the skill (`scripts/validate_specs.py` plus `schemas/`) and manually checks what the script cannot (change/task coherence, `depends_on`, verifiable `acceptance`). It rejects any `status` outside the closed vocabulary defined in `references/status-vocabulary.md` (the skill's copy of `context/sdd-specs/status-vocabulary.md`) and reports the value with the allowed ones.

## Validating specs in a project repo

The `spec-reviewer` skill ships its own validator, so it works in any project (for example an SDD registry repo) without copying `scripts/` or `context/` from this repository:

```
skills/spec-reviewer/
  SKILL.md
  scripts/validate_specs.py     # validator (needs python3 + PyYAML)
  schemas/{feature,change,technical,task}.schema.yaml
  references/status-vocabulary.md
```

Run it from any directory:

```bash
python3 -m pip install --user pyyaml
python3 <skill-dir>/scripts/validate_specs.py features/
```

Where `<skill-dir>` is:

- Claude Code, installed plugin: `~/.claude/plugins/cache/seven-samurai-agents/general/<version>/skills/spec-reviewer` (the skill itself receives its base directory from the environment; with a custom config dir it lives under that dir instead).
- Gemini: `.gemini/skills/spec-reviewer` relative to the project.

Schemas are resolved in this order: `--schemas DIR`, `SDD_SCHEMAS_DIR`, the bundled `schemas/`, then `context/sdd-specs/` (repo mode).

Exit codes: `0` valid (warnings do not fail), `1` invalid specs, `2` environment or usage error (missing PyYAML, schemas not found, bad arguments). Missing PyYAML prints the install command.

### CI example for a registry repo

Pin the version by checking out this repository at a commit SHA (or tag) that contains the plugin version you want, and run the bundled validator against `features/`:

```yaml
jobs:
  validate-specs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - run: python3 -m pip install pyyaml

      - name: Fetch spec-reviewer (pinned)
        uses: actions/checkout@v4
        with:
          repository: bastion-core/agents
          ref: <commit-sha-or-tag>   # pin: bump deliberately, e.g. the commit that released general 1.11.0
          path: .agents
          sparse-checkout: plugins/general/skills/spec-reviewer

      - name: Validate specs
        run: python3 .agents/plugins/general/skills/spec-reviewer/scripts/validate_specs.py features/
```

If the plugin is installed on the runner instead (`claude plugin install general@seven-samurai-agents`), point to `~/.claude/plugins/cache/seven-samurai-agents/general/<version>/skills/spec-reviewer/scripts/validate_specs.py` and fix `<version>` explicitly rather than using a glob.

### Keeping the bundled copies in sync (maintainers)

`scripts/validate_specs.py` and `context/sdd-specs/*.schema.yaml` are the single source of truth. After changing them run `scripts/sync-spec-validator.sh` to refresh the copies in this skill and in the Gemini skill; CI runs `scripts/sync-spec-validator.sh --check` and fails on drift.

## Usage

General agents are technology-agnostic and can be used in any project:

```bash
# Install the architect agent
./scripts/sync-agents.sh
# Select: architect
```

These agents complement technology-specific agents by providing high-level guidance and planning before diving into implementation details.

## When to Use General Agents

Use general plugin agents when:
- Generating technical specifications from a feature.yaml (product specification)
- Planning system architecture before implementation
- Making high-level technical decisions
- Designing system structure and component interactions
- Evaluating architectural patterns and approaches
- Generating product specifications from requirements, documents, or mockups
- Need guidance that applies across programming languages

## Organization

General agents are kept separate from technology-specific plugins because:
- They don't depend on specific programming languages or frameworks
- They can be used alongside any technology plugin
- They focus on conceptual and architectural concerns
- They provide value at the planning and design phases
