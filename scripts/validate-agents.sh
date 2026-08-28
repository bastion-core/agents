#!/bin/bash

# Script de validación de agentes
# Valida la estructura y formato de los archivos de agentes

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$(dirname "$SCRIPT_DIR")/plugins"

# Contadores
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Función para imprimir resultados
print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║        Agent Validation Test Suite           ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# Validar que el directorio de plugins existe
if [ ! -d "$PLUGINS_DIR" ]; then
    print_fail "Plugins directory not found: $PLUGINS_DIR"
    exit 1
fi

print_pass "Plugins directory exists"
echo ""

# ─── Estructura de skills ─────────────────────────────────────────────────────
# Claude Code descubre skills como skills/<nombre>/SKILL.md. Un .md suelto bajo
# skills/ se copia al instalar el plugin pero nunca se carga.
echo -e "${YELLOW}Testing skill directory structure${NC}"
echo "────────────────────────────────────────────────"

stray_skills=$(find "$PLUGINS_DIR" -type f -path "$PLUGINS_DIR/*/skills/*.md" -not -path "$PLUGINS_DIR/*/skills/*/*" ! -name "README.md" 2>/dev/null)
if [ -z "$stray_skills" ]; then
    print_pass "No flat .md files directly under skills/"
else
    while IFS= read -r stray; do
        print_fail "Skill must be a directory with SKILL.md, not a flat file: ${stray#$PLUGINS_DIR/}"
    done <<< "$stray_skills"
fi

while IFS= read -r skill_dir; do
    [ -z "$skill_dir" ] && continue
    skill_dir_name=$(basename "$skill_dir")
    rel_skill="${skill_dir#$PLUGINS_DIR/}"

    if [ -f "$skill_dir/SKILL.md" ]; then
        print_pass "$rel_skill contains SKILL.md"
    else
        print_fail "$rel_skill is missing SKILL.md"
        continue
    fi

    # El 'name' del frontmatter debe coincidir con el nombre del directorio
    skill_name=$(sed -n '/^---$/,/^---$/p' "$skill_dir/SKILL.md" | grep "^name:" | sed 's/name: *//')
    if [ "$skill_name" = "$skill_dir_name" ]; then
        print_pass "$rel_skill name matches directory"
    else
        print_fail "$rel_skill name mismatch: frontmatter '$skill_name' != directory '$skill_dir_name'"
    fi
done < <(find "$PLUGINS_DIR" -mindepth 3 -maxdepth 3 -type d -path "$PLUGINS_DIR/*/skills/*" | sort)

echo ""

# ─── Consistencia de versiones marketplace.json <-> plugin.json ───────────────
echo -e "${YELLOW}Testing manifest version consistency${NC}"
echo "────────────────────────────────────────────────"

MARKETPLACE_FILE="$(dirname "$PLUGINS_DIR")/.claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE_FILE" ]; then
    print_fail "marketplace.json not found: $MARKETPLACE_FILE"
elif ! command -v python3 >/dev/null 2>&1; then
    print_warn "python3 not available, skipping version consistency check"
else
    version_report=$(python3 - "$MARKETPLACE_FILE" "$PLUGINS_DIR" <<'PYEOF'
import json, os, sys

marketplace_file, plugins_dir = sys.argv[1], sys.argv[2]
marketplace = json.load(open(marketplace_file, encoding="utf-8"))

for entry in marketplace.get("plugins", []):
    name = entry["name"]
    manifest = os.path.join(plugins_dir, name, ".claude-plugin", "plugin.json")
    if not os.path.isfile(manifest):
        print(f"FAIL|{name}: plugin.json not found at {manifest}")
        continue
    plugin = json.load(open(manifest, encoding="utf-8"))
    if entry.get("version") != plugin.get("version"):
        print(f"FAIL|{name}: version mismatch, marketplace.json {entry.get('version')} != plugin.json {plugin.get('version')}")
    else:
        print(f"PASS|{name}: version {plugin.get('version')} consistent")
    if entry.get("description") != plugin.get("description"):
        print(f"WARN|{name}: description differs between marketplace.json and plugin.json")
PYEOF
    )
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            PASS\|*) print_pass "${line#PASS|}" ;;
            FAIL\|*) print_fail "${line#FAIL|}" ;;
            WARN\|*) print_warn "${line#WARN|}" ;;
        esac
    done <<< "$version_report"
