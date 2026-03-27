# Architecture Overview

This document describes the architecture, folder structure, naming conventions, and development principles for the Next.js frontend application. The project uses a strict Two-layer Architecture (Domain + Infrastructure) enforced at the lint level.

## Architectural Pattern

The architecture is a **Two-layer Architecture** consisting of **Domain** and **Infrastructure** layers. This is enforced by `eslint-plugin-hexagonal-architecture` at error level.

There is no application layer, no UseCase classes, no Interactors, and no Ploc pattern. The data flow is:

```
Component -> Store -> DataAccess -> API
```

### Comparison with Backend Architecture

| Concept | Backend (Python) | Frontend (Next.js) |
|---------|-----------------|-------------------|
| Layers | 3 (Domain + Application + Infrastructure) | 2 (Domain + Infrastructure) |
| Orchestration | UseCase/Interactor classes | Stores call DataAccess directly |
| DI | Factory functions inject interfaces | DataAccess instantiated at module level |
| DataAccess | Repository interface in domain (Port) | Concrete class, no interface in domain |
| State | N/A (stateless) | Zustand stores with discriminated unions |
| Error handling | OutputErrorContext / OutputSuccessContext | Either monad with fold() |

## Layer Structure

### Domain Layer

- **Path**: `src/core/{module}/domain/`
- **Responsibility**: Pure business rules with zero external dependencies. Defines types, entities, DTOs, enums, constants, and state interfaces.
- **Contains**:
  - `entities/` -- Types and entities (pure TypeScript types)
  - `dtos/` -- Data Transfer Objects (request/response shapes)
  - `enums/` -- String enumerations for domain values
  - `states/` -- State interfaces for stores (discriminated unions)
  - `consts/` -- Domain constants
- **Allowed imports**:
  - Domain of the same module only
  - Shared types from `@core/common/domain`
- **Forbidden imports**:
  - `infrastructure/*`
  - React, Next.js, Zustand, Axios -- no external framework dependencies

### Infrastructure Layer

- **Path**: `src/core/{module}/infrastructure/`
- **Responsibility**: Technical layer containing data access (HTTP), stores, services with real logic, helpers, and UI components. Depends on domain.
- **Contains**:
  - `data-access/` -- HTTP calls (concrete class, no interface)
  - `services/` -- Only if real logic exists (e.g., DraftsService with localStorage + parsing)
  - `helpers/` -- Utility functions for patterns repeated 3+ times
  - `store/` -- Small Zustand stores per concern (~60-100 lines)
  - `ui/` -- screens, components, hooks, feature-table
- **Allowed imports**:
  - `domain/` of the same module
  - `@core/common` (any layer)
  - External libraries (React, Zustand, Axios, etc.)
- **Forbidden imports**:
  - `infrastructure/` of other modules (use domain types instead)

## Folder Structure

### Module Structure

Every feature/module follows this standard directory layout:

```
src/core/{module-name}/
├── domain/
│   ├── entities/          # Types and entities
│   ├── dtos/              # Data Transfer Objects
│   ├── enums/             # Enumerations
│   ├── states/            # State interfaces for stores
│   └── consts/            # Domain constants
└── infrastructure/
    ├── data-access/       # HTTP calls (concrete class, no interface)
    ├── services/          # Only if real logic exists
    ├── helpers/           # Utility functions for repeated patterns
    ├── store/             # Small stores per concern (~60-100 lines)
    └── ui/
        ├── screens/       # Screen components
        ├── components/    # Reusable components of the module
        ├── {feature}-table/  # Table + columns + toolbar
        └── hooks/         # Custom hooks
```

### Route Structure (App Router)

```
src/app/[locale]/{feature}/
├── page.tsx                      # Main page (server component wrapper)
├── [id]/
│   └── page.tsx                  # Detail page
└── layout.tsx                    # Optional feature layout
```

### Shared Code Location

Shared code across modules lives in `src/core/common/` following the same domain + infrastructure split.

