# Next.js Development Plugin

Specialized agents for Next.js frontend development and code review, enforcing Two-layer Architecture (Domain + Infrastructure), Zustand stores, DataAccess pattern, and Either monad error handling.

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

## Technology Stack

- **Framework**: Next.js 13+ (App Router) + TypeScript (strict)
- **State Management**: Zustand
- **Error Handling**: Either monad (Left/Right) with fold()
- **HTTP**: DataAccess pattern with handleRequest<T>()
- **UI**: shadcn/ui + Tailwind CSS + cn()
- **Forms**: React Hook Form + Zod
- **i18n**: next-intl
- **Testing**: Vitest + Testing Library

## Usage

```bash
# Install agents
./scripts/sync-agents.sh
# Select: frontend-nextjs, reviewer-frontend-nextjs
```
