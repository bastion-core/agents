# State Management

This document describes the state management architecture for the Next.js application, covering Zustand stores, the Either pattern for error handling, discriminated union states, the DataAccess pattern, and testing strategies.

## State Pattern

### Zustand Stores

Zustand stores are the core of the infrastructure layer. They orchestrate the flow from DataAccess to state. Stores are small, focused, and divided by concern (~60-100 lines each).

**Location**: `src/core/{module}/infrastructure/store/`

#### Store Template

```typescript
// DriversListStore.ts
import { create } from 'zustand'
import { baseApiUrl } from '@core/common/infrastructure/services/apiEndpoints'
import type {
  DriversListStoreState,
  DriversListStoreActions,
} from '../../domain/states/DriversListStoreState'
import { DriversDataAccess } from '../data-access'

// DataAccess instantiated at MODULE level (outside the store)
const driversDataAccess = new DriversDataAccess(baseApiUrl)

export const useDriversListStore = create<
  DriversListStoreState & DriversListStoreActions
>((set, get) => ({
  // Initial state
  items: [],
  isLoadingList: false,
  pagination: null,

  // Actions -- call DataAccess directly, fold response in place
  loadItems: async () => {
    set({ isLoadingList: true })
    const response = await driversDataAccess.getAll(get().queryParams)
    response.fold(
      (error) => set({ isLoadingList: false, items: [] }),
      (success) => {
        const data = Array.isArray(success.data)
          ? success.data[0]
          : success.data
        set({
          isLoadingList: false,
          items: data.list || [],
          pagination: { totalRows: data.totalRows },
        })
      }
    )
  },

  reset: () =>
    set({ items: [], isLoadingList: false, pagination: null }),
}))
```

#### Store State and Actions Interfaces

State and Actions are defined in **separate interfaces** in the domain layer at `domain/states/`:

```typescript
// DriversListStoreState.ts (domain/states/)
import type { Driver } from '../entities/Driver'
import type { GetDriversDto } from '../dtos/GetDriversDto'

export interface DriversListStoreState {
  items: Driver[]
  isLoadingList: boolean
  pagination: { totalRows: number } | null
  queryParams?: GetDriversDto
}

export interface DriversListStoreActions {
  loadItems: () => Promise<void>
  reset: () => void
}
```

#### Store Rules

- **Multiple stores per module**, divided by concern (list, detail, form).
- **DataAccess is instantiated outside the store**, at module level.
- **State and Actions** are in separate interfaces (in `domain/states/`).
- **Stores call DataAccess directly** -- no Ploc, no UseCase, no Interactor.
- **`response.fold()` is called directly in store actions** -- no intermediate layer.
- **Boolean loading flags** are used: `isLoadingList`, `isLoadingDetail`, etc.
- **UI orchestrates initial load** via `useEffect` in screens.
- **Cross-store communication** uses `useOtherStore.getState().action()`.
- **`set()` is used for state updates** (immutable).
- **Stores are consumed with selectors**: `useStore((s) => ({ field: s.field }))`.
- **Ideal size**: ~60-100 lines per store. Stores that grow beyond this are split by concern.

#### Reset Pattern

Every store implements a `reset()` method to restore initial state:

```typescript
reset: () => set({ items: [], isLoadingList: false, pagination: null })
```

#### Cross-Store Communication

From inside one store, another store's action is called via `getState()`:

```typescript
useOtherStore.getState().someAction()
```

### When to Use Each State Type

#### Zustand Store

- Data shared between multiple components
- Data that persists between navigations
- State of domain entities (drivers, vehicles, etc.)
- State of async operations (loading, error, success)
- Server-side paginated or filtered data

#### Local State (`useState`)

- Temporary UI state (modal open/closed, active tab)
- Form state (React Hook Form handles it)
- Local search/filter within a component
- Toggle, hover, focus states
- Derived values with `useMemo`

#### URL State (`searchParams`)