### Path Aliases

```
~/*            -> ./src/*
@ui/*          -> ./src/ui/*
@components/*  -> ./src/components/*
@core/*        -> ./src/core/*
public/*       -> ./public/*
```

## Dependency Flow

```
infrastructure -> domain   (ALWAYS allowed)
domain -> infrastructure   (NEVER allowed)
```

Infrastructure depends on domain. Domain never imports from infrastructure. This is enforced by `eslint-plugin-hexagonal-architecture` at error level.

Cross-module imports follow the same rule: a module's infrastructure may import domain types from another module, but never another module's infrastructure.

## Key Architectural Decisions

### Technology Stack

| Technology | Role |
|-----------|------|
| Next.js 13+ (App Router) | Framework |
| TypeScript (strict mode) | Language |
| React 18+ | Runtime |
| Zustand | State management |
| Tailwind CSS v4 | Styling |
| React Hook Form + Zod | Forms and validation |
| Axios | HTTP client |
| Vitest + @testing-library/react | Testing |
| shadcn/ui (Radix UI primitives) | UI component library |
| next-intl | Internationalization |

### Import Order Convention

Imports are organized in this order:

```typescript
// 1. React / Next.js imports
import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'

// 2. Third-party libraries
import { create } from 'zustand'
import { useForm } from 'react-hook-form'

// 3. Path alias imports
import { apiAuth } from '@core/common/infrastructure/connections/ApiConnection'
import { Button } from '@components/ui/button'

// 4. Relative imports
import { DriversDataAccess } from '../data-access'
import { DriverCard } from './DriverCard'

// 5. Type imports
import type { Driver } from '../../domain/entities/Driver'
import type { GetDriversDto } from '../../domain/dtos/GetDriversDto'
```

### Formatting (Prettier)

```json
{
  "semi": false,
  "singleQuote": true,
  "tabWidth": 2,
  "printWidth": 80,
  "bracketSameLine": false,
  "singleAttributePerLine": true,
  "trailingComma": "es5"
}
```

### Service vs DataAccess vs Helper Decision Criteria

| Need | Use |
|------|-----|
| Only HTTP calls (fetch/post) | DataAccess |
| Real logic (localStorage, auto-save, parsing) | Service |
| Pattern repeated 3+ times | Helper |
| Simple logic not repeated | Inline in store |

## Anti-Patterns (Forbidden)

The following patterns are explicitly forbidden in this codebase:

### 1. Abstract Base Classes

Abstract base classes are not used unless 3+ classes extend them. Composition over inheritance is preferred, using simple interfaces.

### 2. Generic CRUD Abstractions

Premature `BaseCrudService<T>` or `BaseRepository<T>` generics are not created. Each DataAccess implements its specific methods.

### 3. Deep Inheritance Hierarchies

More than 1 level of inheritance is not used. Factory functions and function composition are preferred.

### 4. Fat Stores (500+ lines)

Monolithic stores with too many responsibilities are not created. Stores are split by concern into `useListStore`, `useDetailStore`, `useFormStore`, etc.

### 5. Use Cases Layer in Frontend

UseCase classes are not created for logic that is simply `set loading -> call API -> fold -> set state`. Stores call DataAccess directly, and orchestration logic lives in the store.

### 6. Application Layer in Frontend

An `application/` layer with Ploc, UseCase, Command, or DI factories is not created. Only two layers exist: domain (pure types) + infrastructure (stores, data-access, UI).

### 7. Unnecessary Middleware Layers

Intermediate layers are not added without clear justification. The chain is `Component -> Store -> DataAccess` with nothing in between.

### 8. DI Framework Overhead

InversifyJS, tsyringe, or other DI frameworks are not used. DataAccess is instantiated at module level with `new ModuleDataAccess(baseApiUrl)`.

### 9. Premature Optimization

`React.memo`, `useMemo`, `useCallback` are not added without measuring performance first. Optimization happens only when there is a measurable problem.

