# Architecture Overview

This document describes the architectural patterns, folder structure, naming conventions, and design decisions for Flutter mobile applications built with Clean Architecture and Feature-Based Modularization.

## Architectural Pattern

The application follows **Clean Architecture** with a **hybrid organization strategy**: feature-first at the top level, then layered within each feature. Each feature is self-contained with its own domain, application, infrastructure, and presentation layers. Cross-cutting concerns live in `common/`.

- **Architecture Style**: Modular Monolith (single Flutter app)
- **Framework**: Flutter SDK (latest stable) + Dart SDK ^3.7.2
- **Platforms**: iOS + Android (single codebase)

## Layer Structure

The architecture is organized in 4 layers, each with a specific responsibility and dependency direction.

### 1. Presentation Layer

- **Path**: `features/{feature}/presentation/`
- **Responsibility**: UI screens and widgets. Consumes BLoC states via `BlocBuilder`/`BlocConsumer`. Dispatches events to BLoCs. Contains no business logic.
- **Depends on**: Application layer (BLoC)
- **Contains**:
  - `screens/` -- Full page screens (one per route)
  - `widgets/` -- Feature-specific reusable widgets

### 2. Application Layer (BLoC)

- **Path**: `features/{feature}/application/bloc/`
- **Responsibility**: BLoC classes that orchestrate business logic. Handle events, call repositories/services, emit states. This layer replaces traditional UseCases/Interactors -- BLoCs call repositories directly.
- **Depends on**: Domain layer
- **Contains**:
  - `{feature}_bloc.dart` -- BLoC class
  - `{feature}_event.dart` -- Freezed event sealed class
  - `{feature}_state.dart` -- Freezed state sealed class
  - `helpers/` -- Helper classes for complex BLoCs (optional)

### 3. Domain Layer

- **Path**: `features/{feature}/domain/`
- **Responsibility**: Business contracts and data definitions. Contains abstract repository interfaces, abstract service interfaces, DTOs, enums, and domain models. No implementation code. No infrastructure dependencies.
- **Depends on**: Nothing (zero dependencies on other layers)
- **Contains**:
  - `repositories/` -- Abstract repository interfaces
  - `services/` -- Abstract service interfaces
  - `dtos/` -- Data Transfer Objects (Freezed classes)
  - `enums/` -- Feature-specific enums
  - `models/` -- Domain models (plain Dart classes)

### 4. Infrastructure Layer

- **Path**: `features/{feature}/infrastructure/`
- **Responsibility**: Concrete implementations of domain interfaces. API providers (Dio calls), repository implementations, service implementations, local storage services.
- **Depends on**: Domain layer
- **Contains**:
  - `{feature}_api_provider.dart` -- API calls (extends `BaseApiProvider`)
  - `{feature}_repository_impl.dart` -- Repository implementation
  - `{feature}_service_impl.dart` -- Service implementation (if applicable)
  - Storage services (SharedPreferences-based, if applicable)

## Folder Structure

### Root Layout (`lib/`)

```
lib/
├── main.dart                              # App entry point
├── common/                                # Cross-cutting concerns
│   ├── application/bloc/                  # Shared BLoCs (e.g., ConnectivityBloc)
│   ├── domain/services/                   # Shared abstract service interfaces
│   ├── infrastructure/                    # BaseApiProvider, interceptor, AppVersionService
│   │   └── networking/                    # Result<T> and RequestError sealed classes
│   ├── presentation/widgets/              # Shared widgets (ConnectivityListener, etc.)
│   └── ui/                                # Project UI abstraction layer
├── features/                              # Feature modules (self-contained)
│   └── {feature_name}/                    # One folder per feature
│       ├── application/bloc/              # BLoC + events + states + helpers
│       ├── domain/
│       │   ├── dtos/                      # Freezed DTOs with custom fromJson
│       │   ├── enums/                     # Feature-specific enums
│       │   ├── models/                    # Domain models (plain Dart classes)
│       │   ├── repositories/              # Abstract repository interfaces
│       │   └── services/                  # Abstract service interfaces
│       ├── infrastructure/                # API providers, repo impls, service impls, storage
│       └── presentation/
│           ├── screens/                   # Full page screens
│           └── widgets/                   # Feature-specific widgets
├── settings/                              # App configuration
│   ├── di.dart                            # Dependency injection setup (get_it)
│   ├── app_routes.dart                    # GoRouter configuration
│   ├── config.dart                        # App configuration (environment, feature flags)
│   ├── environment.dart                   # Environment enum (production, staging, local)
│   ├── url_paths.dart                     # Centralized API endpoint URL paths
│   ├── {project}_colors.dart              # Color constants matching design system
│   └── translations/                      # i18n translation files
└── logs/                                  # Logging and analytics services
```

