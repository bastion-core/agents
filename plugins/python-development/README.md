# Python Development Plugin

Specialized agents and skills for Python development, covering backend systems, testing, code review, and task automation.

## Available Agents

### Development Agents

#### backend-py.md
Backend Python Development Agent specializing in Clean Architecture and Hexagonal Architecture for scalable and maintainable backend systems. Ideal for building REST APIs, domain logic, and infrastructure layers.

**Use cases**:
- Building FastAPI/Django REST APIs
- Implementing Clean Architecture patterns
- Designing domain models and business logic
- Creating repository patterns and data access layers

#### qa-backend-py.md
Quality Assurance agent for Python backend applications with comprehensive testing strategies. Focuses on unit tests, integration tests, and test-driven development.

**Use cases**:
- Writing pytest test suites
- Creating test fixtures and mocks
- Implementing integration tests
- Ensuring code coverage

### Code Review Agents

#### reviewer-backend-py.md
Comprehensive code reviewer for Python backend PRs, combining architecture analysis, code quality validation, and testing coverage assessment. Uses strict scoring criteria and provides actionable feedback.

**Use cases**:
- Automated PR reviews in CI/CD
- Architecture compliance validation
- Code quality and best practices enforcement
- Test coverage analysis

#### reviewer-library-py.md
Specialized code reviewer for Python library development with focus on API design, documentation, and package distribution.

**Use cases**:
- Reviewing Python library PRs
- Validating public API design
- Ensuring documentation quality
- Checking package structure

#### reviewer-alembic-backend-py.md
Code reviewer for Alembic migration job projects (`db-migrator`-style repositories). Applies a different quality bar per directory: strict chain/DDL validation for `alembic/versions/`, pragmatic security-first criteria for `scripts/`, and full Clean Architecture + unit test requirements for `src/`. Uses the `backend-py-alembic`, `backend-py` and `qa-backend-py` skills.

**Use cases**:
- Automated PR reviews for database migration repositories
- Revision chain integrity validation (single head, correct `down_revision`)
- `upgrade()`/`downgrade()` symmetry and DDL safety on populated tables
- Index cost/benefit analysis

**Testing policy**: migration files under `alembic/versions/` and one-off scripts under `scripts/` are exempt from unit tests — they are validated by structure, safety criteria and the `upgrade → downgrade → upgrade` cycle. Unit tests are required only for `src/`.

## Available Skills

### backend-py.md
General Python backend standards, framework-agnostic: layering rules for Clean/Hexagonal Architecture, SOLID, dependency injection, typing, error handling, configuration and secrets, persistence and performance criteria.

**Use cases**:
- Shared baseline for writing and reviewing code under `src/`
- Layer violation and dependency direction checks
- Quality checklist for backend PRs

### backend-py-alembic.md
Quality criteria for Alembic migration job projects: revision chain integrity, revision file structure, `upgrade`/`downgrade` symmetry, DDL safety, enums, indexing rules and data migrations.

**Use cases**:
- Analyzing and reviewing `alembic/versions/`
- Validating `alembic.ini` / `env.py` configuration
- Verifying migrations with `alembic heads` / `check` and the round-trip cycle

### backend-py-celery.md
Executable skill for developing FastAPI routes and Celery scheduled tasks with Clean Architecture. Combines agent capabilities with specific tools for creating API endpoints and background tasks.

**Use cases**:
- Creating new FastAPI routes with dependency injection
- Implementing Celery scheduled tasks
- Building API endpoints with repository patterns
- Generating boilerplate for Clean Architecture components

## Usage

### Installing Agents

```bash
# Install all Python agents
./scripts/sync-agents.sh
# Select: backend-py, qa-backend-py, reviewer-backend-py, reviewer-library-py

# Or install individually
./scripts/sync-agents.sh
# Select: backend-py
```

### Using Skills

Skills are invoked within Claude Code sessions:

```bash
# Use the backend-py-celery skill
/backend-py-celery
```

## Architecture Focus

All Python agents follow Clean Architecture principles:

- **Domain Layer**: Business logic and entities
- **Application Layer**: Use cases and services
- **Infrastructure Layer**: External dependencies (databases, APIs)
- **Presentation Layer**: API routes and controllers

### Clean Architecture Benefits

- Clear separation of concerns
- Testable business logic
- Independent of frameworks
- Database agnostic
- Easy to maintain and extend

## Testing Philosophy

Python QA agents emphasize:

- **Test-Driven Development**: Write tests before implementation
- **Coverage Goals**: Aim for 80%+ code coverage
- **Test Pyramid**: More unit tests, fewer integration tests
- **Fixtures**: Reusable test data and mocks
- **Isolation**: Tests should be independent

## Code Review Criteria

Python reviewers evaluate PRs on:

1. **Architecture Compliance** (30%):
   - Clean Architecture adherence
   - Separation of concerns
   - Dependency inversion

2. **Code Quality** (30%):
   - Readability and maintainability
   - Python best practices (PEP 8)
   - Error handling

3. **Testing** (25%):
   - Test coverage
   - Test quality and assertions
   - Edge case handling

4. **Documentation** (15%):
   - Docstrings
   - Type hints
   - README updates

## Organization

Python agents are organized to support the full development lifecycle:

1. **Plan**: Use architect agent for system design
2. **Develop**: Use backend-py agent for implementation
3. **Test**: Use qa-backend-py agent for quality assurance
4. **Review**: Use reviewer agents for PR validation
5. **Automate**: Use skills for repetitive tasks

## Integration with Git Workflows

Python reviewer agents integrate with GitHub Actions:

```yaml
# .github/workflows/python-code-review.yml
- name: Review Python Backend PR
  uses: ./.github/actions/code-review
  with:
    agent: reviewer-backend-py
```

See `git-workflows/python/` for complete workflow configurations.
