---
name: backend-py-alembic
description: Quality criteria to analyze and review Python Alembic migration jobs — revision chain integrity, upgrade/downgrade symmetry, DDL safety, indexing and data migrations under alembic/versions.
---

# Alembic Migration Job Standards Skill

Quality criteria for **db-migrator style projects**: standalone Python jobs whose responsibility is
to version and apply a database schema with Alembic, plus a small amount of seed/administrative
code around it.

Use this skill to **analyze and review** the migration layer. For creating migrations end-to-end
across the two-repository pattern, use `migrations-creator-py`. For the general backend rules under
`src/`, use `backend-py`. For tests, use `qa-backend-py`.

> **Testing rule for this project type**: files under `alembic/versions/` are **exempt from unit
> tests**. They are validated by structure, quality criteria and the upgrade/downgrade cycle —
> never by pytest coverage. Never request unit tests for a revision file.

---

## 1. Expected Project Layout

```
db-migrator-job/
├── alembic.ini                  # Alembic config (script_location, logging, url placeholder)
├── alembic/
│   ├── env.py                   # Engine/URL wiring, offline/online modes
│   ├── script.py.mako           # Revision template
│   ├── README
│   └── versions/                # ONE file per revision — the reviewed surface
│       └── {revision}_{slug}.py
├── scripts/                     # One-off administrative / backfill scripts
├── src/                         # Job code: seeds, interactors, settings, db connection
│   ├── application/
│   ├── domain/
│   └── infrastructure/
├── tests/                       # Tests for src/ and reusable scripts/ logic only
├── main.py                      # Job entrypoint
├── entrypoint.sh                # Container entrypoint (usually: alembic upgrade head + seeds)
├── Dockerfile
└── requirements.txt / Pipfile
```

### 1.1 — `alembic.ini` and `env.py`

- ✅ The database URL comes from an environment variable, resolved in `env.py`.
  A real URL committed in `alembic.ini` is a **critical** security defect.
- ✅ `%` in the URL is escaped (`url.replace('%', '%%')`) before `set_main_option`, otherwise
  ConfigParser interpolation breaks passwords containing `%`.
- ✅ Values read from `.env` are stripped of surrounding quotes when the pipeline may inject them.
- ✅ Both `run_migrations_offline()` and `run_migrations_online()` remain functional.
- ✅ `target_metadata = None` is acceptable and expected when migrations are handwritten (no
  `--autogenerate`). Do not request autogenerate wiring in that case.
- ❌ No credentials, hostnames, or environment-specific defaults hardcoded in `env.py`.

---

## 2. Revision Chain Integrity (BLOCKING)

The chain is the single most important invariant of a migration repository.

| Check | Rule |
|---|---|
| **Single head** | `alembic heads` must return exactly one revision. Two heads = broken deploy. |
| **`down_revision`** | Must point to the previous head at branch time, never to `None` (except the very first migration) and never to an arbitrary older revision. |
| **Uniqueness** | `revision` IDs must be unique across `alembic/versions/`. |
| **Filename** | `{revision_id}_{descriptive_slug}.py`; the `revision` variable inside must match the filename prefix. |
| **No edits to merged revisions** | Applied migrations are immutable. Fix forward with a new revision. |
| **No orphans** | Every revision must be reachable from the head walking `down_revision`. |

```python
# ✅ Required identifier block in every revision file
revision = '53ab0d98dbd3'
down_revision = '9200b29f9fdd'
branch_labels = None
depends_on = None
```

**How to verify a PR:**

```bash
alembic heads            # expect exactly ONE head
alembic history --verbose | head -30
alembic check            # detects a divergent chain (Alembic 1.9+)
```

When several PRs add migrations in parallel, the last one merged **must rebase** its
`down_revision` onto the new head. Flag any PR whose `down_revision` no longer points at the
current head of the target branch as a **blocking merge conflict**.

---

## 3. Revision File Structure

```python
"""create_payment_schemas

Revision ID: 53ab0d98dbd3
Revises: 9200b29f9fdd
Create Date: 2026-08-03 14:10:20.957628

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = '53ab0d98dbd3'
down_revision = '9200b29f9fdd'
branch_labels = None
depends_on = None


def upgrade() -> None:
    ...


def downgrade() -> None:
    ...
```

