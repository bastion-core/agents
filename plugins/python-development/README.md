# Python Development Plugin

Specialized agents and skills for Python development, covering backend systems, testing, code review, and task automation.

## Available Agents

### Development Agents

#### data-engineer-airflow.md
Data Engineer Agent for Apache Airflow, pandas, and dbt. Specializes in production-grade pipelines on modern data stacks with edge ingestion (APIs, CSV, JSON normalization in pandas) and warehouse transformations in dbt (staging -> intermediate -> marts via Cosmos/DbtTaskGroup).

**Use cases**:
- Designing and implementing thin Airflow DAGs with TaskFlow and Cosmos `DbtTaskGroup`
- Building edge normalization and ingestion with pandas without warehouse re-extraction
- Constructing dbt models (`.sql` + `schema.yml`) with explicit column contracts and tests
- Generating idempotent raw/staging upserts and warehouse data mart models

#### analytics-engineer.md
Analytics Engineer agent for in-warehouse dbt modeling, Ralph Kimball dimensional marts, the dbt Semantic Layer (MetricFlow), standardized metric definitions, and downstream exposures governance.

**Use cases**:
- Designing and implementing Kimball dimensional marts (`dim_*`, `fct_*`) with surrogate keys
- Defining Semantic Layer models, measures, and metrics (simple, derived, cumulative, conversion)
- Registering downstream BI dashboards and ML pipelines in `exposures.yml`
- Enforcing dbt model contracts and comprehensive generic/singular test suites

#### data-scientist.md
Senior Data Scientist and BI agent delivering hybrid exploratory data analysis, rigorous statistical hypothesis testing, tabular & deep learning models, systematic MLflow experiment tracking, low-latency FastAPI serving endpoints, SQL analytics, KPI definitions, and dashboard specifications.

**Use cases**:
- Hybrid EDA with modular Python code in `src/` and companion `.ipynb` notebooks
- Statistical hypothesis testing with effect size estimation (Cohen's d) and FDR corrections
- Leakage-free Scikit-learn pipelines, cross-validation (TimeSeriesSplit, GroupKFold)
- Production serving via FastAPI (lifespan model loading, Pydantic v2 validation) and ONNX
- Business Intelligence: defining formal KPI technical sheets and dashboard specifications

#### ml-engineer.md
Machine Learning Engineer and MLOps specialist for operating models in production. Owns Model Registry promotion (`champion`/`challenger`), CI/CD for models, continuous data/concept drift monitoring (PSI), automated retraining pipelines, and Feature Store integration (Feast).

**Use cases**:
- Promoting candidate models to `@champion` in MLflow Model Registry via automated quality gates
- Implementing CI/CD behavioral suites (invariance, directional monotonicity, and slice tests)
- Calculating Population Stability Index (PSI) and setting up automated incident alerts
- Orchestrating automated retraining DAGs in Apache Airflow with point-in-time correct datasets
- Managing feature schemas and online/offline parity in Feature Stores (Feast)

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

#### qa-data-engineer.md
Quality Assurance auditor for Apache Airflow DAGs and dbt data pipelines. Audits idempotency, backfill safety, retry and SLA policies, prevents the warehouse extraction anti-pattern with pandas, and validates dbt test coverage and build success.

**Use cases**:
- Auditing DAGs for duplicate run safety, idempotency, and deterministic date filters
- Enforcing the strict Edge-Only pandas rule (banning warehouse data extraction into pandas)
- Checking retries, exponential backoff, failure callbacks, and SLAs
- Validating dbt layers, schema tests (unique, not_null, relationships), and Cosmos orchestration

#### qa-data-scientist.md
Quality Assurance auditor for Machine Learning pipelines, statistical inference, and analytics. Audits for data leakage, bad train/validation splits, statistical mistakes (p-hacking, broken assumptions), missing effect sizes, and MLflow reproducibility.

**Use cases**:
- Detecting data leakage and target leakage across preprocessing and cross-validation splits
- Enforcing chronological splits (TimeSeriesSplit) or entity grouping (GroupKFold)
- Auditing hypothesis tests for normality/homoscedasticity checks and multiple comparison adjustments
- Verifying effect sizes (Cohen's d) and 95% confidence intervals on analytical claims
- Ensuring random seed reproducibility and MLflow experiment logging completeness

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

### data-engineer-airflow
Data Engineering standards for Apache Airflow: hybrid extraction (structured, JSONB with deterministic `record_hash`, object storage), Pandas cleaning with Fail-Fast data contracts, and physically optimized PostgreSQL bulk loading with session guardrails.

**Use cases**:
- Writing decoupled, composable pipeline Steps (`Extractor`, `Transformer`, `Loader`)
- Applying `data-architecture-postgre` tuple alignment (8-4-2-1-varlena) to pipeline tables
- Enforcing `audit.pipeline_runs` observability and row-level audit columns
- Dual connection resolution (Airflow `BaseHook` vs Pydantic `Settings`)

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