fi

echo ""

# Contar archivos de agentes (solo en subdirectorios agents/ y skills/, excluyendo README)
agent_count=$(find "$PLUGINS_DIR" -type f \( -path "$PLUGINS_DIR/*/agents/*.md" -o -path "$PLUGINS_DIR/*/skills/*/SKILL.md" \) ! -name "README.md" | wc -l | xargs)

if [ "$agent_count" -eq 0 ]; then
    print_fail "No agent or skill files found in $PLUGINS_DIR"
    exit 1
fi

print_pass "Found $agent_count agent/skill file(s)"
echo ""

# Validar cada archivo de agente (solo en agents/ y skills/, excluyendo README)
while IFS= read -r -d '' agent_file; do
    if [ ! -f "$agent_file" ]; then
        continue
    fi

    # Calcular ruta relativa desde PLUGINS_DIR
    rel_path="${agent_file#$PLUGINS_DIR/}"
    agent_name="${rel_path%.md}"

    # Un skill es skills/<nombre>/SKILL.md; el resto son agents. Cada tipo tiene
    # frontmatter distinto, así que los tests 6 y 7 se bifurcan.
    if [[ "$rel_path" == */skills/*/SKILL.md ]]; then
        entry_kind="skill"
    else
        entry_kind="agent"
    fi

    echo -e "${YELLOW}Testing $entry_kind: $agent_name${NC}"
    echo "────────────────────────────────────────────────"

    # Test 1: Archivo no está vacío
    if [ -s "$agent_file" ]; then
        print_pass "File is not empty"
    else
        print_fail "File is empty"
        echo ""
        continue
    fi

    # Test 2: Archivo comienza con frontmatter YAML
    first_line=$(head -n 1 "$agent_file")
    if [ "$first_line" = "---" ]; then
        print_pass "Has YAML frontmatter delimiter"
    else
        print_fail "Missing YAML frontmatter start (---)"
    fi

    # Test 3: Frontmatter se cierra correctamente
    frontmatter_end=$(awk '/^---$/ {count++; if(count==2) {print NR; exit}}' "$agent_file")
    if [ -n "$frontmatter_end" ] && [ "$frontmatter_end" -gt 1 ]; then
        print_pass "YAML frontmatter closes correctly"
    else
        print_fail "YAML frontmatter not closed properly"
    fi

    # Test 4: Campo 'name' existe y es válido
    name_field=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep "^name:" | sed 's/name: *//')
    if [ -n "$name_field" ]; then
        print_pass "Has 'name' field: $name_field"

        # Validar formato kebab-case
        if [[ "$name_field" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
            print_pass "Name follows kebab-case convention"
        else
            print_warn "Name should be in kebab-case (lowercase with hyphens)"
        fi
    else
        print_fail "Missing 'name' field in frontmatter"
    fi

    # Test 5: Campo 'description' existe
    description_field=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep "^description:" | sed 's/description: *//')
    if [ -n "$description_field" ]; then
        print_pass "Has 'description' field"

        # Validar longitud de descripción
        desc_length=${#description_field}
        if [ $desc_length -lt 20 ]; then
            print_warn "Description is too short (<20 chars): $desc_length chars"
        elif [ $desc_length -gt 200 ]; then
            print_warn "Description is too long (>200 chars): $desc_length chars"
        else
            print_pass "Description length is appropriate: $desc_length chars"
        fi
    else
        print_fail "Missing 'description' field in frontmatter"
    fi

    if [ "$entry_kind" = "skill" ]; then
        # Tests 6-7 (skills): model, color y argument-hint son campos de agent y
        # no forman parte del frontmatter de un skill.
        forbidden_found=""
        for forbidden in model color argument-hint; do
            if sed -n '/^---$/,/^---$/p' "$agent_file" | grep -q "^$forbidden:"; then
                print_fail "Skill frontmatter must not define '$forbidden'"
                forbidden_found="yes"
            fi
        done
        if [ -z "$forbidden_found" ]; then
            print_pass "Frontmatter has no agent-only fields"
        fi

        # 'Task' es el nombre antiguo de la herramienta de subagentes; hoy es 'Agent'.
        allowed_tools_field=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep "^allowed-tools:" | sed 's/allowed-tools: *//')
        if [[ "$allowed_tools_field" =~ (^|[[:space:],])Task([[:space:],]|$) ]]; then
            print_fail "allowed-tools references the retired 'Task' tool (use 'Agent')"
        elif [ -n "$allowed_tools_field" ]; then
            print_pass "allowed-tools uses current tool names"
        fi
    else
        # Test 6: Campo 'model' existe y es válido
        model_field=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep "^model:" | sed 's/model: *//')
        if [ -n "$model_field" ]; then
            if [[ "$model_field" =~ ^(inherit|sonnet|opus|haiku|fable)$ ]]; then
                print_pass "Has valid 'model' field: $model_field"
            else
                print_fail "Invalid 'model' value: $model_field (should be: inherit, sonnet, opus, haiku, or fable)"
            fi
        else
            print_fail "Missing 'model' field in frontmatter"
        fi

        # Test 7: Campo 'color' existe y es válido
        color_field=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep "^color:" | sed 's/color: *//')
        if [ -n "$color_field" ]; then
            if [[ "$color_field" =~ ^(blue|green|yellow|red|purple|cyan|orange|pink)$ ]]; then
                print_pass "Has valid 'color' field: $color_field"
            else
                print_warn "Uncommon 'color' value: $color_field (common: blue, green, yellow, red, purple, cyan)"
            fi
        else
            print_fail "Missing 'color' field in frontmatter"
        fi
    fi

    # Test 8: Tiene contenido después del frontmatter
    content_lines=$(tail -n +$((frontmatter_end + 1)) "$agent_file" | grep -v '^[[:space:]]*$' | wc -l | xargs)
    if [ "$content_lines" -gt 10 ]; then
        print_pass "Has substantial content: $content_lines lines"
    elif [ "$content_lines" -gt 0 ]; then
        print_warn "Content seems short: only $content_lines lines"
    else
        print_fail "No content after frontmatter"
    fi

    # Test 9: Tiene al menos un encabezado H1
    h1_count=$(grep -c "^# " "$agent_file" || true)
    if [ "$h1_count" -gt 0 ]; then
        print_pass "Has H1 heading(s): $h1_count"
    else
        print_warn "No H1 heading found (recommended for structure)"
    fi

    # Test 10: No tiene caracteres especiales problemáticos
    if grep -q $'\r' "$agent_file"; then
        print_fail "Contains Windows line endings (CRLF)"
    else
        print_pass "Has Unix line endings (LF)"
    fi

    # Test 11: Encoding es UTF-8
    if file "$agent_file" | grep -q "UTF-8"; then
        print_pass "File encoding is UTF-8"
    else
        print_warn "File encoding might not be UTF-8"
    fi

    # Test 12: No tiene líneas excesivamente largas (>500 caracteres)
    long_lines=$(awk 'length > 500' "$agent_file" | wc -l | xargs)
    if [ "$long_lines" -eq 0 ]; then
        print_pass "No excessively long lines"
    else
        print_warn "Found $long_lines line(s) longer than 500 characters"
    fi

    echo ""
done < <(find "$PLUGINS_DIR" -type f \( -path "$PLUGINS_DIR/*/agents/*.md" -o -path "$PLUGINS_DIR/*/skills/*/SKILL.md" \) ! -name "README.md" -print0 | sort -z)

# Resumen final
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║              Validation Summary               ║"
echo "╠═══════════════════════════════════════════════╣"
echo -e "║  ${GREEN}Passed:  $PASSED_TESTS${BLUE}"
echo -e "║  ${RED}Failed:  $FAILED_TESTS${BLUE}"
echo -e "║  ${YELLOW}Warnings: $WARNINGS${BLUE}"
echo -e "║  Total:   $TOTAL_TESTS"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# Código de salida
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}✓ All validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some validation tests failed${NC}"
    exit 1
fi