**Required:**
- Module docstring with the message, `Revision ID`, `Revises`, `Create Date`.
- The four identifier variables, in order.
- Both `upgrade()` and `downgrade()` with `-> None` annotations.
- Only Alembic/SQLAlchemy imports plus, when the project uses it, shared migration helpers.

**Two accepted implementation styles** — be consistent with the repository:

1. **Inline**: DDL written directly with `op.*` in the revision file.
2. **Delegated (two-repo pattern)**: the revision file imports prefixed
   `{migration}_revision`, `{migration}_down_revision`, `{migration}_upgrade`,
   `{migration}_downgrade` from the shared library and only wires them.
   In this style the revision file must contain **no DDL logic of its own**.

Mixing both styles in the same revision is a defect.

---

## 4. Upgrade / Downgrade Symmetry (BLOCKING)

Every `upgrade()` must have a `downgrade()` that fully reverses it.

| upgrade does | downgrade must do |
|---|---|
| `create_table` | `drop_table` |
| `add_column` | `drop_column` |
| `drop_column` | `add_column` with the original type, nullability and a `server_default` |
| `alter_column` | `alter_column` back to `existing_type`/nullability |
| `create_index` | `drop_index(..., table_name=...)` |
| `create_unique_constraint` | `drop_constraint(..., type_='unique')` |
| `Enum.create(...)` | `sa.Enum(name=...).drop(op.get_bind(), checkfirst=True)` |
| `op.execute("CREATE ...")` | matching `op.execute("DROP ...")` |

**Ordering rules in `downgrade()`:**

1. Drop indexes/constraints **before** dropping the columns or tables they reference.
2. Drop child tables (holding the FK) **before** parent tables.
3. Drop enums **after** removing the columns that use them.

```python
# ❌ BLOCKING — irreversible
def downgrade() -> None:
    pass

# ❌ BLOCKING — drops parent before child (FK violation)
def downgrade() -> None:
    op.drop_table('users')
    op.drop_table('user_debts')   # references users.id

# ✅ Correct order
def downgrade() -> None:
    op.drop_index('ix_user_debts_user_id', table_name='user_debts')
    op.drop_table('user_debts')
    op.drop_table('users')
```

**Idempotent cycle**: `upgrade → downgrade → upgrade` must leave the schema identical.
When a downgrade is genuinely lossy (dropping a column destroys data), it is still required, and
the loss must be documented in the module docstring.

---

## 5. DDL Safety Rules

### 5.1 — NOT NULL on an existing table

```python
# ❌ Fails on any table with existing rows
op.add_column('users', sa.Column('provider', sa.String(50), nullable=False))

# ✅ server_default backfills existing rows
op.add_column('users', sa.Column('provider', sa.String(50), nullable=False, server_default='phone'))
```

For a NOT NULL column with no sensible default, use the three-step pattern:
add nullable → backfill with an `op.execute` UPDATE → `alter_column(nullable=False)`.

### 5.2 — Foreign keys

- Always declare the `ondelete` behaviour explicitly (`CASCADE`, `SET NULL`, `RESTRICT`).
  An implicit `NO ACTION` on a child table is a design smell — flag it.
- `SET NULL` requires the column to be `nullable=True`; `CASCADE` on a column that must always
  exist requires `nullable=False`. Mismatches between `ondelete` and nullability are defects.
- Referenced tables must already exist at that point in the chain (create parents first).

### 5.3 — Enums (PostgreSQL)

```python
# upgrade
status_enum = sa.Enum('ACTIVE', 'INACTIVE', name='user_status_enum')
status_enum.create(op.get_bind(), checkfirst=True)
op.add_column('users', sa.Column('status', status_enum, nullable=False, server_default='ACTIVE'))

# downgrade
op.drop_column('users', 'status')
sa.Enum(name='user_status_enum').drop(op.get_bind(), checkfirst=True)
```

- Native enums must be created explicitly before use in `add_column` (SQLAlchemy does not
  auto-create the type for `add_column`, unlike `create_table`).
- Adding a value to an existing enum requires `ALTER TYPE ... ADD VALUE` and **cannot** be run
  inside a transaction on older PostgreSQL versions — flag it.
