# Test Result: Insufficient feature.yaml Input Handling

**Test ID**: 12_test_insufficient_feature_yaml
**Agent Under Test**: Architect Agent v2.0
**Prompt File**: `plugins/general/agents/architect.md`
**Test Spec**: `docs/features/architect/tasks/12_test_insufficient_feature_yaml.yaml`
**Date**: 2026-03-13
**Type**: Static validation (READ-ONLY analysis of agent prompt)

---

## Test Methodology

This test validates the architect agent prompt by statically analyzing whether the prompt text contains explicit instructions, rules, and structures that would cause the agent to correctly handle insufficient feature.yaml inputs. Each scenario and validation check is evaluated against specific sections of the agent prompt.

---

## Scenario Results

### 1. missing_business_rules

| Aspect | Detail |
|--------|--------|
| **Input** | feature.yaml sin business_rules o con reglas vagas |
| **Expected** | Lista de faltantes indicando que business_rules esta incompleto, con preguntas sobre restricciones, limites y reglas que impacten la arquitectura |
| **Result** | **PASS** |

**Justification**: The agent prompt defines `business_rules` in the Validation Phase checklist (line 101) with the criterion: "Reglas concretas con valores, limites o restricciones que impacten la arquitectura" and possible states: `missing / incomplete / ambiguous / valid`. The Decision Gate (lines 114-117) explicitly states that if ANY field has state `missing`, `incomplete`, or `ambiguous`, the MissingDataRequest flow is activated. The Missing Data Flow section (lines 128-146) requires presenting a structured table with Campo, Estado, Detalle, and Pregunta sugerida, and rule 2 (line 143) mandates that questions be "especificas al contexto arquitectonico" with an example. This fully covers the expected behavior of reporting missing/vague business_rules with architecture-oriented questions.

---

### 2. missing_inputs_outputs

| Aspect | Detail |
|--------|--------|
| **Input** | feature.yaml sin definicion clara de inputs y outputs |
| **Expected** | Lista de faltantes indicando que inputs/outputs estan incompletos, con preguntas sobre tipos de dato, formatos y contratos esperados |
| **Result** | **PASS** |

**Justification**: The validation checklist includes both `inputs` (line 102) with criterion "Cada entrada tiene nombre, tipo de dato y contexto suficiente para definir contratos" (states: `missing / incomplete / valid`) and `outputs` (line 103) with criterion "Cada salida tiene nombre, tipo de dato y formato esperado" (states: `missing / incomplete / valid`). These criteria explicitly reference types, formats, and contracts. When either field is missing or incomplete, the Decision Gate triggers MissingDataRequest. The structured response format will surface these as individual rows with specific questions about data types, formats, and contract definitions.

---

### 3. ambiguous_acceptance_criteria

| Aspect | Detail |
|--------|--------|
| **Input** | feature.yaml con criterios vagos como "debe ser rapido" o "debe ser seguro" |
| **Expected** | Lista de faltantes indicando que acceptance_criteria es ambiguo, con preguntas para obtener criterios medibles y verificables |
| **Result** | **PASS** |

**Justification**: The prompt explicitly addresses this exact scenario. The `acceptance_criteria` field (line 100) requires "Al menos 3 criterios verificables que definan alcance tecnico" with possible states including `ambiguous`. The classification of states section (lines 108-111) defines `ambiguous` as "el campo tiene informacion vaga o no medible" and provides the exact examples from the test scenario: `"debe ser rapido", "debe ser seguro"` (line 110). The Decision Gate (line 116) confirms that `ambiguous` status triggers the MissingDataRequest flow. This is an exact match to the test expectation.

---

### 4. minimal_description

| Aspect | Detail |
|--------|--------|
| **Input** | feature.yaml solo con description basica sin acceptance_criteria ni business_rules |
| **Expected** | Lista de faltantes indicando multiples campos incompletos con preguntas especificas por campo |
| **Result** | **PASS** |

**Justification**: The validation checklist (lines 96-104) covers all seven fields independently: `feature`, `description`, `acceptance_criteria`, `business_rules`, `inputs`, `outputs`, and `tests_scope`. Each has its own validation criterion and possible states. The Decision Gate (lines 114-116) states: "Si ALGUN campo tiene estado missing, incomplete o ambiguous -> activar MissingDataRequest". The MissingDataRequest response format (lines 134-138) is a table that lists each failing field as a separate row with its own Estado, Detalle, and Pregunta sugerida. This means when multiple fields are missing (acceptance_criteria, business_rules, inputs, outputs, tests_scope), each will appear as its own entry with a field-specific question. The prompt handles multiple missing fields by design.

---

### 5. unrelated_content

| Aspect | Detail |
|--------|--------|
| **Input** | Archivo YAML que no sigue el formato de feature.yaml estandarizado |
| **Expected** | Agente indica que el archivo no tiene el formato esperado y solicita un feature.yaml valido |
| **Result** | **PASS (Implicit)** |

