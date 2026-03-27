# Architecture Overview

This document describes the architectural patterns, directory structure, compliance requirements, and validation checklist for Flutter applications reviewed under Clean Architecture with Feature-First organization.

## Architectural Pattern

The Flutter project implements **Clean Architecture** with **Feature-First Organization**:

- **Clean Architecture**: 3 layers (Domain, Infrastructure, Presentation) with an Application sub-layer for BLoC
- **Feature-First Organization**: Code organized by business features, not by type
- **BLoC Pattern**: State management using flutter_bloc v8.1.6
- **Repository Pattern**: Abstract interfaces with concrete implementations
- **Dependency Injection**: GetIt v7.7.0 for service location
- **Result/Either Pattern**: For error handling
- **Freezed DTOs**: Immutable data models
- **GoRouter**: For navigation

## Layer Structure

### Domain Layer

- **Path**: `features/{feature}/domain/`
- **Responsibility**: Business logic (framework-agnostic). Contains abstract interfaces and DTOs only.
- **Depends on**: Nothing -- the domain layer has no dependencies on outer layers.
- **Contains**:
  - `repositories/` -- Abstract interfaces
  - `dtos/` -- Data Transfer Objects (Freezed)

The domain layer must not import Flutter packages. It is framework-agnostic.

### Infrastructure Layer

- **Path**: `features/{feature}/infrastructure/`
- **Responsibility**: Data layer and API integration. Contains concrete repository implementations and API providers.
- **Depends on**: Domain layer (implements domain interfaces)
- **Contains**:
  - `*_api_provider.dart` -- API call implementations
  - `*_repository_impl.dart` -- Repository interface implementations

### Presentation Layer

- **Path**: `features/{feature}/presentation/`
- **Responsibility**: UI layer only. Screens and widgets.
- **Depends on**: Application layer (BLoC)
- **Contains**:
  - `screens/` -- Full page screens
  - `widgets/` -- Feature-specific reusable widgets

### Application Sub-Layer (BLoC)

- **Path**: `features/{feature}/application/bloc/`
- **Responsibility**: Use cases and state management via BLoC implementations.
- **Depends on**: Domain layer
- **Contains**:
  - `*_bloc.dart` -- BLoC class
  - `*_event.dart` -- Event definitions
  - `*_state.dart` -- State definitions

BLoCs are placed in `application/bloc/`, not in `presentation/bloc/`. BLoCs contain application logic, not presentation logic. The presentation layer only consumes BLoC states.

## Folder Structure

### Project Location

The Flutter project is located at the **repository root**, not in a nested subdirectory. The `lib/`, `test/`, and `pubspec.yaml` are at root level.

**Correct repository structure:**

```
app/                                  # Repository root
├── .claude/                          # Claude AI configuration
├── .github/                          # GitHub Actions workflows
├── lib/                              # Flutter source code (at root)
│   ├── features/
│   ├── common/
│   ├── settings/
│   └── main.dart
├── test/                             # Test files
├── pubspec.yaml                      # Dependencies
├── analysis_options.yaml             # Linter rules
├── android/                          # Android project
└── ios/                              # iOS project
```

Nesting the Flutter project in a subdirectory (e.g., `mobile_app/lib/`) is incorrect.

### Expected `lib/` Structure

```
lib/
├── features/
│   ├── [feature_name]/
│   │   ├── domain/                   # Business logic (framework-agnostic)
│   │   │   ├── repositories/         # Abstract interfaces
│   │   │   └── dtos/                 # Data Transfer Objects (Freezed)
│   │   ├── application/              # Use cases & state management
│   │   │   └── bloc/                 # BLoC implementations
│   │   ├── infrastructure/           # Data layer & API integration
│   │   │   ├── *_api_provider.dart
│   │   │   └── *_repository_impl.dart
│   │   └── presentation/            # UI layer
│   │       ├── screens/
│   │       └── widgets/
├── common/
│   ├── infrastructure/
│   │   ├── base_api_provider.dart
│   │   └── networking/
│   └── ui/
├── settings/
│   ├── di.dart                       # Dependency injection setup
│   ├── app_routes.dart               # GoRouter configuration
│   └── config.dart
└── main.dart
```

## Dependency Flow

```
Presentation -> Application (BLoC) -> Domain (Interfaces) <- Infrastructure (Implementations)
```

