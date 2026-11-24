#!/bin/bash

# Sincroniza el validador de specs SDD con las copias empaquetadas en la skill
# spec-reviewer (plugin general de Claude Code y skill de Gemini).
#
# Fuente unica de verdad:
#   scripts/validate_specs.py
#   context/sdd-specs/{feature,change,technical,task}.schema.yaml
#   context/sdd-specs/status-vocabulary.md   (referencia)
#
# Uso: ./scripts/sync-spec-validator.sh           copia la fuente a los destinos
#      ./scripts/sync-spec-validator.sh --check   no escribe; sale con 1 si hay deriva

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

SRC_SCRIPT="$REPO_ROOT/scripts/validate_specs.py"
SRC_SCHEMAS_DIR="$REPO_ROOT/context/sdd-specs"
SCHEMAS=(feature change technical task)

DESTS=(
    "$REPO_ROOT/plugins/general/skills/spec-reviewer"
    "$REPO_ROOT/gemini/spec-generator/.gemini/skills/spec-reviewer"
)

MODE="sync"
case "${1:-}" in
    "") ;;
    --check) MODE="check" ;;
    -h|--help) sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Uso: $0 [--check]" >&2; exit 2 ;;
esac

# pares "origen|destino-relativo"
pairs() {
    echo "$SRC_SCRIPT|scripts/validate_specs.py"
    for s in "${SCHEMAS[@]}"; do
        echo "$SRC_SCHEMAS_DIR/$s.schema.yaml|schemas/$s.schema.yaml"
    done
    echo "$SRC_SCHEMAS_DIR/status-vocabulary.md|references/status-vocabulary.md"
}

drift=0
while IFS='|' read -r src rel; do
    if [ ! -f "$src" ]; then
        echo "ERROR: falta la fuente $src" >&2
        exit 2
    fi
    for dest in "${DESTS[@]}"; do
        target="$dest/$rel"
        shown="${target#"$REPO_ROOT"/}"
        if [ "$MODE" = "check" ]; then
            if [ ! -f "$target" ]; then
                echo "FALTA: $shown"; drift=1
            elif ! cmp -s "$src" "$target"; then
                echo "DIFIERE: $shown"; drift=1
            fi
        else
            mkdir -p "$(dirname "$target")"
            if [ ! -f "$target" ] || ! cmp -s "$src" "$target"; then
                cp "$src" "$target"
                echo "actualizado: $shown"
            fi
        fi
    done
done < <(pairs)

if [ "$MODE" = "check" ]; then
    if [ "$drift" -ne 0 ]; then
        echo "Las copias empaquetadas no coinciden con la fuente. Ejecuta: scripts/sync-spec-validator.sh" >&2
        exit 1
    fi
    echo "OK: las copias empaquetadas coinciden con la fuente"
fi
exit 0
