# Claude Agents Marketplace

This is a plugin marketplace for Claude Code containing specialized agents and skills for development workflows.

## Installation

Add this marketplace to your Claude Code:

```bash
/plugin marketplace add bastion-core/agents
```

## Available Plugins

### 🏗️ general
Language-agnostic agents for software architecture and system design.

**Install:**
```bash
/plugin install general@seven-samurai-agents
```

**Contains:**
- `architect` - Software architecture specialist for system design and planning

---

### 🐍 python-development
Python backend development agents and skills with Clean Architecture, FastAPI, and Celery.

**Install:**
```bash
/plugin install python-development@seven-samurai-agents
```

**Contains:**
- `backend-py` - Backend Python development with Clean Architecture
- `qa-backend-py` - QA and testing specialist for Python backend
- `reviewer-backend-py` - Code review agent for Python backend PRs
- `reviewer-library-py` - Code review agent for Python library projects
- `backend-py-celery` (skill) - FastAPI routes and Celery tasks development

---

### 📱 flutter-development
Flutter and Dart development agents for mobile app development and code review with Clean Architecture, BLoC+Freezed, and Result<T> error handling.

**Install:**
```bash
/plugin install flutter-development@seven-samurai-agents
```

**Contains:**
- `mobile-flutter` - Flutter mobile development with Clean Architecture and Feature-Based Modularization
- `reviewer-mobile-flutter` - Code review agent for Flutter mobile PRs
- `reviewer-flutter-app` - Code review agent for Flutter application PRs (legacy)

---

### ⚡ nextjs-development
Next.js frontend development agents for building and reviewing apps with Two-layer Architecture, Zustand stores, DataAccess pattern, and Either monad error handling.

**Install:**
```bash
/plugin install nextjs-development@seven-samurai-agents
```

**Contains:**
- `frontend-nextjs` - Next.js frontend development with Two-layer Architecture
- `reviewer-frontend-nextjs` - Code review agent for Next.js frontend PRs

---

## Usage

After installing plugins, agents and skills become available in Claude Code:

### Using Agents
Agents are automatically available based on your project context. Simply describe your task and Claude will use the appropriate agent.

### Using Skills
Skills can be invoked with the `/` prefix:

```bash
/backend-py-celery Create a new API endpoint for user authentication
```

## Browse Plugins

List all available plugins from this marketplace:

```bash
/plugin list
```

Show details of a specific plugin:

```bash
/plugin show python-development@seven-samurai-agents
```

## Updates

Check for plugin updates:

```bash
/plugin update python-development@seven-samurai-agents
```

Update all plugins from this marketplace:

```bash
/plugin update --marketplace claude-agents
```

## Contributing

To add new plugins to this marketplace, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## License

MIT License - See [LICENSE](../LICENSE) for details.
