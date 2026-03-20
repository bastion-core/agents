# Convenciones Frontend Next.js

Resumen de convenciones arquitectonicas para generacion de especificaciones tecnicas de proyectos Next.js.

## Stack Tecnologico

- **Framework**: Next.js 13+ (App Router obligatorio)
- **Lenguaje**: TypeScript (strict mode obligatorio)
- **Runtime**: React 18+
- **State Management**: Zustand
- **Estilos**: Tailwind CSS v4
- **Formularios**: React Hook Form + Zod
- **HTTP Client**: Axios
- **Testing**: Vitest + @testing-library/react (jsdom)
- **UI Library**: shadcn/ui (Radix UI primitives)
- **i18n**: next-intl
- **Tablas**: TanStack React Table
- **Iconos**: lucide-react

## Arquitectura: Two-layer (2 Capas)

El proyecto sigue una arquitectura estricta de **2 capas** (Domain + Infrastructure), enforced por `eslint-plugin-hexagonal-architecture`. NO hay capa de aplicacion, NO hay UseCase, NO hay Interactors, NO hay Ploc.

```
Flujo de datos: Component -> Store -> DataAccess -> API
```

### Capa 1: Domain
- **Path**: `src/core/{module}/domain/`
- **Contenido**: entities/ (tipos puros), dtos/, enums/, states/ (discriminated unions), consts/
- **Responsabilidad**: Reglas de negocio puras. Sin dependencias externas.
- **Imports permitidos**: Solo dominio del mismo modulo y `@core/common/domain`
- **Imports prohibidos**: infrastructure/*, React, Next.js, Zustand, Axios

### Capa 2: Infrastructure
- **Path**: `src/core/{module}/infrastructure/`
- **Contenido**: data-access/, services/, helpers/, store/, ui/ (screens, components, hooks)
- **Responsabilidad**: Capa tecnica con data access (HTTP), stores, servicios, helpers y componentes UI
- **Imports permitidos**: domain/ del mismo modulo, @core/common, librerias externas
- **Imports prohibidos**: infrastructure/ de OTROS modulos

### Direccion de dependencias
```
infrastructure -> domain   (SIEMPRE)
domain -> infrastructure   (NUNCA)
```

## DataAccess Pattern (NO es un Port)

DataAccess es una **clase concreta** (sin interfaz en dominio). Maneja toda la comunicacion HTTP con Axios.

- Usa `handleRequest<T>()` para envolver TODAS las llamadas HTTP
- Retorna `Either<ServiceError, ServiceSuccess<T>>`
- `baseApiUrl` inyectado via constructor
- Usa `apiAuth` (Axios con interceptor Bearer token)
- Trailing slash OBLIGATORIO en todas las URLs
- Metodo `originalMethod()` identifica el origen en logs de error
- Se instancia a NIVEL DE MODULO (fuera del store)

## Either Pattern (Manejo Funcional de Errores)

- `Either<L, R>` — valor que es Left (error) o Right (exito)
- `ServiceError` — error con code, message, description
- `ServiceSuccess<T>` — wrapper de exito con data: T
- `fold(onLeft, onRight)` — manejar ambos caminos
- DataAccess NUNCA lanza excepciones, siempre retorna Either
- NUNCA usar try/catch en DataAccess para errores de API

## Discriminated Union States

Estados para UI modelados con discriminated unions y campo `kind` como discriminador:

- SIEMPRE usar `kind` como campo discriminador
- SIEMPRE definir constantes para valores de kind (evitar magic strings)
- Narrowing con `state.kind === LOADED_KIND` (NUNCA instanceof)
- Cada estado tiene SOLO los campos relevantes a ese estado
- States viven en `domain/states/`

## Zustand Store Pattern

- **Multiples stores por modulo**, divididos por concern (list, detail, form)
- **DataAccess instanciado FUERA del store**, a nivel de modulo
- **State y Actions** en interfaces SEPARADAS (en domain/states/)
- **Stores llaman DataAccess directamente** — NO Ploc, NO UseCase, NO Interactor
- **`response.fold()` DIRECTAMENTE en acciones del store**
- **Boolean loading flags**: isLoadingList, isLoadingDetail, etc.
- **Tamano ideal**: ~60-100 lineas por store. Si crece, dividir por concern
- Reset pattern: `reset: () => set({ items: [], isLoadingList: false })`

## Estructura de Carpetas

```
src/core/{module-name}/
  domain/
    entities/          # Tipos puros TypeScript
    dtos/              # Data Transfer Objects
    enums/             # Enumeraciones string
    states/            # Interfaces de estado (discriminated unions)
    consts/            # Constantes de dominio
  infrastructure/
    data-access/       # Llamadas HTTP (clase concreta)
    services/          # Solo si hay logica real (ej. DraftsService)
    helpers/           # Funciones utilitarias (patron repetido 3+ veces)
    store/             # Stores pequenos por concern (~60-100 lineas)
    ui/
      screens/         # Componentes de pantalla
      components/      # Componentes reutilizables del modulo
      {feature}-table/ # Table + columns + toolbar
      hooks/           # Custom hooks
```

### Rutas (App Router)
```
src/app/[locale]/{feature}/
  page.tsx             # Pagina principal (server component wrapper)
  [id]/page.tsx        # Pagina de detalle
```

## Naming Conventions

| Tipo | Convencion | Ejemplo |
|------|-----------|---------|
| Componentes | PascalCase.tsx | `DriverCard.tsx` |
| Hooks | camelCase.ts con prefijo `use` | `useDriversPreview.ts` |
| DataAccess | PascalCase.ts | `DriversDataAccess.ts` |
| Stores | PascalCase.ts con prefijo `use` | `useDriversStore` |
| Tests | PascalCase.test.ts(x) | `DriversStore.test.ts` |
| Constantes | UPPER_SNAKE_CASE | `LOADED_KIND` |

## Formularios

- Zod schema SIEMPRE para validacion
- `zodResolver` para integrar Zod con React Hook Form
- Inferir tipos del schema: `z.infer<typeof schema>`
- Mensajes de error con i18n cuando sea posible

## i18n

- Libreria: next-intl
- Locales: ["es", "en"], default "es"
- Archivos: `src/messages/es.json`, `src/messages/en.json`
- Keys organizadas por feature: `{feature}.{section}.{key}`
- NUNCA texto hardcodeado en componentes
- Uso: `const t = useTranslations('{feature}')`

## Testing

| Capa | Cobertura objetivo | Foco |
|------|-------------------|------|
| Domain | 90%+ | Logica pura, sin mocks |
| Stores | 70%+ | Acciones con DataAccess mockeado |
| Infrastructure Services | 60%+ | Mock HTTP |
| UI Components | 50%+ | Solo componentes criticos |

- Framework: Vitest + @testing-library/react
- Tests colocados junto al archivo fuente
- Mock DataAccess con `vi.mock()`
- Testear comportamiento visible, no detalles de implementacion

## Anti-Patterns (PROHIBIDOS)

| Anti-Pattern | Alternativa Correcta |
|-------------|---------------------|
| Capa de aplicacion (UseCase, Ploc, Interactor) | Stores llaman DataAccess directamente |
| Clases base abstractas (sin 3+ extensiones) | Composicion sobre herencia |
| Generic CRUD (BaseCrudService) | Cada DataAccess con metodos especificos |
| Fat Stores (500+ lineas) | Dividir por concern: list, detail, form |
| DI Frameworks (InversifyJS, tsyringe) | DataAccess instanciado a nivel de modulo |
| `any` en TypeScript | `unknown` con type guards |
| Texto hardcodeado en UI | `useTranslations()` |
| API calls directas en componentes | Flujo store -> DataAccess |
| React.memo/useMemo/useCallback sin medir | Optimizar solo con evidencia |
| Importar infrastructure de otro modulo | Usar tipos de domain |
