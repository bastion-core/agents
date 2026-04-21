# Claude Agents Repository

Repositorio centralizado de agentes personalizados para Claude Code. Facilita la instalación y sincronización de agentes especializados en diferentes proyectos de desarrollo.

## Descripción

Este repositorio proporciona una colección de agentes de Claude especializados y un script de sincronización que permite instalarlos fácilmente en cualquier proyecto local. Los agentes están diseñados para tareas específicas de desarrollo, desde arquitectura de software hasta testing y QA.

## Agentes Disponibles

Los agentes están organizados en plugins por dominio tecnológico. Cada plugin contiene agentes especializados y skills ejecutables.

### General Plugin

Agentes agnósticos de lenguaje que funcionan en cualquier proyecto.

#### 1. Architect Agent (`[general/agents] architect`)
**Especialista en Arquitectura de Software**

Agente enfocado en análisis, evaluación y recomendación de soluciones arquitectónicas sin escribir código de implementación.

**Capacidades:**
- Análisis profundo de arquitectura de proyectos
- Evaluación de patrones de diseño (Clean Architecture, Hexagonal, etc.)
- Recomendaciones de arquitectura con pros/cons
- Planificación detallada de desarrollo por fases
- Generación de diagramas (Mermaid)
- Estimaciones de tiempo y recursos
- Documentación técnica completa (ADRs)

**Cuándo usar:**
- Diseño de nuevas funcionalidades
- Refactorización de sistemas existentes
- Evaluación de opciones técnicas
- Planificación de proyectos
- Documentación de arquitectura

### Python Development Plugin

Agentes y skills especializados para desarrollo Python backend.

#### 2. Backend Python Agent (`[python-development/agents] backend-py`)
**Desarrollo Backend Python con Clean Architecture**

Agente especializado en desarrollo backend Python usando Clean Architecture y Hexagonal Architecture (Ports & Adapters).

**Stack Tecnológico:**
- FastAPI 0.68.2+
- SQLAlchemy 2.0+ (PostgreSQL)
- MongoEngine (MongoDB)
- Alembic 1.14.0+
- Python 3.11+

**Capacidades:**
- Implementación de Clean Architecture/Hexagonal Architecture
- Desarrollo de APIs REST con FastAPI
- Gestión de bases de datos (PostgreSQL, MongoDB)
- Migraciones con Alembic
- Aplicación de principios SOLID
- Patrones de diseño (Repository, Interactor, DTO)
- Seguridad y autenticación (JWT, OAuth 2.0)
- Optimización de queries y performance

**Cuándo usar:**
- Desarrollo de APIs REST
- Implementación de casos de uso (Interactors)
- Creación de repositorios y adaptadores
- Migraciones de base de datos
- Refactorización hacia arquitectura limpia

#### 3. QA Backend Python Agent (`[python-development/agents] qa-backend-py`)
**Testing y QA para Backend Python**

Agente especializado en testing, QA y chaos engineering para sistemas backend Python.

**Capacidades:**
- Testing unitario con Pytest
- Testing de integración
- Testing end-to-end
- Chaos engineering
- Cobertura de código (>90% objetivo)
- Testing de performance
- Testing de seguridad
- Generación de fixtures y mocks
- Análisis de código estático

**Cuándo usar:**
- Escribir tests unitarios e integración
- Aumentar cobertura de código
- Implementar chaos engineering
- Validar seguridad del código
- Testing de performance

#### 4. Reviewer Backend Python Agent (`[python-development/agents] reviewer-backend-py`)
**Code Review Automatizado para Backend Python**

Agente especializado en revisión de código que combina las perspectivas del Architect, Backend-Py y QA para proporcionar reviews completas de PRs.

**Capacidades:**
- Análisis de arquitectura y patrones de diseño
- Validación de calidad de código (type hints, SOLID, DRY)
- Revisión de tests y cobertura (>90% objetivo)
- Detección de vulnerabilidades de seguridad
- Evaluación de performance y queries
- Generación de feedback estructurado con scores
- Decisión de APPROVE/REQUEST_CHANGES

