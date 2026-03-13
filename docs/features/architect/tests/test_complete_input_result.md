# Test Result: Complete Feature YAML Input Validation

**Test Spec**: `docs/features/architect/tasks/11_test_complete_feature_yaml.yaml`
**Agent Prompt**: `plugins/general/agents/architect.md`
**Test Input**: `docs/features/product/feature.yaml`
**Date**: 2026-03-13
**Tester**: Automated prompt validation (read-only)
**Agent Version**: v2.0

---

## Summary

| # | Check | Result | Justification |
|---|-------|--------|---------------|
| 1 | feature.yaml defined as primary mandatory input | PASS | See details below |
| 2 | Extraction mapping for all feature.yaml fields | PASS | See details below |
| 3 | Validation checklist with criteria per field | PASS | See details below |
| 4 | technical.yaml output template with ALL fields | PASS | See details below |
| 5 | Conditional fields only included when applicable | PASS | See details below |
| 6 | technical-proposal.md with 2-3 alternatives and decision matrix | PASS | See details below |
| 7 | infrastructure-proposal.md with AWS/GCP proposals and comparison matrix | PASS | See details below |
| 8 | Uses Write tool to save output files | PASS | See details below |
| 9 | Explicitly states NEVER generate implementation code | PASS | See details below |
| 10 | Uses Mermaid syntax for all diagrams | PASS | See details below |

**Overall Result**: 10/10 PASS

---

## Detailed Validation

### Check 1: feature.yaml defined as primary mandatory input

**Result**: PASS

The agent prompt contains a dedicated section titled **"Primary Input: feature.yaml"** (line 48) that explicitly states:

> "Tu insumo principal de entrada es un archivo feature.yaml generado por el agente product."

This section clearly defines feature.yaml as the primary and mandatory input for the agent. The pipeline section (line 69) also begins with "Leer feature.yaml" as step 1, reinforcing it as the entry point for the entire agent workflow. Additionally, the validation phase (line 90) and decision gate (line 113) both operate exclusively on the feature.yaml content, confirming it as the sole mandatory input.

---

### Check 2: Extraction mapping for all feature.yaml fields

**Result**: PASS

The agent prompt includes a complete mapping table (lines 52-61) that maps each feature.yaml field to its architectural analysis purpose:

| feature.yaml Field | Mapped Architectural Purpose |
|---------------------|------------------------------|
| `feature` | Defines the output technical.yaml file name |
| `description` | Informs technical scope and involved components |
| `acceptance_criteria` | Defines the technical scope the architecture must support |
| `business_rules` | Directly impacts architectural decisions (limits, validations, permissions) |
| `inputs` | Defines API contracts, validations, and request schemas |
| `outputs` | Defines response schemas, error codes, and formats |
| `tests_scope` | Informs testing strategy and flows to cover |

All seven fields from the feature.yaml specification are mapped. The reading procedure (lines 63-67) also describes the four-step process: (1) user provides path, (2) use Read tool, (3) extract and map each field, (4) optionally analyze codebase.

---

### Check 3: Validation checklist with criteria per field

**Result**: PASS

The agent prompt contains a full **"Checklist de Validacion"** table (lines 96-104) with specific validation criteria for each field:

| Field | Validation Criterion | Possible States |
|-------|---------------------|-----------------|
| `feature` | Has a clear snake_case name | missing / valid |
| `description` | Identifies user role, action, and functional objective | missing / incomplete / valid |
| `acceptance_criteria` | At least 3 verifiable criteria defining technical scope | missing / incomplete / ambiguous / valid |
| `business_rules` | Concrete rules with values, limits, or restrictions impacting architecture | missing / incomplete / ambiguous / valid |
| `inputs` | Each input has name, data type, and sufficient context for contracts | missing / incomplete / valid |
| `outputs` | Each output has name, data type, and expected format | missing / incomplete / valid |
| `tests_scope` | At least one success scenario and one error scenario | missing / incomplete / valid |

The classification of states (lines 108-111) provides four levels: missing, incomplete, ambiguous, and valid. The decision gate (lines 115-117) enforces that ALL fields must be valid before proceeding. This is a well-defined validation framework.

---

### Check 4: technical.yaml output template with ALL fields

**Result**: PASS

The agent prompt includes a complete technical.yaml template (lines 771-824) that contains all seven required top-level fields:

1. **`feature`** (line 773): snake_case name matching the feature.yaml input
2. **`layer`** (line 774): enumerated values (api, domain, infrastructure, agent, worker, scheduler)
3. **`architecture`** (lines 776-781): includes pattern, entry, use_case, and interfaces sub-fields
4. **`api_contract`** (lines 783-803): includes method, path, auth, request schema, success response, and error responses
5. **`pipeline`** (lines 805-809): includes phase_name with input, process, and output
6. **`data_model`** (lines 810-821): includes er_diagram (Mermaid) and data_dictionary with entities, attributes, and relationships
7. **`dependencies`** (lines 823-824): list of component names with brief responsibility descriptions

A descriptive table for each field's purpose is also included (lines 828-837), along with writing rules (lines 840-851) that specify conventions for keys (English), values (Spanish for descriptions, English for technical names), and formatting rules per field.

---

### Check 5: Conditional fields only included when applicable

**Result**: PASS

The agent prompt explicitly defines three conditional fields with specific inclusion criteria in the **"Campos condicionales"** section (lines 854-856):

- **`api_contract`**: "incluir SOLO si la funcionalidad expone un endpoint REST/GraphQL" (line 854)
- **`pipeline`**: "incluir SOLO si la funcionalidad sigue un pipeline secuencial (agentes, workers, batch)" (line 855)
- **`data_model`**: "incluir SOLO si la funcionalidad crea o modifica tablas/entidades en la base de datos" (line 856)

These conditions are also documented inline in the YAML template itself with comments:
- Line 783: `# Solo si la funcionalidad expone un endpoint`
- Line 805: `# Solo para agentes, workers o procesos batch`
- Line 810: `# Solo si modifica el modelo de datos`

This double documentation (in comments and in a dedicated section) ensures the conditionality is clear and unambiguous.

---

### Check 6: technical-proposal.md with 2-3 alternatives and decision matrix

**Result**: PASS

The agent prompt requires generating `technical-proposal.md` as a mandatory output (lines 34-36 and line 1912). The section on solution alternatives (Phase 2.3, lines 417-460) provides a detailed option template and explicitly states:

> "Present at least **2-3 viable options** for comparison." (line 462)

The decision matrix requirement is defined in Phase 2.4 (lines 464-476), which provides a weighted scoring table template with criteria such as Implementation Complexity (20%), Maintenance Cost (25%), Scalability (20%), Alignment with Current Architecture (15%), Time to Market (10%), and Team Familiarity (10%).

The technical-proposal.md template (lines 1916-2033) reinforces this with dedicated sections for:
- Section 3: Solution Options Analysis (with Option 1, Option 2, Option 3 structure)
- Comparison Matrix reference
- Section 6: Technical Decisions with options considered, selected option, and justification

The Recommendation Guidelines (lines 2149-2152) also state: "Show at least 2-3 viable alternatives" and "Use objective evaluation criteria."

---

### Check 7: infrastructure-proposal.md with AWS/GCP proposals and comparison matrix

**Result**: PASS

The agent prompt dedicates an entire phase (Phase 4, lines 641-717) to infrastructure architecture proposals, with explicit subsections for:

- **AWS Infrastructure Proposal** (Section 4.2, lines 655-673): Full table mapping infrastructure concerns to AWS services (EKS, ECR, ALB, RDS, ElastiCache, S3, SQS, etc.)
- **GCP Infrastructure Proposal** (Section 4.3, lines 677-694): Full table mapping infrastructure concerns to GCP services (GKE, Artifact Registry, Cloud SQL, Memorystore, Cloud Storage, Pub/Sub, etc.)
- **Comparison Matrix** (Section 4.5, lines 705-717): Weighted comparison table with criteria including K8s Management, Cost Estimate, Managed Services Maturity, Team Familiarity, Region Availability, and Vendor Lock-in Risk

The `infrastructure-proposal.md` template (lines 1756-1910) includes:
- Section 3: AWS Proposal with architecture diagram, services selection table, networking, and estimated monthly cost
- Section 4: GCP Proposal with architecture diagram, services selection table, networking, and estimated monthly cost
- Section 5: AWS vs GCP Comparison with weighted scoring matrix
- Section 6: Recommendation with selected provider and justification

Mermaid diagram templates for both AWS (lines 1063-1111) and GCP (lines 1115-1163) infrastructure are also provided.

---

### Check 8: Uses Write tool to save output files

**Result**: PASS

The agent prompt explicitly requires using the Write tool in two locations:

1. **technical.yaml output** (line 860):
   > "Usar **Write tool** para guardar el archivo en: `docs/features/[feature_name]/technical.yaml`"

