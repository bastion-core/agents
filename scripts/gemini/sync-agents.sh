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

# 1. Limpiar agentes y archivos de soporte anteriores para evitar archivos obsoletos
if [ -d "$AGENTS_DIR" ]; then
    echo "🧹 Limpiando agentes y archivos anteriores..."
    rm -f "$AGENTS_DIR"/*.md "$AGENTS_DIR"/*.yaml
fi

# 2. Crear directorios necesarios
mkdir -p "$AGENTS_DIR"

# 3. Copiar Agentes ($SRC_DIR/.gemini/agents/)
if [ -d "$SRC_DIR/.gemini/agents" ]; then
    echo "📦 Sincronizando agentes..."
    cp -r "$SRC_DIR/.gemini/agents/"* "$AGENTS_DIR/"
else
    echo "⚠️ No se encontró la carpeta $SRC_DIR/.gemini/agents/"
fi

# 4. Copiar Archivos de Soporte (Schemas, Ejemplos) - NO se copian .md aquí para evitar
#    que Gemini los interprete como agentes
echo "📑 Sincronizando archivos de soporte (schemas, ejemplos)..."
for pattern in "schema-*.yaml" "example-*.yaml"; do
    # shellcheck disable=SC2086
    files=$(ls "$SRC_DIR"/$pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        for file in "$SRC_DIR"/$pattern; do
            if [ -f "$file" ]; then
                cp "$file" "$AGENTS_DIR/"
            fi
        done
    fi
done

# 5. Configurar Instrucciones Globales (GEMINI.md)
if [ -f "$SRC_DIR/GEMINI.md" ]; then
    echo "⚙️ Configurando instrucciones globales (GEMINI.md)..."
    cp "$SRC_DIR/GEMINI.md" "$GEMINI_DIR/GEMINI.md"
else
    echo "⚠️ No se encontró $SRC_DIR/GEMINI.md"
fi

echo "✅ Sincronización completada con éxito."
echo "💡 Ahora puedes usar @architect, @product, etc., en cualquier repositorio."