**Cuándo usar:**
- Code reviews automatizados en GitHub PRs
- Validación de calidad antes de merge
- Asegurar estándares de arquitectura
- Verificar cobertura de testing
- Auditorías de seguridad

#### 5. Reviewer Library Python Agent (`[python-development/agents] reviewer-library-py`)
**Code Review para Librerías Python**

Agente especializado en revisión de código para librerías Python, enfocado en API design, documentación y distribución de paquetes.

**Cuándo usar:**
- Revisión de PRs en proyectos de librería Python
- Validación de diseño de API pública
- Verificación de documentación y ejemplos
- Auditoría de estructura de paquete

#### 6. Backend Python Celery Skill (`[python-development/skills] backend-py-celery`)
**Desarrollo de APIs y Tareas Celery**

Skill ejecutable para desarrollo de rutas FastAPI y tareas programadas Celery con Clean Architecture.

**Capacidades:**
- Creación de endpoints FastAPI con dependency injection
- Implementación de tareas Celery programadas
- Generación de boilerplate para Clean Architecture
- Integración con repositorios centralizados

**Cuándo usar:**
- Crear nuevas rutas de API REST
- Implementar tareas programadas (cron jobs)
- Generar estructura de Clean Architecture

### Flutter Development Plugin

Agentes especializados para desarrollo Flutter/Dart.

#### 7. Reviewer Flutter App Agent (`[flutter-development/agents] reviewer-flutter-app`)
**Code Review para Aplicaciones Flutter**

Agente especializado en revisión de código Flutter, enfocado en widgets, state management y performance móvil.

**Capacidades:**
- Análisis de arquitectura de widgets
- Validación de state management patterns
- Optimización de performance
- Best practices de Flutter/Dart

**Cuándo usar:**
- Code reviews automatizados de Flutter PRs
- Validación de arquitectura de widgets
- Verificación de performance
- Auditoría de best practices móviles

## GitHub Workflows

Este repositorio incluye workflows de GitHub Actions reutilizables para automatizar procesos de CI/CD.

### Workflows Disponibles

#### Code Review Backend Python (`code-review-backend-py.yml`)

Workflow que automatiza el code review usando el agente `reviewer-backend-py` de Claude AI.

**Características:**
- ✅ Revisión automática de PRs
- ✅ Análisis de arquitectura, código y testing
- ✅ Aprobación/rechazo basado en criterios de calidad
- ✅ Bloqueo de merge si no cumple estándares
- ✅ Comentarios detallados en PR

**Requisitos:**
- Secret: `ANTHROPIC_API_KEY`
- Permisos: write para pull-requests

**Documentación completa:**
- [Arquitectura del Code Review Agent](./docs/CODE_REVIEW_AGENT_ARCHITECTURE.md)
- [Guía de Despliegue](docs/CI_CD_GUIDE_TO_CODE_REVIEW_AGENT.md)
- [README de Workflows](./git-workflows/README.md)

### Instalación de Workflows

#### Método 1: Script de Sincronización (Recomendado)

```bash
# Desde tu proyecto
./scripts/sync-workflows.sh

# Con repositorio personalizado
./scripts/sync-workflows.sh https://github.com/tu-empresa/workflows.git

# Con variable de entorno
WORKFLOWS_REPO=https://github.com/tu-empresa/repo.git ./scripts/sync-workflows.sh
```

El script te permite:
1. Ver todos los workflows disponibles
2. Seleccionar cuáles instalar
3. Copiarlos automáticamente a `.github/workflows/`
4. Ver qué secrets necesitas configurar

#### Método 2: Copia Manual

```bash
# Copiar workflow específico
cp git-workflows/code-review-backend-py.yml .github/workflows/

# Copiar todos los workflows
cp git-workflows/*.yml .github/workflows/
```

#### Método 3: Instalación Global