2. **Mandatory output files** (line 870):
   > "Usar **Write tool** para guardar cada archivo en la misma carpeta del feature.yaml de entrada."

This covers all three mandatory output files: technical.yaml, technical-proposal.md, and infrastructure-proposal.md. The prompt also instructs using the **Read tool** for reading the feature.yaml (line 65), establishing a clear read-then-write workflow.

---

### Check 9: Explicitly states NEVER generate implementation code

**Result**: PASS

The agent prompt contains multiple explicit prohibitions against generating code:

1. **Section header** (line 39): "What You MUST NOT Do - Code Implementation"
2. **Line 41**: "NEVER generate implementation code (not even code examples)"
3. **Line 42**: "Do not create source code files (.js, .py, .java, etc.)"
4. **Line 43**: "Do not write code snippets or fragments"
5. **Line 44**: "Do not suggest specific code implementations"
6. **Line 46**: "Your deliverables are **architectural documentation, diagrams, and strategic plans**, not code."
7. **Agent description** (line 10): "without writing implementation code"
8. **Boundaries section** (line 2412): "You AVOID: Implementation code, detailed coding examples, specific syntax"
9. **Redirect script** (lines 2414-2415): A polite redirect message is provided for when users ask for code

The prohibition is thorough, covering generated code, code examples, code snippets, source files, and specific implementations. The word "NEVER" is used explicitly.

---

### Check 10: Uses Mermaid syntax for all diagrams

**Result**: PASS

The agent prompt mandates Mermaid for all diagrams in multiple locations:

1. **Line 27**: "Generate architecture diagrams (using Mermaid syntax)"
2. **Line 874**: "Use **Mermaid syntax** for all diagrams."
3. **Diagram templates** (lines 878-1191): Every diagram template in the prompt uses Mermaid syntax, covering:
   - Architecture Overview (`graph TB`) - line 879
   - Component Diagram (`graph LR`) - line 918
   - Sequence Diagram (`sequenceDiagram`) - line 937
   - Data Flow Diagram (`graph LR`) - line 957
   - Class Diagram (`classDiagram`) - line 969
   - Deployment Diagram (`graph TB`) - line 996
   - Gantt Chart (`gantt`) - line 1031
   - State Machine (`stateDiagram-v2`) - line 1051
   - AWS Infrastructure (`graph TB`) - line 1064
   - GCP Infrastructure (`graph TB`) - line 1116
   - CI/CD GitOps Flow (`graph LR`) - line 1168
   - Task Dependency Mapping (`graph TD`) - line 601
   - ER Diagram (`erDiagram`) - line 733

4. **Conditional diagram flows** (lines 719-763): All conditional diagrams (ER, sequence, infrastructure) specify Mermaid syntax explicitly
5. **Infrastructure diagram requirements** (lines 698-703): Specify Mermaid diagrams for each cloud provider

No alternative diagram format (PlantUML, ASCII, Draw.io, etc.) is referenced anywhere in the prompt. Mermaid is the exclusive diagramming standard.

---

## Test Input Validation

The test input file `docs/features/product/feature.yaml` was verified to be a complete feature.yaml containing all mandatory fields:

| Field | Present | Content Quality |
|-------|---------|-----------------|
| `feature` | Yes | `product_specification_generator` (valid snake_case) |
| `description` | Yes | Starts with "Como Product Owner o Product Manager" (valid role format) |
| `acceptance_criteria` | Yes | 10 verifiable criteria (exceeds minimum of 3) |
| `business_rules` | Yes | 9 concrete rules with values and constraints |
| `inputs` | Yes | 4 inputs with names and descriptions |
| `outputs` | Yes | Detailed output specification with 9 field descriptions |
| `tests_scope` | Yes | 6 scenarios covering success, partial, edge cases, and validation |

This feature.yaml would pass all validation checks defined in the agent's checklist, meaning the agent should proceed to the analysis phase without triggering the MissingDataRequest flow.

---

## Conclusion

All 10 validation checks **PASS**. The architect agent prompt (v2.0) is correctly structured to handle a complete feature.yaml input and produce all expected outputs. The prompt defines clear input requirements, validation criteria, output templates, conditional field rules, mandatory deliverables, tool usage instructions, code generation prohibitions, and diagram standards. The test input (`docs/features/product/feature.yaml`) is a valid and complete feature.yaml that would trigger the full analysis pipeline without any missing data requests.
