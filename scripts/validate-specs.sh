#!/bin/bash

# Validador de especificaciones SDD (feature, change, technical y tasks).
# Delega en scripts/validate_specs.py. Requiere python3 y PyYAML (pip install pyyaml).
#
# Uso: ./scripts/validate-specs.sh <directorio-o-archivos...>
#      ./scripts/validate-specs.sh            (sin argumentos: context/sdd-specs y docs/features)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 no esta disponible" >&2
    exit 2
fi

if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "Falta PyYAML: pip install pyyaml" >&2
    exit 2
fi

if [ "$#" -eq 0 ]; then
    set -- "$REPO_ROOT/context/sdd-specs" "$REPO_ROOT/docs/features"
fi

exec python3 "$SCRIPT_DIR/validate_specs.py" "$@"