### Test Layout

```
test/
├── features/
│   └── {feature}/
│       ├── application/bloc/
│       │   ├── {feature}_bloc_test.dart
│       │   ├── mocks/
│       │   │   └── {feature}_mock.dart    # @GenerateMocks file
│       │   └── helpers/
│       │       └── {helper}_test.dart
│       ├── infrastructure/
│       │   └── {repo_impl}_test.dart
│       └── domain/services/
│           └── {service}_test.dart
└── common/
    ├── application/bloc/
    │   └── {bloc}_test.dart
    └── infrastructure/
        └── {service}_test.dart
```

### New Feature Folder Template

When creating a new feature, this is the required directory structure:

```
lib/features/{feature_name}/
├── application/bloc/
├── domain/dtos/
├── domain/enums/
├── domain/repositories/
├── domain/services/
├── infrastructure/
├── presentation/screens/
└── presentation/widgets/
```

## Dependency Flow

```
Presentation -> Application (BLoC) -> Domain (Interfaces) <- Infrastructure (Implementations)
```

The domain layer has zero dependencies on other layers. Infrastructure implements domain interfaces. BLoCs depend on domain abstractions, never on infrastructure directly.

## Key Architectural Decisions

### Decision 1: No Separate Entity Layer

DTOs serve as both data carriers and domain entities. A separate Entity layer would introduce unnecessary mapping complexity without meaningful benefit at this scale. DTOs are immutable (Freezed) and contain no business logic, making them suitable as entities.

DTOs are placed in `features/{feature}/domain/dtos/`.

### Decision 2: No UseCase/Interactor Classes

BLoCs call repositories directly. UseCases would add an extra layer of indirection with minimal benefit since most operations are simple CRUD + validation flows. BLoCs already serve as the orchestration layer.

### Decision 3: No Mapper Classes

DTOs handle their own serialization via custom `fromJson` factories. No separate mapper classes are needed. The DTO IS the mapped object.

### Decision 4: DTOs Live in domain/

DTOs are used across all layers (domain contracts, infrastructure serialization, application logic). Placing them in `domain/` avoids circular dependencies and keeps them accessible to all layers.

### Decision 5: Helper Classes for Complex BLoCs

When a BLoC handles many events with complex logic, helper classes extract related event handlers into focused classes. This maintains single responsibility without introducing UseCase complexity.

Helper classes are placed in `features/{feature}/application/bloc/helpers/` when a BLoC has more than 5-6 event handlers or when event handlers exceed 50 lines of logic.

## Anti-Patterns (Forbidden)

The following patterns are explicitly forbidden in this project. They add unnecessary complexity without proportional benefit.