- Filters that should be shareable via URL
- Pagination (page, perPage)
- Route parameters ([id], [locale])

## Data Flow

The data flow follows a unidirectional pattern:

```
Component -> Store -> DataAccess -> API
```

1. **Component** calls a store action (e.g., `loadItems()`).
2. **Store** sets loading state, calls DataAccess, and processes the response with `fold()`.
3. **DataAccess** makes the HTTP call via `apiAuth` and wraps it with `handleRequest<T>()`.
4. **API** returns the response, which `handleRequest` converts to `Either<ServiceError, ServiceSuccess<T>>`.

### Discriminated Union States

States for the UI are modeled using discriminated unions with a `kind` field. This enables safe type narrowing in components.

**Location**: `src/core/{module}/domain/states/`

```typescript
// DriversState.ts
import type { ServiceError } from '@core/common/domain'
import type { Driver } from '../entities/Driver'

export interface LoadingDriversState {
  kind: 'LoadingDriversState'
}

export interface LoadedDriversState {
  kind: 'LoadedDriversState'
  data: Driver[]
  totalRows?: number
}

export interface ErrorDriversState {
  kind: 'ErrorDriversState'
  serviceError: ServiceError
}

export type DriversState =
  | LoadingDriversState
  | LoadedDriversState
  | ErrorDriversState

// Constants to avoid magic strings:
export const LOADING_KIND = 'LoadingDriversState'
export const LOADED_KIND = 'LoadedDriversState'
export const ERROR_KIND = 'ErrorDriversState'
```

#### Discriminated Union Rules

- `kind` is always the discriminator field.
- Constants are always defined for kind values (no magic strings).
- Narrowing uses `state.kind === LOADED_KIND` (not `instanceof`).
- Each state interface contains only the fields relevant to that state.
- State interfaces live in `domain/states/`.

#### Type Narrowing in Components

```typescript
if (dataState.kind === ERROR_KIND) {
  return <ErrorHandler errorState={dataState.serviceError} />
}

const data = dataState.kind === LOADED_KIND ? dataState.data : []
```

## Error Handling

### Either Pattern (Functional Error Handling)

The Either monad is the foundation of error handling across the entire frontend. DataAccess methods never throw exceptions. They return `Either<ServiceError, ServiceSuccess<T>>`.

**Location**: `@core/common/domain/Either.ts`

#### Core Types

- `Either<L, R>` -- A value that is either Left (error) or Right (success).
- `ServiceError` -- Error with `code`, `message`, `description`.
- `ServiceSuccess<T>` -- Success wrapper with `data: T`.

#### Key Methods

- `fold(onLeft, onRight)` -- Handle both paths.
- `mapRight(fn)` -- Transform the right (success) value.
- `isLeft()` / `isRight()` -- Type guards.

#### Usage in DataAccess

```typescript
async getAll(params: QueryParamsDto): Promise<Either<ServiceError, ServiceSuccess<Driver[]>>> {
  return handleRequest<Driver[]>(
    apiAuth.get(this.paths.getAll(params)),
    'DriversDataAccess.getAll'
  )
}
```

#### Usage in Stores

```typescript
getAll: async (params) => {
  set({ isLoadingList: true })
  const response = await driversDataAccess.getAll(params)
  response.fold(
    (error) => set({ isLoadingList: false, drivers: [] }),
    (success) => set({ isLoadingList: false, drivers: success.data })
  )
}
```

#### Error Handling Flow

1. DataAccess calls `handleRequest(apiAuth.get(url), 'origin')`.
2. `handleRequest` captures Axios errors.
3. Returns `Either.left(ServiceError)` on error.
4. Returns `Either.right(ServiceSuccess<T>)` on success.

#### Either Rules

- `try/catch` is not used in DataAccess for API errors.
- `handleRequest<T>` wraps all HTTP calls.
- `fold()` handles both error and success paths.
- `ServiceError` includes: `code`, `message`, `description`.

## Dependency Injection

