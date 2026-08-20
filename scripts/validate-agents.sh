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

# Contar archivos de agentes (solo en subdirectorios agents/ y skills/, excluyendo README)
agent_count=$(find "$PLUGINS_DIR" -type f \( -path "*/agents/*.md" -o -path "*/skills/*.md" \) ! -name "README.md" | wc -l | xargs)

if [ "$agent_count" -eq 0 ]; then
    print_fail "No agent files found in $PLUGINS_DIR"
    exit 1
fi

print_pass "Found $agent_count agent file(s)"
echo ""

# Validar cada archivo de agente (solo en agents/ y skills/, excluyendo README)
while IFS= read -r -d '' agent_file; do
    if [ ! -f "$agent_file" ]; then
        continue
    fi

    # Calcular ruta relativa desde PLUGINS_DIR
    rel_path="${agent_file#$PLUGINS_DIR/}"
    agent_name="${rel_path%.md}"
    echo -e "${YELLOW}Testing agent: $agent_name${NC}"
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
done < <(find "$PLUGINS_DIR" -type f \( -path "*/agents/*.md" -o -path "*/skills/*.md" \) ! -name "README.md" -print0 | sort -z)

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