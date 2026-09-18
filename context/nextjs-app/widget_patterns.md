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

### How a component is declared

A component is declared as a function, `export default function` for the one a file is named
after and `export function` for a secondary one in the same file. Props are destructured in the
signature and typed with an `interface`.

`React.FC` is not used. It adds nothing that the annotated props do not already give, it makes
generic components awkward to type, and it drags in an implicit `children` that most components
do not accept. It is spelled out here because it keeps coming back: the six components that still
carry it were not written at the same time, and two of them are recent.

```tsx
// GOOD
export default function DriverCard({ id, onAction }: DriverCardProps) {

// BAD
export const DriverCard: React.FC<DriverCardProps> = ({ id, onAction }) => {
```

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
- Colors come from the semantic tokens described below, never from a palette class
- Responsive design uses breakpoints: `sm:`, `md:`, `lg:`, `xl:`

### Theming (semantic tokens)

Colors live as semantic tokens in `src/app/globals.css` (`:root` and `.dark`) and are mapped in
`tailwind.config.ts`. A screen picks the meaning, never the color.

| Use | Class |
|---|---|
| Page background | `bg-background` |
| Card over the page | `bg-surface-1` (same value as `bg-card`) |
| Card inside a card | `bg-surface-2` |
| Table head, highlighted row | `bg-surface-3` |
| Menus, dialogs, popovers | `bg-popover` |
| Primary text | `text-foreground` |
| Descriptions, units, secondary cells | `text-muted-foreground` |
| Borders and table rules | `border-border` |
| Meaning carried by text or an icon | `text-success`, `text-warning`, `text-danger`, `text-info` |
| Status pill | `<Badge variant="success">` and its four siblings |
| Which one it is, not how it is going | `text-category-1` to `text-category-5`, `bg-category-N-soft` |
| Figure that summarises a block | `text-figure` |
| Text or icon over a fixed brand fill | `text-on-brand` |
| Scrim and whatever is drawn on it | `bg-overlay`, `text-overlay-foreground` |

Inside a dialog or a popover the scale is measured from the surface you are already on, not from
the page: the panel is `bg-popover` and counts as level one, a nested block takes `bg-surface-2`
and a quote inside it `bg-surface-3`.

Never write `bg-white`, `bg-black`, `bg-gray-*`, `text-neutral-*`, `text-green-*`, `border-gray-*`,
a hex literal, or a hand written `dark:` variant. Each token already carries both palettes, so a
`dark:` compensation is the defect this standard removes.

**Hover and selected states use the tint utilities**, never another surface token:
`hover:tint-hover` for a row or a card, `tint-selected` for selected, open, active or dragged over,
and `hover:tint-on-brand` over a fixed brand fill. A state is measured against the surface it sits
on, and a flat token cannot know which one that is: `hover:bg-muted` darkens over a card and
lightens over a table head. The utilities paint through `background-image`, so an element that
carries its own fill keeps it and stays opaque. The tint switches instead of fading, on purpose.

**A meaning color is a text color.** It works as a solid fill only for a small mark with no text,
such as a status dot or the indicator of a progress bar. Anything large or carrying text uses
border plus soft fill plus text, the way `<Button variant="approve">` does with
`border border-success bg-success-soft text-success`. Only `destructive` is calibrated as a solid
fill in both palettes.

If a tone is missing, declare a token in `globals.css` and map it in `tailwind.config.ts`; never
write the color in the component. If a screen looks wrong once the standard is applied, the
standard is wrong: report it instead of adding a local exception.

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
