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
SKILLS_DIR="$GEMINI_DIR/skills"

echo "🚀 Iniciando sincronización global de agentes desde $SRC_DIR..."

# 1. Limpiar agentes, archivos de soporte y skills anteriores
if [ -d "$AGENTS_DIR" ]; then
    echo "🧹 Limpiando agentes y archivos anteriores..."
    rm -f "$AGENTS_DIR"/*.md "$AGENTS_DIR"/*.yaml
fi
if [ -d "$SKILLS_DIR" ]; then
    echo "🧹 Limpiando skills anteriores..."
    rm -rf "$SKILLS_DIR"/*
fi

# 2. Crear directorios necesarios
mkdir -p "$AGENTS_DIR"
mkdir -p "$SKILLS_DIR"

# 3. Copiar Agentes ($SRC_DIR/.gemini/agents/)
if [ -d "$SRC_DIR/.gemini/agents" ]; then
    echo "📦 Sincronizando agentes..."
    cp -r "$SRC_DIR/.gemini/agents/"* "$AGENTS_DIR/"
else
    echo "⚠️ No se encontró la carpeta $SRC_DIR/.gemini/agents/"
fi

# 4. Copiar Skills ($SRC_DIR/.gemini/skills/)
if [ -d "$SRC_DIR/.gemini/skills" ]; then
    echo "🛠️ Sincronizando skills..."
    cp -r "$SRC_DIR/.gemini/skills/"* "$SKILLS_DIR/"
else
    echo "⚠️ No se encontró la carpeta $SRC_DIR/.gemini/skills/"
fi

# 5. Copiar Archivos de Soporte (SDD Specs)
SPECS_DIR="$REPO_ROOT/context/sdd-specs"

echo "📑 Sincronizando archivos de soporte (schemas, ejemplos)..."

# SDD Specs
if [ -d "$SPECS_DIR" ]; then
    echo "   - SDD Specs de $SPECS_DIR"
    cp "$SPECS_DIR"/*.schema.yaml "$AGENTS_DIR/" 2>/dev/null || true
    cp "$SPECS_DIR"/*.example.yaml "$AGENTS_DIR/" 2>/dev/null || true
fi

# 6. Configurar Instrucciones Globales (GEMINI.md)
if [ -f "$SRC_DIR/GEMINI.md" ]; then
    echo "⚙️ Configurando instrucciones globales (GEMINI.md)..."
    cp "$SRC_DIR/GEMINI.md" "$GEMINI_DIR/GEMINI.md"
else
    echo "⚠️ No se encontró $SRC_DIR/GEMINI.md"
fi

echo "✅ Sincronización completada con éxito."
echo "💡 Ahora puedes usar @architect, @product, etc., en cualquier proyecto."