### DataAccess Pattern

DataAccess is a **concrete class** (no interface in domain -- it is not a port) that handles all HTTP communication using Axios with an authentication interceptor.

**Location**: `src/core/{module}/infrastructure/data-access/`

#### DataAccess Template

```typescript
// DriversDataAccess.ts
import { apiAuth, handleRequest } from '~/core/common/infrastructure'
import type { Either, ServiceError, ServiceSuccess } from '@core/common/domain'
import type { Driver, DriverList } from '@core/drivers/domain'
import type { CreateDriverDto, GetDriversDto } from '@core/drivers/domain'

export class DriversDataAccess {
  private readonly apiUrl: string

  constructor(baseApiUrl: string) {
    this.apiUrl = `${baseApiUrl}drivers/`
  }

  private originalMethod(methodName: string) {
    return `DriversDataAccess.${methodName}`
  }

  async getAll(
    params?: GetDriversDto
  ): Promise<Either<ServiceError, ServiceSuccess<DriverList[]>>> {
    return handleRequest<DriverList[]>(
      apiAuth.get(this.apiUrl, { params }),
      this.originalMethod('getAll')
    )
  }

  async getById(
    id: string
  ): Promise<Either<ServiceError, ServiceSuccess<Driver[]>>> {
    return handleRequest<Driver[]>(
      apiAuth.get(`${this.apiUrl}${id}/`),
      this.originalMethod('getById')
    )
  }

  async create(
    dto: CreateDriverDto
  ): Promise<Either<ServiceError, ServiceSuccess<Driver[]>>> {
    return handleRequest<Driver[]>(
      apiAuth.post(this.apiUrl, dto),
      this.originalMethod('create')
    )
  }

  async update(
    id: string,
    dto: Partial<CreateDriverDto>
  ): Promise<Either<ServiceError, ServiceSuccess<Driver[]>>> {
    return handleRequest<Driver[]>(
      apiAuth.patch(`${this.apiUrl}${id}/`, dto),
      this.originalMethod('update')
    )
  }

  async delete(
    id: string
  ): Promise<Either<ServiceError, ServiceSuccess<void>>> {
    return handleRequest<void>(
      apiAuth.delete(`${this.apiUrl}${id}/`),
      this.originalMethod('delete')
    )
  }
}
```

#### Shared Dependencies

- **apiAuth**: Axios instance with Bearer token interceptor at `@core/common/infrastructure/connections/ApiConnection.ts`.
- **handleRequest**: Wraps HTTP calls and returns Either at `@core/common/infrastructure/services/RequestHelper.ts`.
- **QueryParamsFormatterHelper**: Formats filters and pagination (page, perPage, sort, order, search, searchType, dateRange, filters) at `@core/common/infrastructure/services/`.

#### DataAccess Rules

- DataAccess is a concrete class with no interface in domain (it is not a port).
- `handleRequest<T>()` wraps all HTTP calls.
- `baseApiUrl` is injected via constructor.
- `apiAuth` (Axios with Bearer token interceptor) is used for authenticated requests.
- For multipart uploads, `FormData` is used.
- `originalMethod()` identifies the origin in error logs.
- A trailing slash is mandatory on all URLs.

#### Instantiation

DataAccess is instantiated at module level, outside the store:

```typescript
const driversDataAccess = new DriversDataAccess(baseApiUrl)
```

No DI framework (InversifyJS, tsyringe, etc.) is used. Simple module-level instantiation.

#### URL Patterns

| Method | Pattern | Purpose |
|--------|---------|---------|
| GET | `/{resource}/?params` | List with filters |
| GET | `/{resource}/{id}/` | Get by ID |
| POST | `/{resource}/` | Create |
| PATCH | `/{resource}/{id}/` | Partial update |
| DELETE | `/{resource}/{id}/` | Delete |

### Service Pattern

Services contain real business logic -- not HTTP call wrappers. If only fetch/post is needed, DataAccess is used instead.