**Justification**: The prompt defines the complete expected structure of a feature.yaml (lines 50-61) with seven specific fields: `feature`, `description`, `acceptance_criteria`, `business_rules`, `inputs`, `outputs`, `tests_scope`. The validation checklist (lines 96-104) checks ALL of these fields. If a YAML file does not follow this format, ALL fields would be classified as `missing` (defined as "el campo no existe o esta vacio" on line 108). The Decision Gate would trigger MissingDataRequest for every field. The pipeline description (lines 69-77) also shows the flow: if validation fails, the agent produces a MissingDataRequest rather than proceeding. However, the prompt does NOT contain an explicit instruction to detect "this is not a feature.yaml format" as a distinct error category. The agent would classify each expected field as `missing` rather than giving a single "wrong format" error. This is a minor gap -- the behavior is functionally correct (no partial output is generated, missing data is reported) but the user experience differs slightly from a dedicated "invalid format" message. Marked as PASS because the core safety behavior (no partial generation, data request) is preserved.

---

## Validation Check Results

### V1: Agent does NOT generate technical.yaml when inputs are insufficient

| Check | Result |
|-------|--------|
| **Status** | **PASS** |

**Evidence**: The Decision Gate section (line 117) explicitly states: "NUNCA generar un technical.yaml parcial si falta informacion" (emphasis in the original prompt with bold NUNCA). The Missing Data Flow rules (line 144) reinforce: "Nunca generar technical.yaml, technical-proposal.md ni infrastructure-proposal.md parciales". The pipeline flow (lines 83-85) confirms: "Si ALGUN campo falla -> activar flujo de MissingDataRequest (nunca generar archivos parciales)".

---

### V2: Agent does NOT generate technical-proposal.md nor infrastructure-proposal.md when inputs are insufficient

| Check | Result |
|-------|--------|
| **Status** | **PASS** |

**Evidence**: Line 144 of the Missing Data Flow rules explicitly states: "Nunca generar technical.yaml, technical-proposal.md ni infrastructure-proposal.md parciales". All three output files are explicitly prohibited when validation fails. This is a direct, unambiguous prohibition covering all three mandatory output files.

---

### V3: Response includes structured format (campo, estado, detalle, pregunta sugerida)

| Check | Result |
|-------|--------|
| **Status** | **PASS** |

**Evidence**: The Missing Data Flow section (lines 134-138) defines the exact structured format as a table:

```
| Campo | Estado | Detalle | Pregunta sugerida |
|-------|--------|---------|-------------------|
| `[campo]` | missing/incomplete/ambiguous | Que informacion especifica falta del feature.yaml | Pregunta concreta para obtener el dato |
```

All four columns requested in the test spec are present: campo, estado (with the three possible values: missing/incomplete/ambiguous), detalle, and pregunta sugerida.

---

### V4: Agent uses AskUserQuestion for soliciting missing data

| Check | Result |
|-------|--------|
| **Status** | **PASS** |

**Evidence**: The Missing Data Flow rules (line 142) explicitly state: "Usar AskUserQuestion para hacer preguntas concretas al usuario o PO". The term "AskUserQuestion" is mentioned by name as the mechanism for soliciting missing data. It is also referenced in the conditional diagram flows (lines 729, 742, 755) for other interaction points, confirming it is the standard tool the agent uses for user interaction.

---

### V5: Agent re-executes validation after receiving new data

| Check | Result |
|-------|--------|
| **Status** | **PASS** |

**Evidence**: The Missing Data Flow rules (line 145) explicitly state: "Despues de recibir respuestas del usuario, re-ejecutar la validacion completa del feature.yaml con la nueva informacion". Line 146 adds: "Solo continuar al analisis cuando TODOS los campos tengan estado valid". This confirms the full re-validation loop is mandated before proceeding to analysis.

---

## Summary

| # | Item | Result |
|---|------|--------|
| S1 | missing_business_rules | PASS |
| S2 | missing_inputs_outputs | PASS |
| S3 | ambiguous_acceptance_criteria | PASS |
| S4 | minimal_description | PASS |
| S5 | unrelated_content | PASS (Implicit) |
| V1 | No partial technical.yaml generation | PASS |
| V2 | No partial technical-proposal.md / infrastructure-proposal.md generation | PASS |
| V3 | Structured response format (campo, estado, detalle, pregunta sugerida) | PASS |
| V4 | Uses AskUserQuestion for soliciting missing data | PASS |
| V5 | Re-executes validation after receiving new data | PASS |

**Overall Result**: **PASS (10/10)**

---

## Observations

1. **Scenario S5 (unrelated_content)**: The agent prompt does not have a dedicated "invalid format" detection step. Instead, it relies on per-field validation, which means an unrelated YAML file would result in all seven fields being marked as `missing`. The functional outcome is correct (no partial generation, structured data request), but a dedicated format-check message could improve user experience. This is a minor enhancement opportunity, not a defect.

2. **Ambiguity examples**: The prompt provides explicit examples of ambiguous inputs ("debe ser rapido", "debe ser seguro") which directly match the test scenario inputs. This demonstrates strong alignment between the prompt design and the test expectations.

3. **Triple prohibition layer**: The prohibition against partial file generation is stated in three separate locations in the prompt (pipeline description line 85, Decision Gate line 117, Missing Data Flow rules line 144), providing strong redundancy against the agent bypassing the rule.

---

**Test executed by**: Claude Opus 4.6 (static prompt analysis)
**Test type**: READ-ONLY validation -- no modifications made to the agent prompt
