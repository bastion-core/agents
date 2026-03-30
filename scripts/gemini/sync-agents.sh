#!/bin/bash

# Script de Sincronización Global de Agentes Gemini
# Este script configura los agentes y convenciones del repositorio actual 
# para que estén disponibles globalmente en cualquier proyecto.

set -e

# Obtener el directorio raiz del repositorio (dos niveles arriba de scripts/gemini/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
SRC_DIR="$REPO_ROOT/gemini/spec-generator"

GEMINI_DIR="$HOME/.gemini"
AGENTS_DIR="$GEMINI_DIR/agents"

echo "🚀 Iniciando sincronización global de agentes desde $SRC_DIR..."

# 1. Crear directorios necesarios
mkdir -p "$AGENTS_DIR"

# 2. Copiar Agentes ($SRC_DIR/.gemini/agents/)
if [ -d "$SRC_DIR/.gemini/agents" ]; then
    echo "📦 Sincronizando agentes..."
    cp -r "$SRC_DIR/.gemini/agents/"* "$AGENTS_DIR/"
else
    echo "⚠️ No se encontró la carpeta $SRC_DIR/.gemini/agents/"
fi

# 3. Copiar Archivos de Soporte (Convenciones, Schemas, Ejemplos)
echo "📑 Sincronizando archivos de soporte (convenciones, schemas, ejemplos)..."
# Usamos un bucle para evitar errores si no hay archivos que coincidan
for pattern in "conventions-*.md" "schema-*.yaml" "example-*.yaml"; do
    # shellcheck disable=SC2086
    files=$(ls "$SRC_DIR"/$pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        # Copiamos cada archivo individualmente para evitar problemas con el glob en el destino
        for file in "$SRC_DIR"/$pattern; do
            if [ -f "$file" ]; then
                cp "$file" "$AGENTS_DIR/"
            fi
        done
    fi
done

# 4. Configurar Instrucciones Globales (GEMINI.md)
if [ -f "$SRC_DIR/GEMINI.md" ]; then
    echo "⚙️ Configurando instrucciones globales (GEMINI.md)..."
    cp "$SRC_DIR/GEMINI.md" "$GEMINI_DIR/GEMINI.md"
else
    echo "⚠️ No se encontró $SRC_DIR/GEMINI.md"
fi

echo "✅ Sincronización completada con éxito."
echo "💡 Ahora puedes usar @architect, @product, etc., en cualquier repositorio."