```typescript
// DraftsService.ts
export class DraftsService {
  constructor(private readonly storage: StorageService) {}

  saveDraft(name: string, data: DraftData): string {
    const draftId = this.generateId()
    this.storage.save(this.getKey(draftId), { ...data, id: draftId })
    return draftId
  }

  getAllDrafts(): Draft[] {
    const keys = this.storage.getAllKeys()
    return keys
      .filter((k) => k.startsWith('draft_'))
      .map((k) => this.storage.get(k))
      .sort((a, b) => b.updatedAt - a.updatedAt)
  }

  private generateId(): string {
    return `draft_${Date.now()}`
  }

  private getKey(id: string): string {
    return `drafts_${id}`
  }
}
```

### Helpers Pattern

Pure functions for patterns that repeat 3+ times within a module:

```typescript
// normalizeResponse.ts
export function normalizeResponse<T>(successData: T | T[]): T {
  return Array.isArray(successData) ? successData[0] : successData
}

// Usage in store:
response.fold(
  (error) => set({ isLoading: false }),
  (success) => {
    const data = normalizeResponse(success.data)
    set({ isLoading: false, items: data.list })
  }
)
```

## Testing Strategy

### Framework and Location

- **Framework**: Vitest + @testing-library/react (jsdom environment)
- **Location**: Tests are colocated next to source files (`{File}.test.ts(x)`)
- **Commands**:
  - Run all: `npx vitest run`
  - Watch mode: `npx vitest`
  - Coverage: `npx vitest run --coverage`

### Coverage Targets

| Layer | Target | Rationale |
|-------|--------|-----------|
| Domain | 90%+ | Pure logic, easy to test |
| Stores | 70%+ | Actions with mocked DataAccess |
| Infrastructure Services | 60%+ | Mock HTTP or skip |
| UI Components | 50%+ | Critical components only |

Priority is domain and stores first. 100% UI coverage is not a goal -- critical behavior is tested.

### Domain Tests (90%+ coverage)

Pure tests with no dependencies and no mocks:

```typescript
import { describe, it, expect } from 'vitest'
import { transformDriverData } from './driverTransforms'

describe('Driver domain', () => {
  it('should transform data correctly', () => {
    const input = { first_name: 'John', last_name: 'Doe' }
    const result = transformDriverData(input)
    expect(result).toEqual({ firstName: 'John', lastName: 'Doe' })
  })

  it('should handle empty arrays', () => {
    const result = transformDriverData([])
    expect(result).toEqual([])
  })

  it('should validate required fields', () => {
    const invalid = { name: '' }
    const result = validate(invalid)
    expect(result.isLeft()).toBeTruthy()
  })

  it('should return right on valid data', () => {
    const valid = { name: 'Test', email: 'test@test.com' }
    const result = validate(valid)
    expect(result.isRight()).toBeTruthy()
  })
})
```

Domain test guidelines:
- No mocks (pure logic).
- Edge cases are covered (null, undefined, empty arrays).
- Both paths of Either are tested (left/right).

### Store Tests (70%+ coverage)

Store actions are tested with DataAccess mocked via `vi.mock()`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { act } from '@testing-library/react'
import { useDriversListStore } from './DriversListStore'

// Mock the DataAccess module
vi.mock('../data-access', () => ({
  DriversDataAccess: vi.fn().mockImplementation(() => ({
    getAll: vi.fn(),
    getById: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  })),
}))