```bash
# Clonar en directorio home
git clone https://github.com/Grinest/agents.git ~/.claude-agents

# Crear alias
echo 'alias sync-workflows="~/.claude-agents/scripts/sync-workflows.sh"' >> ~/.bashrc
source ~/.bashrc

# Usar desde cualquier proyecto
cd /tu/proyecto
sync-workflows
```

### Configuración Post-Instalación

Después de instalar un workflow:

1. **Configurar Secrets**:
   ```
   Repositorio → Settings → Secrets → Actions → New secret
   ```
   - `ANTHROPIC_API_KEY`: Tu API key de Anthropic

2. **Configurar Permisos**:
   ```
   Settings → Actions → General → Workflow permissions
   ```
   - ✅ Read and write permissions
   - ✅ Allow GitHub Actions to create and approve pull requests

3. **Personalizar** (opcional):
   - Editar triggers en `.github/workflows/`
   - Ajustar modelos de Claude
   - Modificar criterios de revisión

Ver [documentación completa de workflows](./git-workflows/README.md) para más detalles.

## Instalación de Agentes y Skills

### Método Recomendado: Plugin Marketplace (2026)

El método moderno usa el sistema de plugins de Claude Code:

#### 1. Agregar el Marketplace

```bash
/plugin marketplace add bastion-core/agents
```

#### 2. Instalar Plugins

Instala los plugins que necesites:

```bash
# Agentes generales (arquitectura)
/plugin install general@seven-samurai-agents

# Desarrollo Python (backend, QA, review, skill Celery)
/plugin install python-development@seven-samurai-agents

# Desarrollo Flutter (review)
/plugin install flutter-development@seven-samurai-agents

# O instalar todo
/plugin install general@seven-samurai-agents python-development@seven-samurai-agents flutter-development@seven-samurai-agents
```

#### 3. Verificar Instalación

```bash
# Listar plugins instalados
/plugin list

# Ver detalles de un plugin
/plugin show python-development@seven-samurai-agents
```

### Configuración para Equipos

Para que todo el equipo tenga los mismos plugins automáticamente, agrega a `.claude/settings.json`:

```json
{
  "plugin_marketplaces": ["Grinest/agents"],
  "plugins": [
    "general@seven-samurai-agents",
    "python-development@seven-samurai-agents",
    "flutter-development@seven-samurai-agents"
  ]
}
```

Los miembros del equipo solo necesitan clonar el proyecto - los plugins se instalan automáticamente.

### Explorar Plugins Disponibles

```bash
# Ver todos los plugins del marketplace
/plugin marketplace browse seven-samurai-agents

# Buscar por tecnología
/plugin search python
/plugin search flutter
```

### Actualizar Plugins

```bash
# Actualizar un plugin específico
/plugin update python-development@seven-samurai-agents

# Actualizar todos los plugins del marketplace
/plugin update --marketplace seven-samurai-agents
```

### Método Alternativo: Instalación Manual

Si prefieres no usar el sistema de plugins, puedes copiar manualmente:

```bash
# Crear directorio de agentes
mkdir -p .claude/agents

# Copiar agentes deseados
cp claude-agents/plugins/general/agents/architect.md .claude/agents/
cp claude-agents/plugins/python-development/agents/backend-py.md .claude/agents/
cp claude-agents/plugins/python-development/skills/backend-py-celery.md .claude/agents/
```

> ⚠️ **Nota**: La instalación manual no tiene versionamiento ni auto-updates. Se recomienda usar el método de plugins.

## Uso de Agentes y Skills

Una vez instalados los plugins, los agentes y skills están disponibles automáticamente en Claude Code.

### Invocar Agentes

Los agentes se activan automáticamente según el contexto de tu solicitud:

```bash
# El agente architect se activa automáticamente
"Analiza la arquitectura de este proyecto y recomienda cómo agregar autenticación"

# El agente backend-py se activa para desarrollo
"Implementa un interactor para crear usuarios siguiendo Clean Architecture"

# El agente qa-backend-py se activa para testing
"Escribe tests unitarios para este interactor con >90% de cobertura"
```

