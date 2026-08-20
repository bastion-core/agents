# Next.js Development Plugin

Specialized agents for Next.js development and code review, covering two distinct
architectures. Pick the reviewer that matches the project — they enforce different, mutually
incompatible conventions:

| Project shape | Reviewers |
|---|---|
| **Frontend-only**, Two-layer (domain + infrastructure), Zustand + Either monad, DataAccess | `reviewer-frontend-nextjs` |
| **Fullstack**, Hexagonal (domain / application / infrastructure), App Router + Route Handlers + Prisma | `reviewer-fullstack-nextjs` and `reviewer-security-nextjs` |

## Available Agents

### Development Agents

#### frontend-nextjs.md
Frontend Next.js Development Agent specializing in Two-layer Architecture with Zustand stores and DataAccess pattern for production-ready Next.js apps.

**Use cases**:
- Implement new features following Two-layer Architecture (Domain + Infrastructure)
- Create Zustand stores divided by concern
- Build DataAccess classes with handleRequest<T>() and Either returns
- Implement discriminated union states with 'kind' field
- Set up i18n with next-intl
- Generate domain, store, DataAccess, and UI tests

**Architecture**: Two-layer Architecture (Domain + Infrastructure) enforced by eslint-plugin-hexagonal-architecture

### Code Review Agents

#### reviewer-frontend-nextjs.md
Comprehensive code reviewer for Next.js frontend PRs, combining architecture analysis, code quality validation, and testing coverage assessment.

**Review dimensions**:
- Architecture (30%): Two-layer compliance, dependency direction, module structure
- Code Quality (40%): TypeScript strict, Either pattern, Zustand stores, components, hooks
- Testing (30%): Domain tests (90%+), store tests (70%+), DataAccess tests (60%+), UI tests (50%+)

**Runs through**: `scripts/code-review.sh`

#### reviewer-fullstack-nextjs.md
Code reviewer for **fullstack** Next.js PRs where the frontend and the backend ship from the
same repository: App Router pages, Route Handlers under `src/app/api`, and business logic
under `src/core` organized as Hexagonal Architecture with Prisma adapters.

**Review dimensions**:
- Architecture (30%): hexagonal layering, `src/core` never imports `src/ui`, thin route
  handlers and pages, server-confirmed state ownership, single Prisma client
- Code Quality (40%): TypeScript strict, domain-error to HTTP mapping, dual validation
  (zod form + domain parser), zero hardcoded text including `aria-label`/`alt`/`sr-only`,
  design-system compliance, motion and touch-target rules, component reuse, dead code
- Testing (30%): correct suite placement, in-memory port doubles over mocked Prisma clients,
  integration tests against a real PostgreSQL, test-database safety locks

**Runs through**: `scripts/code-review.sh`

#### reviewer-security-nextjs.md
Security-focused reviewer for the same fullstack shape. Runs on the same PR as
`reviewer-fullstack-nextjs` without interfering with it.

**Review dimensions**:
- Auth & Access Control: per-route guard helpers (there is no `middleware.ts`, so an
  unguarded mutating route is a silent bypass), session cookie and HMAC token invariants,
  password hashing and timing, rate limiting, payment-webhook signature authentication
- Data Protection: secrets and `NEXT_PUBLIC_` exposure, internal error detail leaking to the
  client, PII (identity documents) never reaching a public surface, signed-upload boundary
  where the server builds the object path
- Input Validation: domain parsers at every boundary, injection (SQL, sort, XSS, open
  redirect, SSRF), mass assignment, server/client boundary, third-party and model output

**Model**: `claude-fable-5`
**Runs through**: `scripts/security-review.sh` — a separate script with its own PR-comment
marker and check-run name, so both reviewers can run on one PR without reading each other's
comments as their own previous review.
**Extra gate**: any CRITICAL finding forces `REQUEST_CHANGES` regardless of the scores.

## Technology Stack

### Frontend-only track (`frontend-nextjs`, `reviewer-frontend-nextjs`)

- **Framework**: Next.js 13+ (App Router) + TypeScript (strict)
- **State Management**: Zustand
- **Error Handling**: Either monad (Left/Right) with fold()
- **HTTP**: DataAccess pattern with handleRequest<T>()
- **UI**: shadcn/ui + Tailwind CSS + cn()
- **Forms**: React Hook Form + Zod
- **i18n**: next-intl
- **Testing**: Vitest + Testing Library

### Fullstack track (`reviewer-fullstack-nextjs`, `reviewer-security-nextjs`)

- **Framework**: Next.js 16 (App Router) + React 19 + TypeScript (strict)
- **Backend**: Route Handlers under `src/app/api` with shared `handle()` / `handleAsAdmin()`
  wrappers; no `middleware.ts`
- **Architecture**: Hexagonal — `src/core/<context>/{domain,application,infrastructure}`,
  enforced by `eslint-plugin-hexagonal-architecture`
- **Persistence**: Prisma 5 + PostgreSQL, single client cached on `globalThis`
- **State Management**: Zustand, server-hydrated, stores only what the server confirmed
- **Validation**: zod in the form, domain parsers on the server
- **UI**: shadcn (`base-nova` over `@base-ui/react`) + Tailwind 4 + Framer Motion
- **i18n**: next-intl with structurally identical locale files
- **Testing**: Vitest 4 — a unit suite with in-memory ports and an integration suite against
  a real PostgreSQL

## Usage

```bash
# Install agents
./scripts/sync-agents.sh
# Frontend-only project:  frontend-nextjs, reviewer-frontend-nextjs
# Fullstack project:      reviewer-fullstack-nextjs, reviewer-security-nextjs
```

## CI/CD

Workflow templates live in `git-workflows/nextjs/`:

| Template | Agent | Script | Check run |
|---|---|---|---|
| `code-review-frontend-nextjs.yml` | `reviewer-frontend-nextjs` | `code-review.sh` | Claude Code Review |
| `code-review-fullstack-nextjs.yml` | `reviewer-fullstack-nextjs` | `code-review.sh` | Claude Code Review |
| `code-review-security-nextjs.yml` | `reviewer-security-nextjs` | `security-review.sh` | Claude Security Review |

The fullstack and security templates are designed to run together on the same PR. Do **not**
install `code-review-frontend-nextjs.yml` alongside `code-review-fullstack-nextjs.yml`: both
use `code-review.sh`, which means the same comment marker and the same check-run name, and
they would overwrite each other.

Required repository secrets: `ANTHROPIC_API_KEY`, `AGENTS_GITHUB_TOKEN` (deploy key with read
access to this repository), and `VOLTOP_GITHUB_PAT` (or `GITHUB_TOKEN`) for posting comments.