Dependencies flow inward. Infrastructure depends on Domain (implements interfaces). Domain has no dependencies on outer layers. There are no circular dependencies between layers.

The presentation layer does not call Infrastructure directly -- it goes through the Application/BLoC layer.

## Key Architectural Decisions

### Feature Self-Containment

Each feature is self-contained with its own layers. Code is organized by feature, not by type (no global `screens/` or `widgets/` directory). Shared code lives in `common/`, not scattered across features.

### BLoC Placement

BLoCs belong in `application/bloc/`, not in `presentation/bloc/`. They contain application logic, not presentation logic.

### Separate BLoC Files

Each BLoC has separate files: `*_bloc.dart`, `*_event.dart`, `*_state.dart`. All BLoCs are registered in DI (`di.dart`).

### Domain Purity

The Domain layer contains only abstract interfaces and DTOs. No Flutter or Dio dependencies are allowed.

## Anti-Patterns (Forbidden)

| Pattern | Why It's Forbidden | Correct Approach |
|---------|-------------------|-----------------|
| Flutter project nested in subdirectory | Standard tooling, CI/CD, and IDE integrations expect root-level project | Place `lib/`, `test/`, `pubspec.yaml` at repository root |
| Presentation calling Infrastructure directly | Violates dependency flow | Go through Application/BLoC layer |
| Domain importing Flutter packages | Domain must be framework-agnostic | Keep domain layer pure Dart |
| BLoCs in `presentation/bloc/` | BLoCs contain application logic | Use `application/bloc/` |
| Missing layers in features | Incomplete feature structure | Each feature has domain, application, infrastructure, presentation |
| UI widgets with business logic | Business logic belongs in BLoCs | Extract logic to BLoC layer |
| Global `screens/` or `widgets/` directories | Code organized by type instead of feature | Organize by feature under `features/` |
| Cross-feature dependencies | Features should be self-contained | Use `common/` for shared code |

## Naming Conventions

- **Classes**: PascalCase (`LoginBloc`, `AuthRepository`)
- **Files**: snake_case (`login_bloc.dart`, `auth_repository.dart`)
- **Variables/methods**: camelCase (`getUserData`, `isLoading`)
- **Private members**: `_prefixed` (`_repository`, `_onLogin`)
- **BLoC files**: `{feature}_bloc.dart`, `{feature}_event.dart`, `{feature}_state.dart`
- **API Providers**: `{feature}_api_provider.dart`
- **Repository implementations**: `{feature}_repository_impl.dart`

## Development Principles

### Architecture Compliance Checklist

The following checklist is used for validating architectural compliance:

**Project Location Validation (Critical)**:
- Flutter project is at the repository root (`lib/`, `test/`, `pubspec.yaml` at root level)
- Flutter project is not nested in any subdirectory
- Changed files have paths starting with `lib/`, `test/`, not `any_folder/lib/`

**Base Structure Validation**:
- Core directories exist at root: `lib/features/`, `lib/common/`, `lib/settings/`
- Essential files at root: `lib/main.dart`, `lib/settings/di.dart`, `lib/settings/app_routes.dart`
- Test directory at root: `test/`
- Flutter config at root: `pubspec.yaml`, `analysis_options.yaml`

**Clean Architecture Layers**:
- Each feature has `domain/`, `application/`, `infrastructure/`, and `presentation/` directories
- Domain layer contains only abstract interfaces and DTOs (no Flutter/Dio dependencies)
- Application layer contains BLoC implementations
- Infrastructure layer contains concrete repository implementations and API providers
- Presentation layer contains only UI code (screens, widgets)

**Feature Organization**:
- Code is organized by feature, not by type
- Each feature is self-contained with its own layers
- Shared code is in `common/`, not scattered across features
- Features are in `lib/features/`

**Dependency Flow**:
- Dependencies flow inward: Presentation -> Application -> Domain
- Infrastructure depends on Domain (implements interfaces)
- Domain has no dependencies on outer layers
- No circular dependencies between layers

**BLoC Organization**:
- BLoCs are in `application/bloc/` (not `presentation/bloc/`)
- Each BLoC has separate files: `*_bloc.dart`, `*_event.dart`, `*_state.dart`
- BLoCs are registered in DI (`di.dart`)