### Invocar Skills

Los skills se invocan explícitamente con el prefijo `/`:

```bash
# Skill de desarrollo FastAPI + Celery
/backend-py-celery Create a new API endpoint for user authentication with JWT

# Ver ayuda de un skill
/backend-py-celery --help
```

### Listar Agentes y Skills Instalados

```bash
# Ver todos los plugins instalados
/plugin list

# Ver agentes disponibles
/agents list

# Ver skills disponibles
/skills list
```

## Estructura del Proyecto

```
claude-agents/
├── .gitignore
├── .github/
│   └── workflows/
│       └── validate-agents.yml           # CI para validar agentes
├── .idea/                                # IntelliJ IDEA config
├── README.md                             # Este archivo
├── plugins/                              # Sistema de plugins
│   ├── README.md                         # Documentación del sistema de plugins
│   ├── general/                          # Agentes agnósticos de lenguaje
│   │   ├── README.md
│   │   └── agents/
│   │       └── architect.md             # Agente de arquitectura
│   ├── python-development/              # Ecosistema Python
│   │   ├── README.md
│   │   ├── agents/
│   │   │   ├── backend-py.md           # Agente de backend Python
│   │   │   ├── qa-backend-py.md        # Agente de QA/testing
│   │   │   ├── reviewer-backend-py.md  # Agente de code review
│   │   │   └── reviewer-library-py.md  # Agente de review de librerías
│   │   └── skills/
│   │       └── backend-py-celery.md    # Skill FastAPI + Celery
│   └── flutter-development/             # Ecosistema Flutter
│       ├── README.md
│       └── agents/
│           └── reviewer-flutter-app.md  # Agente de review Flutter
├── docs/                                 # Documentación
│   ├── CI_CD_GUIDE_TO_CODE_REVIEW_AGENT.md  # Guía de CI/CD
│   ├── CODE_REVIEW_AGENT_ARCHITECTURE.md    # Arquitectura del reviewer
│   ├── QUICKSTART_TO_USE_AGENTS.md          # Inicio rápido
│   └── TESTING_STRATEGY.md                  # Estrategia de testing
├── git-workflows/                        # Workflows reutilizables
│   ├── README.md                        # Documentación de workflows
│   ├── python/
│   │   └── code-review-backend-py.yml  # Workflow de code review Python
│   └── flutter/
│       └── code-review-flutter-app.yml # Workflow de code review Flutter
└── scripts/                              # Scripts de utilidad
    ├── sync-workflows.sh                # Script de sincronización de workflows
    ├── validate-agents.sh               # Script de validación de agentes
    └── README.md                        # Documentación de scripts
```

### Arquitectura de Plugins

El proyecto usa una arquitectura de plugins que organiza agentes y skills por dominio tecnológico:

- **`plugins/general/`**: Agentes agnósticos que funcionan en cualquier lenguaje
- **`plugins/python-development/`**: Ecosistema completo Python (agentes + skills)
- **`plugins/flutter-development/`**: Ecosistema Flutter (agentes + skills)

Cada plugin contiene:
- **`agents/`**: Archivos .md con instrucciones y personalidad de agentes
- **`skills/`**: Archivos .md con capacidades ejecutables (herramientas + funciones)
- **`README.md`**: Documentación específica del plugin

## Configuración para Equipos y Empresas

### Opción Recomendada: Marketplace Privado

Crea tu propio marketplace privado para tu empresa:

#### 1. Fork este repositorio
```bash
# Fork a tu organización
https://github.com/tu-empresa/claude-agents
```

#### 2. Personaliza plugins
```bash
# Agrega agentes específicos de tu empresa
mkdir plugins/company-standards
# Agrega tus agentes personalizados
```

#### 3. Configura en el proyecto
```json
// .claude/settings.json
{
  "plugin_marketplaces": ["tu-empresa/claude-agents"],
  "plugins": [
    "general@seven-samurai-agents",
    "python-development@seven-samurai-agents",
    "company-standards@seven-samurai-agents"
  ]
}
```