describe('useDriversListStore', () => {
  beforeEach(() => {
    // Reset store state between tests
    act(() => {
      useDriversListStore.getState().reset()
    })
  })

  it('should load items successfully', async () => {
    const mockData = { list: [{ id: '1', name: 'Driver 1' }], totalRows: 1 }
    const mockResponse = {
      fold: (_onError: Function, onSuccess: Function) =>
        onSuccess({ data: [mockData] }),
    }

    const { DriversDataAccess } = await import('../data-access')
    const mockInstance = new DriversDataAccess('')
    ;(mockInstance.getAll as ReturnType<typeof vi.fn>).mockResolvedValue(
      mockResponse
    )

    await act(async () => {
      await useDriversListStore.getState().loadItems()
    })

    const state = useDriversListStore.getState()
    expect(state.isLoadingList).toBe(false)
    expect(state.items).toHaveLength(1)
  })

  it('should handle error response', async () => {
    const mockResponse = {
      fold: (onError: Function) =>
        onError({ code: '500', message: 'Server Error' }),
    }

    const { DriversDataAccess } = await import('../data-access')
    const mockInstance = new DriversDataAccess('')
    ;(mockInstance.getAll as ReturnType<typeof vi.fn>).mockResolvedValue(
      mockResponse
    )

    await act(async () => {
      await useDriversListStore.getState().loadItems()
    })

    const state = useDriversListStore.getState()
    expect(state.isLoadingList).toBe(false)
    expect(state.items).toEqual([])
  })

  it('should reset state', () => {
    act(() => {
      useDriversListStore.setState({ items: [{ id: '1' }], isLoadingList: true })
    })

    act(() => {
      useDriversListStore.getState().reset()
    })

    const state = useDriversListStore.getState()
    expect(state.items).toEqual([])
    expect(state.isLoadingList).toBe(false)
  })
})
```

Store test guidelines:
- DataAccess is mocked with `vi.mock()`.
- Both success and error cases are tested.
- Loading state transitions are verified.
- `beforeEach` resets store state.
- `act()` wraps state updates.

### UI Tests (50%+ for critical components)

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '~/test-utils/test-utils'
import userEvent from '@testing-library/user-event'
import { DriverCard } from './DriverCard'

// Mock Next.js navigation
vi.mock('next/navigation', async () => ({
  ...(await vi.importActual('next/navigation')),
  useParams: () => ({ locale: 'es' }),
}))

describe('DriverCard', () => {
  it('should render with correct data', () => {
    render(<DriverCard data={mockDriver} />)
    expect(screen.getByText('John Doe')).toBeInTheDocument()
  })

  it('should handle empty state', () => {
    render(<DriverCard data={null} />)
    expect(screen.getByText(/no data/i)).toBeInTheDocument()
  })

  it('should call handler on button click', async () => {
    const onAction = vi.fn()
    render(<DriverCard data={mockDriver} onAction={onAction} />)
    await userEvent.click(screen.getByRole('button', { name: /edit/i }))
    expect(onAction).toHaveBeenCalledTimes(1)
  })
})
```

UI test guidelines:
- Custom render from `test-utils` is used (includes NextIntlProvider).
- `next/navigation` is mocked when using router hooks.
- Elements are queried by role, text, or test-id (not by CSS class).
- Visible behavior is tested, not implementation details.
- `screen.getByText` and `screen.getByRole` are used for queries.

### Mock Patterns

#### Factory Pattern (Test Data)

```typescript
// driverFactory.ts
import { Factory } from 'fishery'
import type { Driver } from '../../domain/entities/Driver'

export const driverFactory = Factory.Sync.makeFactory<Driver>({
  id: Factory.each((i) => `id-${i}`),
  firstName: 'Test',
  lastName: 'Driver',
  email: 'test@example.com',
  status: 'ACTIVE',
  createdAt: '2024-01-01',
})

// Usage:
const single = driverFactory.build({ firstName: 'Custom' })
const list = driverFactory.buildList(5)
```

#### Service Mock Factory

```typescript
import { mockGetServiceFactory } from '@core/common/infrastructure/test-utils'

const mockDataAccess = mockGetServiceFactory({
  response: Either.right(successResponse),
})
```

#### Custom Mocks Available

- `LocalStorageMock`: Simulates localStorage in jsdom.
- `MockStorageService`: Storage wrapper for tests.
- `MockWebSocketFactory`: Simulates WebSocket connections.