- A `String` column plus a CHECK constraint (or application-level enum) is an acceptable
  alternative when the value set changes often. Be consistent with the repository's existing style.

### 5.4 — Types

| Type | Column definition | Notes |
|---|---|---|
| UUID | `UUID(as_uuid=True)` | From `sqlalchemy.dialects.postgresql`. Standard for PK/FK. |
| String | `sa.String(length=N)` | Prefer an explicit length; unbounded `sa.String()` needs justification. |
| Text | `sa.Text` | Long free-form text. |
| Money | `sa.Numeric(precision, scale)` | ❌ Never `sa.Float` for money. |
| Boolean | `sa.Boolean` | `server_default=sa.text('false')`. |
| DateTime | `sa.DateTime` | UTC at rest; use the project's timestamp helper. |
| JSON | `postgresql.JSONB` | ❌ Prefer JSONB over JSON in PostgreSQL. |
| Enum | `sa.Enum(..., name='...')` | See 5.3. |

### 5.5 — Timestamps and extensions

- Use the project's shared helper (e.g. `_add_timestamp_columns('table')`) for
  `created_at`/`updated_at` instead of declaring them by hand — inconsistent defaults across
  tables are a defect.
- Extensions must be created idempotently: `op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')`.

### 5.6 — Locking and large tables

- Adding a column with a **volatile** default, changing a column type, or adding a NOT NULL
  constraint rewrites the table and holds an ACCESS EXCLUSIVE lock. On large tables, flag it and
  suggest the incremental pattern.
- `CREATE INDEX CONCURRENTLY` cannot run inside a transaction; it requires
  `op.get_context().autocommit_block()` (or `isolation_level='AUTOCOMMIT'`). Plain `create_index`
  on a large hot table is acceptable for this project size but should be called out.

---

## 6. Indexing Criteria

> Every index speeds up reads and taxes every write. Only create indexes justified by real,
> frequent queries.

### Create an index when

| Criterion | Example |
|---|---|
| UNIQUE business constraint | `idempotency_key`, `email`, `external_id` |
| FK used in frequent WHERE/JOIN | `user_id` on a table always filtered by user |
| High-selectivity column filtered often | UUIDs, emails, timestamps |
| Frequent multi-column query | `(user_id, created_at)` for "my recent payments" |
| ORDER BY of a paginated query | `created_at DESC` with LIMIT/OFFSET |

### Do NOT create an index when

| Criterion | Example |
|---|---|
| Low cardinality | `status` with 6 values, booleans, `currency` with 1-2 values |
| Small table (< 10K rows) | Seq scan is as fast or faster |
| Rarely filtered column | JSONB read but never searched |
| Redundant with a compound | `(user_id)` when `(user_id, status)` already exists |
| Write-heavy, read-rare table | Logs, audit trails, event sourcing |

### Compound index rules

1. **Leftmost prefix**: `(A, B, C)` serves `A`, `A+B`, `A+B+C` — not `B` or `C` alone.
2. Order by descending selectivity (most selective column first).
3. Maximum 3-4 columns.

### Limits and naming

- **Max 3 indexes at table creation**, UNIQUE constraints included. More requires a stated query
  and its `EXPLAIN ANALYZE`.
- Lookup/config tables: 1-2 indexes. High-write tables: 0-1.
- Don't optimize preventively — add the index when there is evidence (pg_stat_statements, seq scan).

