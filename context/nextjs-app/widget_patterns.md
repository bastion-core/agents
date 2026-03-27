# UI Component Patterns

This document describes the component architecture, templates, and guidelines for building UI components in the Next.js application. All components follow standardized patterns using shadcn/ui, Tailwind CSS, and specific store consumption strategies.

## Component Architecture

Components are organized within each module's `infrastructure/ui/` directory. The architecture follows a clear hierarchy:

```
Pages (App Router) -> Screens -> Components/Hooks
```

- **Pages** (`src/app/[locale]/{feature}/page.tsx`): Minimal wrappers that import Screen components. No business logic.
- **Screens** (`infrastructure/ui/screens/`): Orchestrate initial data load and compose stores, hooks, and module components.
- **Components** (`infrastructure/ui/components/`): Reusable module-specific components.
- **Hooks** (`infrastructure/ui/hooks/`): Custom hooks encapsulating UI logic.
- **Feature Tables** (`infrastructure/ui/{feature}-table/`): Data table implementations with columns, toolbar, and pagination.

Shared UI primitives (shadcn/ui) live in `src/components/ui/`.

## Component Categories

### Page Components

Pages are minimal wrappers in the App Router that delegate entirely to Screen components.

```tsx
// src/app/[locale]/drivers/page.tsx
import DriversScreen from '@core/drivers/infrastructure/ui/screens/DriversScreen'

export default function DriversPage() {
  return <DriversScreen />
}
```

```tsx
// src/app/[locale]/drivers/[id]/page.tsx
import DriverDetailScreen from '@core/drivers/infrastructure/ui/screens/DriverDetailScreen'

export default function DriverDetailPage() {
  return <DriverDetailScreen />
}
```

Pages contain no business logic, no store access, and no data fetching.

### Screen Components

Screens orchestrate the initial data load and compose stores, hooks, and module components. They use `useRef` as an initialization guard to prevent double calls in React StrictMode.

```tsx
'use client'

import { useEffect, useRef } from 'react'
import { useTranslations } from 'next-intl'
import { useDriversListStore } from '@core/drivers/infrastructure/store/DriversListStore'
import { DriversTable } from '../drivers-table/DriversTable'

export default function DriversScreen() {
  const t = useTranslations('drivers')
  const { loadItems, isLoadingList } = useDriversListStore((s) => ({
    loadItems: s.loadItems,
    isLoadingList: s.isLoadingList,
  }))

  const initialized = useRef(false)

  useEffect(() => {
    if (!initialized.current) {
      initialized.current = true
      loadItems()
    }
  }, [])

  return (
    <div className="flex flex-col gap-6 p-6">
      <h1 className="text-2xl font-bold">{t('title')}</h1>
      <DriversTable isLoading={isLoadingList} />
    </div>
  )
}
```

### Feature Components

Reusable components within a module. They receive data via props and consume store state through specific selectors.

```tsx
'use client'

import { useTranslations } from 'next-intl'
import { useDriversListStore } from '@core/drivers/infrastructure/store/DriversListStore'
import {
  LOADED_KIND,
  ERROR_KIND,
} from '@core/drivers/domain/states/DriversState'

interface DriverCardProps {
  id: string
  onAction: (data: Driver) => void
}

export default function DriverCard({ id, onAction }: DriverCardProps) {
  const t = useTranslations('drivers')
  const { dataState } = useDriversListStore((s) => ({
    dataState: s.dataState,
  }))

  if (dataState.kind === ERROR_KIND) {
    return <ErrorHandler errorState={dataState.serviceError} />
  }

  const data = dataState.kind === LOADED_KIND ? dataState.data : []

  return (
    <div className="flex flex-col gap-4">
      <h1>{t('title')}</h1>
      {/* UI content */}
    </div>
  )
}
```

### Custom Hooks

Custom hooks live in `infrastructure/ui/hooks/` and follow a strict 6-section internal structure.

```typescript
'use client'

import { useState, useEffect, useMemo, useCallback } from 'react'
import { useDriversListStore } from '@core/drivers/infrastructure/store/DriversListStore'

export const useDriversPreview = (params: PreviewParams) => {
  // 1. Local state
  const [searchValue, setSearchValue] = useState('')

  // 2. Store integration
  const { data, fetchData } = useDriversListStore((s) => ({
    data: s.items,
    fetchData: s.loadItems,
  }))

  // 3. Computed values (memoized)
  const filteredData = useMemo(
    () => data.filter((item) => item.name.includes(searchValue)),
    [data, searchValue]
  )

  // 4. Side effects
  useEffect(() => {
    fetchData(params)
  }, [params])

  // 5. Handlers
  const handleSearch = useCallback((value: string) => {
    setSearchValue(value)
  }, [])

  // 6. Return object (not array)
  return {
    filteredData,
    searchValue,
    handleSearch,
  }
}
```

The 6 sections in order:

1. **Local state** (`useState`)
2. **Store integration** (`useStore` with selectors)
3. **Computed values** (`useMemo` for expensive derivations)
4. **Side effects** (`useEffect`)
5. **Handlers** (`useCallback` for handlers passed as props)
6. **Return object** (not array, for better readability)

## Component Resolution Flow

When building a new feature, components are resolved in this order:

1. **Check shadcn/ui** for base primitives (Button, Input, Dialog, etc.) at `src/components/ui/`.
2. **Check `@core/common`** for shared components used across modules.
3. **Check the module's `infrastructure/ui/components/`** for existing module-specific components.
4. **Create a new component** in the module's `infrastructure/ui/components/` if none exists.

For data tables, the dedicated `{feature}-table/` directory is used within the module's UI folder.

## Component Templates

### shadcn/ui Base Components

shadcn/ui provides the base component library. Custom basic components (buttons, inputs, dialogs) are not created.

**Location**: `src/components/ui/`

```typescript
import { Button } from '@components/ui/button'
import { Dialog, DialogContent, DialogHeader } from '@components/ui/dialog'
import { Input } from '@components/ui/input'
```

**Available components**: Accordion, Button, Checkbox, Dialog, DropdownMenu, Input, Label, NavigationMenu, Popover, Progress, RadioGroup, Select, Separator, Switch, Tabs, Table, Toast, Tooltip.

### Tailwind CSS with `cn()`

Conditional classes use the `cn()` utility. Template literals are not used for conditional classes.

```tsx
import { cn } from '@/lib/utils'

<div
  className={cn(
    'flex items-center gap-2',
    isActive && 'bg-primary text-white',
    isDisabled && 'opacity-50 cursor-not-allowed'
  )}
>
```

Style guidelines:
- `cn()` is used for conditional classes
- Tailwind classes are preferred over custom CSS
- Dark mode uses the `dark:` prefix
- Responsive design uses breakpoints: `sm:`, `md:`, `lg:`, `xl:`

### Data Tables (TanStack React Table)

Data tables follow a standardized file structure within each module.

**Location**: `src/core/{module}/infrastructure/ui/{feature}-table/`

```
{feature}-table/
├── DataTable.tsx           # Generic table component
├── DataTableColumns.tsx    # Column definitions (ColumnDef[])
├── DataTableToolBar.tsx    # Filters, search, actions
└── TablePagination         # Server-side pagination
```

Key characteristics:
- Columns are defined with `ColumnDef<Entity>` from TanStack React Table.
- Server-side pagination is used (not client-side for large datasets).
- The toolbar contains filters that update query params in the store.

### Forms (React Hook Form + Zod)

Forms use React Hook Form for state management and Zod for schema validation, integrated via `zodResolver`.

```tsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const formSchema = z.object({
  name: z.string().min(1, 'Required'),
  email: z.string().email('Invalid email'),
})

type FormValues = z.infer<typeof formSchema>

export function DriverForm() {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(formSchema),
  })

  const onSubmit = async (data: FormValues) => {
    // Call store action
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <Input {...register('name')} />
      {errors.name && <span>{errors.name.message}</span>}
    </form>
  )
}
```

Form guidelines:
- Zod schema is always used for validation.
- `zodResolver` integrates Zod with React Hook Form.
- Types are inferred from the schema: `z.infer<typeof schema>`.
- i18n error messages are used when possible.

### Dynamic Imports for Heavy Components

Heavy components (maps, charts) use `dynamic()` import for code splitting.

```typescript
import dynamic from 'next/dynamic'

const MapView = dynamic(
  () => import('@core/locations/infrastructure/ui/components/MapView'),
  { ssr: false, loading: () => <MapSkeleton /> }
)
```

## Rules and Constraints

### Component Directives

- `'use client'` is required only when the component uses hooks, events, or state.
- Props are defined with `interface` (not type alias).
- Visible text always uses `useTranslations()` from next-intl (never hardcoded strings).
- Pages export as `default`. Reusable components use named exports.

### Store Consumption

Store state is accessed through specific selectors. Full store destructuring is not used.

```typescript
// Correct: specific selector
const { dataState } = useModuleStore((s) => ({
  dataState: s.dataState,
}))

// Incorrect: destructuring everything
const { everything } = useModuleStore()
```

### Type Narrowing with Discriminated Unions

Before accessing data from a discriminated union state, the `kind` field is checked:

```typescript
if (dataState.kind === ERROR_KIND) {
  return <ErrorHandler errorState={dataState.serviceError} />
}

const data = dataState.kind === LOADED_KIND ? dataState.data : []
```

### Custom Hook Rules

- The `use` prefix is mandatory.
- Hooks are placed in `infrastructure/ui/hooks/`.
- `useMemo` is used for expensive computed derivations.
- `useCallback` is used for handlers passed as props to memoized components.
- `useRef` is used for initialization flags (to avoid double calls in StrictMode).
- Hooks return an **object** (not an array).

### Screen Initialization Pattern

Screens use `useRef` to guard against double initialization in React StrictMode:

```typescript
const initialized = useRef(false)

useEffect(() => {
  if (!initialized.current) {
    initialized.current = true
    loadItems()
  }
}, [])
```

### Internationalization in Components

All visible text uses `useTranslations()` with a feature namespace:

```tsx
const t = useTranslations('drivers')
<h1>{t('title')}</h1>
<span>{t('table.name')}</span>
```

Translation keys are organized as `{feature}.{section}.{key}` in `src/messages/es.json` and `src/messages/en.json`.

### Memoization Guidelines

- `useMemo`: Only for expensive computations (filter/sort of large arrays).
- `useCallback`: Only when passing a handler as prop to a memoized component.
- `React.memo`: Only for components that re-render frequently without changes.
- Memoization is not applied by default. Performance is measured before optimizing.