### 10. Over-Testing Implementation Details

Tests do not verify that `useState` was called or that render executed N times. Tests verify visible behavior of the component.

### Code Smells Reference

| Smell | Fix |
|-------|-----|
| `any` type | Use `unknown` and type guards |
| Magic strings | Use constants or enums |
| Hardcoded text in UI | Use `useTranslations()` |
| Direct API calls in components | Use store -> DataAccess flow |
| Business logic in components | Extract to hooks or helpers |
| Mutating state directly | Use `set()` from Zustand (immutable) |
| Importing from other module's infrastructure | Use domain types only |
| `console.log` in production | Use logger service |
| Nested ternaries | Extract to functions or use early returns |

## Naming Conventions

### File Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components | PascalCase.tsx | `DriverCard.tsx` |
| Hooks | camelCase.ts | `useDriversPreview.ts` |
| DataAccess | PascalCase.ts | `DriversDataAccess.ts` |
| Services | PascalCase.ts | `DriversService.ts` |
| Helpers | camelCase.ts | `normalizeResponse.ts` |
| Stores | PascalCase.ts | `DriversStore.ts` |
| Types/Entities | PascalCase.ts | `Driver.ts` |
| DTOs | PascalCase.ts | `GetDriversDto.ts` |
| Tests | PascalCase.test.ts(x) | `DriversStore.test.ts` (colocated next to source) |

### Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components | PascalCase | `function DriverCard()` |
| Hooks | camelCase with `use` prefix | `useDriversPreview` |
| Constants | UPPER_SNAKE_CASE | `LOADED_KIND` |
| Types | PascalCase | `DriverStatus` |
| Stores | camelCase with `use` prefix | `useDriversStore` |
| Functions | camelCase | `getDriversByStatus` |
| Private fields | camelCase (no `_` prefix) | `apiUrl` |

## Development Principles

### TypeScript Rules

- **Strict mode** is mandatory and always enabled.
- The `any` type is not used. `unknown` is used when the type is not known, then narrowed with type guards.
- **Discriminated unions** are used for states with a `kind` field as discriminator.
- **String enums** are used for domain values (e.g., `DriverStatus`).
- **Generics** are used for reusable utilities (e.g., `Either<E, A>`, `handleRequest<T>`).

### Domain Layer Purity

- Zero dependencies on React, Next.js, Zustand, or Axios in the domain layer.
- Only imports from `domain/` of the same module and `@core/common/domain`.
- Entities use `type` or `interface` (not classes with methods).
- No side effects in domain layer.

### Performance Guidelines

- `useMemo` is used only for expensive computations (filter/sort of large arrays).
- `useCallback` is used only when passing a handler as prop to a memoized component.
- `React.memo` is used only for components that re-render frequently without changes.
- Memoization is not applied by default; measurement comes first.
- Next.js App Router provides automatic code splitting by route.
- `dynamic()` import is used for heavy components (maps, charts).
- Modals and sidebars not initially visible are lazy-loaded.
- Server-side pagination is used for large lists.
- Search fields are debounced (300ms).
- `next/image` is used for automatic image optimization with defined `width` and `height`.

### Internationalization (i18n)

- **Library**: next-intl
- **Locales**: `["es", "en"]` with default locale `"es"`
- **Message files**: `src/messages/es.json`, `src/messages/en.json`
- All visible text in components uses `useTranslations()`, never hardcoded strings.
- Translation keys are organized by feature: `{feature}.{section}.{key}`.
- Translations are added in both `es.json` and `en.json`.

### Git Workflow

- **Commits**: Commitizen with `cz-emoji-conventional` (`npm run cm`)
- **Pre-commit**: Husky + lint-staged (Prettier, ESLint, hexagonal-architecture plugin)
- **Branch strategy**: `main` (production), `develop` (staging), `feature/{ticket-id}-{description}`, `fix/{ticket-id}-{description}`