| Object | Pattern |
|---|---|
| Index | `idx_{table}_{col}` / `idx_{table}_{col1}_{col2}` (or the repo's existing `ix_` prefix — be consistent) |
| Unique constraint | `uq_{table}_{col}` |
| Foreign key | `fk_{table}_{col}` |
| Check constraint | `ck_{table}_{rule}` |

```python
# ✅ Compound for a real query, covers user_id alone
op.create_index('idx_payments_user_id_status', 'payments', ['user_id', 'status'])
# ❌ Redundant with the compound above
op.create_index('idx_payments_user_id', 'payments', ['user_id'])
# ❌ Low cardinality
op.create_index('idx_payments_status', 'payments', ['status'])
```

Unnamed constraints (letting the DB auto-generate a name) make `downgrade()` fragile — always
pass an explicit `name=`.

---

## 7. Data Migrations Inside Revisions

```python
# ✅ Parameterized, bounded, reversible-aware
op.execute(
    sa.text("UPDATE users SET provider = :value WHERE provider IS NULL"),
    {"value": "phone"},
)
```

- ❌ f-string / `%`-formatted SQL built from variables — **critical** SQL injection defect, even
  in a migration.
- ✅ Keep heavy backfills out of the schema migration when they can run for minutes: prefer a
  script under `scripts/` and keep the revision fast, or batch the UPDATE.
- ✅ A data migration must state in the docstring whether it is reversible.
- ❌ Never mix an unrelated data backfill with a schema change in the same revision.

---

## 8. Migration Naming

| Operation | Message format |
|---|---|
| Create table | `create_{table}_table` |
| Drop table | `drop_{table}_table` |
| Add column | `add_{column}_to_{table}_table` |
| Remove column | `remove_{column}_from_{table}_table` |
| Modify column | `modify_{column}_in_{table}_table` |
| Constraint/index | `add_{constraint}_to_{table}_table` |
| Multiple related changes | `add_{x}_and_{y}_in_{table}_table` |

One migration = **one logical change**. Unrelated changes belong in separate revisions; a single
cohesive feature spanning several related tables (e.g. a payments schema) is acceptable in one
revision when the tables are created together and share FKs.

---

## 9. Anti-Patterns (flag every occurrence)

1. `downgrade()` with `pass` or a partial reversal.
2. `down_revision` not pointing at the current head / two heads in the branch.
3. Editing a revision that is already applied in a shared environment.
4. Raw SQL strings for DDL that Alembic operations already express (`op.create_table`, etc.).
5. Adding `nullable=False` to an existing table without `server_default`.
6. Enum created implicitly, or not dropped in `downgrade()`.
7. Indexes dropped after their table/column in `downgrade()`.
8. Hand-rolled `created_at`/`updated_at` instead of the shared helper.
9. Unnamed constraints and indexes.
10. `sa.Float` for monetary amounts.
11. Unrelated schema + data changes bundled together.
12. Secrets or environment-specific values inside a revision.
13. Dropping a column/table without documenting the data loss.
14. `op.execute` with interpolated user/config values.

---

## 10. Verification Commands

```bash
alembic heads                 # exactly one head expected
alembic history --verbose     # inspect the chain
alembic current               # applied revision in the target DB
alembic check                 # divergence detection (1.9+)

# Round-trip validation against a disposable database
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

A revision is considered validated when the round-trip runs clean — this replaces unit tests
for `alembic/versions/`.

---

## 11. Alembic Review Checklist

**Chain (blocking)**
- [ ] Exactly one head after the change
- [ ] `down_revision` points at the previous head
- [ ] `revision` unique and matching the filename prefix
- [ ] No modification of already-applied revisions

**Structure**
- [ ] Docstring header with message / Revision ID / Revises / Create Date
- [ ] Four identifier variables present
- [ ] `upgrade()` and `downgrade()` typed `-> None`
- [ ] Consistent with the repository's style (inline vs delegated)
- [ ] One logical change per revision, message follows the naming table

**Safety**
- [ ] `downgrade()` fully reverses `upgrade()`
- [ ] Drop order: indexes/constraints → child tables → parent tables → enums
- [ ] `server_default` for NOT NULL columns added to existing tables
- [ ] Explicit `ondelete` on every FK, consistent with nullability
- [ ] Enums created explicitly and dropped in downgrade
- [ ] Extensions created with `IF NOT EXISTS`
- [ ] Shared timestamp helper used
- [ ] `Numeric` for money, `JSONB` for JSON, explicit `String` lengths

**Indexes**
- [ ] Every index justified by a real query
- [ ] No low-cardinality or redundant indexes
- [ ] ≤ 3 indexes at table creation
- [ ] Explicit names following the repo's convention

**Data**
- [ ] Parameterized SQL only
- [ ] Backfills batched or moved to `scripts/`
- [ ] Data loss documented

**Explicitly NOT required**
- [ ] ❌ Unit tests for files in `alembic/versions/`
- [ ] ❌ Coverage targets for `alembic/versions/`
- [ ] ❌ Clean Architecture layering inside a revision file