#### 4. Commitea la configuración
```bash
git add .claude/settings.json
git commit -m "Add Claude Code plugin configuration"
```

Todo el equipo obtiene automáticamente los mismos plugins al clonar el proyecto.

### Marketplace Público + Plugins Privados

Combina este marketplace público con plugins privados de tu empresa:

```json
// .claude/settings.json
{
  "plugin_marketplaces": [
    "Grinest/agents",        // Público
    "tu-empresa/private-agents"         // Privado
  ],
  "plugins": [
    "python-development@seven-samurai-agents",  // Del público
    "company-standards@private-agents"   // Del privado
  ]
}
```

### Configuración por Usuario (Opcional)

Para configuración personal adicional:

```bash
# Cada desarrollador puede agregar marketplaces adicionales
/plugin marketplace add usuario/personal-agents

# E instalar plugins personales
/plugin install my-utils@personal-agents
```

## Crear Nuevos Agentes

### Estructura de un Agente

Cada agente es un archivo Markdown con frontmatter YAML, organizado dentro de la estructura de plugins:

```markdown
---
name: agent-name
description: Brief description of the agent
model: inherit
color: blue
---

# Agent Title

Your agent prompt here...
```

### Campos del Frontmatter

- `name`: Identificador único del agente (kebab-case)
- `description`: Descripción breve (1 línea)
- `model`: Modelo a usar (`inherit`, `sonnet`, `opus`, `haiku`)
- `color`: Color para la UI (`blue`, `green`, `yellow`, `red`, `purple`, `cyan`)

### Agregar un Nuevo Agente a un Plugin Existente

```bash
# 1. Crear el archivo del agente
touch plugins/python-development/agents/nuevo-agente.md

# 2. Agregar frontmatter y contenido
# Ver ejemplo abajo

# 3. Validar el agente
./scripts/validate-agents.sh

# 4. Actualizar README del plugin
# Editar plugins/python-development/README.md
```

### Crear un Nuevo Plugin

Para crear un nuevo plugin (ej: `javascript-development`):

```bash
# 1. Crear estructura
mkdir -p plugins/javascript-development/agents
mkdir -p plugins/javascript-development/skills

# 2. Crear README del plugin
touch plugins/javascript-development/README.md

# 3. Agregar agentes
touch plugins/javascript-development/agents/frontend-react.md

# 4. Validar
./scripts/validate-agents.sh
```

### Ejemplo de Agente

```markdown
---
name: frontend-react
description: React frontend development agent specializing in TypeScript and modern React patterns
model: inherit
color: cyan
---

# Frontend React Agent

You are a specialized React frontend development agent...
```

Ver [documentación de plugins](./plugins/README.md) para más detalles sobre convenciones y estructura.

## Contribuir

### Agregar un Nuevo Agente

1. Fork este repositorio
2. Crea un nuevo archivo en `plugins/[plugin-name]/agents/` o `plugins/[plugin-name]/skills/`
3. Agrega el agente/skill a `plugin.json` del plugin
4. Prueba el agente localmente
5. Actualiza el README del plugin
6. Crea un Pull Request con descripción detallada

### Mejorar un Agente Existente

1. Fork el repositorio
2. Modifica el agente en `plugins/[plugin-name]/agents/`
3. Documenta los cambios
4. Incrementa la versión en `plugin.json` si es necesario
5. Crea un Pull Request

### Reportar Issues

Si encuentras problemas:

1. Verifica que no exista un issue similar
2. Crea un nuevo issue con:
   - Descripción clara del problema
   - Pasos para reproducir
   - Comportamiento esperado vs actual
   - Logs relevantes

## Casos de Uso

### Startup con Clean Architecture