| # | Forbidden Pattern | Reason | Use Instead |
|---|------------------|--------|-------------|
| 1 | Separate Entity layer | DTOs are sufficient as both data carriers and domain entities | Freezed DTOs in `domain/dtos/` |
| 2 | Mapper classes | DTOs handle their own serialization via custom `fromJson` | `fromJson` logic in the DTO's factory constructor |
| 3 | UseCase/Interactor classes | BLoCs already serve as the orchestration layer | BLoCs call repositories directly; use helpers for complex BLoCs |
| 4 | `injectable` / auto DI packages | Manual get_it registration is clearer and more explicit | Manual registration in `di.dart` with feature-grouped methods |
| 5 | `auto_route` package | `go_router` is simpler and sufficient | GoRouter with declarative routes in `app_routes.dart` |
| 6 | `ScreenUtil` / responsive utility packages | Native Flutter responsive design is sufficient | `MediaQuery`, `LayoutBuilder`, `Flex` widgets |
| 7 | Separate error handler middleware | `Result<T>` + `RequestError` handle all error cases | Return `Result<T>` from all repositories, consume with `.when()` |
| 8 | Abstract base BLoC classes | Each BLoC is self-contained with its own concerns | Keep BLoCs independent; use helpers for shared logic if needed |
| 9 | Over-abstracting UI components | The project's UI abstraction with named constructors provides sufficient abstraction | `{Project}Button.primary()`, `{Project}Text.title()`, etc. |
| 10 | `data/` layer naming | The project uses `infrastructure/` consistently | Always use `infrastructure/` for the implementation layer |
| 11 | `core/` or `shared/` folders | The project uses `common/` consistently | Always use `common/` for cross-cutting concerns |
| 12 | Throwing exceptions in business logic | `Result<T>` pattern replaces exception-based error handling | Return `Result.failure(RequestError.xxx())` instead of throwing |
| 13 | Directly importing the underlying UI library in features | The project's UI abstraction is the correct import | Import the project's UI barrel file, not the library directly |
| 14 | Raw Color values in widget code | All colors are centralized in the project's colors file | `{Project}Colors.primary`, `{Project}Colors.surface`, etc. |

## Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Screen | `{screen_name}_screen.dart` | `notifications_screen.dart` |
| Widget | `{widget_name}_widget.dart` | `notification_card_widget.dart` |
| BLoC | `{feature}_bloc.dart` | `notifications_bloc.dart` |
| Event | `{feature}_event.dart` | `notifications_event.dart` |
| State | `{feature}_state.dart` | `notifications_state.dart` |
| Test | `{source_file}_test.dart` | `notifications_bloc_test.dart` |
| Request DTO | `{name}_request_dto.dart` | `mark_read_request_dto.dart` |
| Response DTO | `{name}_response_dto.dart` | `notification_response_dto.dart` |
| API Provider | `{feature}_api_provider.dart` | `notifications_api_provider.dart` |
| Repository Impl | `{feature}_repository_impl.dart` | `notifications_repository_impl.dart` |
| Service Impl | `{feature}_service_impl.dart` | `notifications_service_impl.dart` |

Additional naming rules:

- **Classes**: PascalCase (`LoginBloc`, `AuthRepository`)
- **Files**: snake_case (`login_bloc.dart`, `auth_repository.dart`)
- **Variables/methods**: camelCase (`getUserData`, `isLoading`)
- **Private members**: `_prefixed` (`_repository`, `_onLogin`)

### Folder Rules

- Each feature has all 4 layers: `application/`, `domain/`, `infrastructure/`, `presentation/`
- Shared code goes in `common/`, not in a specific feature
- No `core/` or `shared/` folder -- use `common/` instead
- No `data/` layer -- use `infrastructure/` instead
- Features are not nested inside other features

## Development Principles

The project balances architectural principles with pragmatic development:

**Implemented patterns**:
- Clean Architecture with Feature-Based Modularization as defined in the project structure
- BLoC + Freezed patterns for state management
- `Result<T>` error handling for all async operations
- Project's UI abstraction components for all UI elements
- Constructor injection for all dependencies
- Comprehensive BLoC tests with `bloc_test`

**Avoided over-engineering**:
- No abstractions for hypothetical future needs
- No design patterns that are not needed for current requirements
- No additional layers beyond the established 4-layer architecture
- No "future-proofing" that is not justified by actual requirements
- No refactoring of working code that already follows established patterns
- No complexity for the sake of "best practices" when simpler solutions work

The core principle: simple, working solutions that follow established patterns are preferred over over-engineered solutions that try to solve hypothetical future problems.
