# General Plugin

Language-agnostic agents that work across all technologies and programming languages.

## Available Agents

### Architecture & Design

- **architect.md**: Software Architecture Agent (v2.0) that accepts a `feature.yaml` (product specification) as primary input and generates a `technical.yaml` (technical specification), `technical-proposal.md`, and `infrastructure-proposal.md` as outputs. Includes validation of input completeness, missing data flow, conditional diagram generation (ER, sequence, infrastructure AWS/GCP), solution alternatives with decision matrix, and three-point time estimation. Never generates implementation code.
- **data-architect.md**: PostgreSQL Data Architecture specialist for database design, tuple layout and padding optimization, indexing strategies, UTC timestamp integrity, data contracts, and zero-downtime safe DDL migrations.
- **qa-data-architect.md**: Specialized QA auditor for PostgreSQL database migrations and schemas, verifying lock timeouts, foreign key indexes, tuple padding, UTC timezone integrity, Row-Level Security (RLS), and naming conventions.

### Product Specification

- **product.md**: Product Specification Agent that analyzes documents, images, and business context to generate standardized `feature.yaml` files. The generated specification serves as a Definition of Ready (DoR) for engineering teams, ensuring all product requirements are clear, complete, and actionable before implementation begins.

## Available Skills

### data-architecture-postgre
Estándares de arquitectura de datos en PostgreSQL para diseño de tablas, orden y alineación física de columnas, tipos óptimos, índices, manejo temporal UTC y migraciones DDL sin downtime.

### data-quality-governance
Estándares de calidad y gobernanza de datos: contratos de datos, suites de validación declarativa (Great Expectations / SodaCL), linaje de datos, clasificación/enmascaramiento PII y SLAs de frescura.

### github-workflow
Estándares y templates para el flujo de trabajo en GitHub, incluyendo mensajes de commit, Pull Requests y Releases.

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