```bash
# 1. Agregar marketplace y instalar plugins
/plugin marketplace add Grinest/agents
/plugin install general@seven-samurai-agents python-development@seven-samurai-agents

# 2. Usar el agente de arquitectura
"Analiza este proyecto y recomienda la mejor forma de implementar un sistema de autenticación"

# 3. Usar el agente de backend
"Implementa el sistema de autenticación siguiendo las recomendaciones del arquitecto"

# 4. Usar skill para crear endpoint
/backend-py-celery Create authentication endpoint with JWT tokens
```

### Empresa con Repositorio Privado

```bash
# 1. Crear fork privado para la empresa
# GitHub: Fork Grinest/agents a empresa/claude-agents

# 2. Personalizar plugins
git clone git@github.com:empresa/claude-agents.git
cd claude-agents
# Agregar plugins personalizados...

# 3. Configurar en proyectos de la empresa
# En cada proyecto: .claude/settings.json
{
  "plugin_marketplaces": ["empresa/claude-agents"],
  "plugins": ["python-development@seven-samurai-agents"]
}

# 4. Los agentes personalizados están disponibles automáticamente
```

### Freelancer con Múltiples Clientes

```bash
# Cliente A - Configuración en .claude/settings.json del proyecto
{
  "plugin_marketplaces": ["cliente-a/agents"],
  "plugins": ["python-development@seven-samurai-agents"]
}

# Cliente B - Configuración en .claude/settings.json del proyecto
{
  "plugin_marketplaces": ["cliente-b/agents"],
  "plugins": ["javascript-development@seven-samurai-agents"]
}

# Cambiar entre proyectos automáticamente
cd ~/projects/cliente-a  # Usa plugins de cliente A
cd ~/projects/cliente-b  # Usa plugins de cliente B
# Los plugins se cargan automáticamente según el proyecto
```

## Actualización de Plugins

Los plugins se pueden actualizar fácilmente:

```bash
# Actualizar un plugin específico
/plugin update python-development@seven-samurai-agents

# Actualizar todos los plugins de un marketplace
/plugin update --marketplace seven-samurai-agents

# Ver versiones disponibles
/plugin show python-development@seven-samurai-agents
```

### Auto-updates (Opcional)

Configura auto-updates para mantener plugins actualizados automáticamente:

```json
// .claude/settings.json
{
  "plugin_auto_update": true,
  "plugin_marketplaces": ["Grinest/agents"]
}
```

## Requisitos

- **Claude Code CLI** (2026 o superior)
- **Git** (para marketplaces en GitHub/GitLab)
- Internet (para instalar plugins remotos)

## Solución de Problemas

### Los plugins no aparecen

```bash
# Verificar plugins instalados
/plugin list

# Verificar marketplaces configurados
/plugin marketplace list

# Reinstalar plugin
/plugin uninstall python-development@seven-samurai-agents
/plugin install python-development@seven-samurai-agents
```

### Error al agregar marketplace

1. Verifica que el repositorio exista y sea público (o tengas acceso)
2. Verifica que contenga `.claude-plugin/marketplace.json`
3. Para repos privados, configura autenticación Git (SSH o tokens)

```bash
# Ver detalles del error
/plugin marketplace add owner/repo --verbose
```

### Los agentes no se activan automáticamente

1. Verifica que el plugin esté instalado: `/plugin list`
2. Los agentes se activan por contexto - prueba con una solicitud específica
3. Para skills, usa el prefijo `/`: `/backend-py-celery --help`
4. Reinicia Claude Code si es necesario

### Conflictos de nombres entre plugins

Los plugins tienen namespaces automáticos para evitar conflictos:

```bash
# Si dos plugins tienen el mismo skill, especifica el namespace
/python-development:backend-py-celery
/my-plugin:backend-py-celery
```

## Recursos

- [Guía Rápida](docs/QUICKSTART_TO_USE_AGENTS.md) - Inicio rápido con agentes y workflows
- [Documentación de Scripts](./scripts/README.md) - Documentación de scripts de sincronización
- [Documentación de Workflows](./git-workflows/README.md) - Workflows de GitHub Actions
- [Claude Code Documentation](https://docs.anthropic.com/claude/docs) - Documentación oficial de Claude
