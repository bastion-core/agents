# Gemini Agents - Configuración Global

Este directorio contiene los agentes especializados de Gemini y el script de sincronización para habilitarlos globalmente en tu máquina.

## Propósito

Al sincronizar los agentes globalmente, podrás invocarlos (usando `@product`, `@architect`, etc.) desde **cualquier repositorio** en tu terminal, sin necesidad de copiar los archivos de configuración a cada proyecto.

## Pasos para la Sincronización Global

Sigue estos pasos para configurar los agentes en tu entorno local:

### 1. Ejecutar el Script de Sincronización

Desde la raíz de este repositorio, ejecuta el siguiente comando:

```bash
bash gemini/sync-agents.sh
```

Este script realizará las siguientes acciones:
- Creará el directorio `~/.gemini/agents/` si no existe.
- Copiará todos los agentes definidos en `gemini/spec-generator/.gemini/agents/` a tu configuración global.
- Copiará los archivos de soporte (convenciones, esquemas y ejemplos) para que los agentes tengan el contexto necesario.
- Configurará el archivo `~/.gemini/GEMINI.md` con las instrucciones de orquestación global.

### 2. Verificar la Instalación

Abre una nueva terminal o dirígete a cualquier otro proyecto y ejecuta Gemini CLI:

```bash
gemini
```

Una vez dentro de la CLI, puedes preguntar qué agentes hay disponibles:

```
> Hola, ¿qué subagents tienes disponibles?
```

Debería responder listando agentes como `@product`, `@architect`, `@backend-py`, etc.

## Estructura de Archivos Sincronizados

Los agentes se instalan en:
- `~/.gemini/agents/`: Contiene los archivos `.md` de cada agente y archivos YAML de soporte.
- `~/.gemini/GEMINI.md`: Define las reglas generales y el flujo de trabajo (Discovery con Gemini -> Delivery con Claude Code).

## Actualización de Agentes

Si se realizan cambios en los agentes dentro de este repositorio, simplemente vuelve a ejecutar el script `bash gemini/sync-agents.sh` para actualizar tu configuración global con las últimas versiones.

---
*Nota: Asegúrate de tener instalado [@google/gemini-cli](https://github.com/google-gemini/gemini-cli) y configurado Vertex AI para el correcto funcionamiento.*
