# Convenciones Mobile Flutter

Resumen de convenciones arquitectonicas para generacion de especificaciones tecnicas de proyectos Flutter.

## Stack Tecnologico

- **Framework**: Flutter SDK (latest stable) + Dart SDK ^3.7.2
- **Plataformas**: iOS + Android (single codebase)
- **State Management**: flutter_bloc ^8.1.6 con Freezed sealed unions
- **HTTP Client**: Dio ^5.6.0 con interceptor custom
- **Dependency Injection**: get_it ^7.7.0 (service locator manual)
- **Routing**: go_router ^14.2.0
- **Data Classes**: freezed_annotation ^2.4.4, freezed ^2.4.4
- **JSON**: json_annotation ^4.9.0, json_serializable ^6.8.0
- **Local Storage**: shared_preferences ^2.3.2
- **i18n**: i18n_extension ^15.0.4
- **Testing**: bloc_test ^9.1.7, mockito ^5.4.4
- **Firebase**: firebase_core, firebase_messaging, cloud_firestore, firebase_analytics, firebase_crashlytics
- **Code Generation**: build_runner ^2.4.9

## Arquitectura: Clean Architecture con Feature-Based Modularization (4 Capas)

Estilo: Modular Monolith (single Flutter app). Organizacion feature-first en el nivel superior, luego por capas dentro de cada feature.

### Las 4 Capas

**1. Presentation** (`features/{feature}/presentation/`)
- Screens (una por ruta) y widgets feature-specific
- Consume BLoC states via BlocBuilder/BlocConsumer
- Despacha eventos al BLoC
- NUNCA contiene logica de negocio

**2. Application (BLoC)** (`features/{feature}/application/bloc/`)
- BLoC classes que orquestan logica de negocio
- Maneja eventos, llama repositorios/servicios, emite estados
- Reemplaza UseCases/Interactors tradicionales — BLoCs llaman repositorios directamente
- Helpers opcionales para BLoCs complejos (>6 handlers o >200 lineas)

**3. Domain** (`features/{feature}/domain/`)
- Contratos de negocio: interfaces abstractas de repositorios y servicios
- DTOs (Freezed classes), enums, modelos de dominio
- SIN codigo de implementacion, SIN dependencias de infraestructura
- Depende de: NADA (zero dependencies)

**4. Infrastructure** (`features/{feature}/infrastructure/`)
- Implementaciones concretas de interfaces del dominio
- API providers (Dio calls), implementaciones de repositorios y servicios
- Storage services (SharedPreferences)

### Flujo de Dependencias
```
Presentation -> Application (BLoC) -> Domain (Interfaces) <- Infrastructure (Implementations)
```

## 5 Decisiones Criticas de Arquitectura

### Decision 1: No Separate Entity Layer
Los DTOs sirven como carriers de datos Y como entidades de dominio. NUNCA crear carpeta `entities/` ni clases Entity separadas.

### Decision 2: No UseCase/Interactor Classes
Los BLoCs llaman repositorios directamente. NUNCA crear carpetas `usecase/` ni `interactor/`.

### Decision 3: No Mapper Classes
Los DTOs manejan su propia serializacion via factories `fromJson` custom. NUNCA crear carpetas `mapper/` ni clases Mapper.

### Decision 4: DTOs Live in domain/
Los DTOs se usan en todas las capas. SIEMPRE colocarlos en `features/{feature}/domain/dtos/`.

### Decision 5: Helper Classes for Complex BLoCs
Cuando un BLoC tiene >5-6 event handlers o handlers >50 lineas, extraer a helpers en `features/{feature}/application/bloc/helpers/`.

## Estructura de Carpetas

```
lib/
  main.dart
  common/                           # Cross-cutting concerns
    application/bloc/               # BLoCs compartidos (ConnectivityBloc)
    domain/services/                # Interfaces compartidas
    infrastructure/                 # BaseApiProvider, interceptor
      networking/                   # Result<T> y RequestError
    presentation/widgets/           # Widgets compartidos
    ui/                            # Capa de abstraccion UI del proyecto
  features/                        # Feature modules (self-contained)
    {feature_name}/
      application/bloc/            # BLoC + events + states + helpers
      domain/
        dtos/                      # Freezed DTOs
        enums/                     # Enums feature-specific
        models/                    # Modelos de dominio
        repositories/              # Interfaces abstractas de repositorio
        services/                  # Interfaces abstractas de servicio
      infrastructure/              # API providers, repo impls, service impls
      presentation/
        screens/                   # Pantallas completas
        widgets/                   # Widgets feature-specific
  settings/                        # Configuracion de la app
    di.dart                        # Setup de dependency injection (get_it)
    app_routes.dart                # GoRouter configuration
    url_paths.dart                 # URL paths centralizados
```

## Result<T> Pattern (Manejo de Errores)

Sealed class custom tipo Either:
- `Result.success(T data)` — envuelve datos exitosos
- `Result.failure(RequestError error)` — envuelve informacion de error

**RequestError** variantes:
- `RequestError.connectivity(message)` — sin internet
- `RequestError.response(error)` — DioException con response
- `RequestError.timeout(message)` — timeout
- `RequestError.unknown(message)` — error inesperado

**Consumo:**
```
result.when(
  success: (data) => ...,
  failure: (error) => ...,
);
```

- SIEMPRE retornar Result<T> desde repositorios y API providers
- NUNCA lanzar excepciones en logica de negocio
- SIEMPRE capturar DioException en API providers

## BLoC Pattern con Freezed

- Eventos usan `event.map()` para delegation
- Estados usan `state.when()` para consumo en UI
- Constructor del BLoC recibe dependencias via inyeccion (no get_it directo)
- Registrar BLoCs como `registerFactory` en DI (nueva instancia por widget)

**BlocBuilder**: solo rebuilds de UI basados en estado
**BlocConsumer**: side effects (navegacion, snackbars) + rebuilds
**BlocListener**: solo side effects (sin rebuild)

## DTOs con Freezed

- SIEMPRE usar `@freezed` annotation
- Request DTOs: json_serializable auto-generated (incluir `.g.dart`)
- Response DTOs: factory `fromJson` CUSTOM (solo `.freezed.dart`)
- Extraer primer elemento del array `data` cuando API retorna envelope
- NUNCA crear clases Entity separadas — DTOs SON las entidades
- NUNCA crear clases Mapper — DTOs manejan su propia serializacion

## Dependency Injection (get_it)

- `registerFactory` para BLoCs (nueva instancia por widget)
- `registerLazySingleton` para servicios, repositorios, API providers
- SIEMPRE registrar tipos abstractos (interfaces), no concretos
- Agrupar registros por feature en metodos privados
- NUNCA acceder a getIt directamente desde BLoCs o repos — inyectar via constructor

## Naming Conventions

| Tipo | Convencion | Ejemplo |
|------|-----------|---------|
| Screen | `{screen_name}_screen.dart` | `notifications_screen.dart` |
| Widget | `{widget_name}_widget.dart` | `notification_card_widget.dart` |
| BLoC | `{feature}_bloc.dart` | `notifications_bloc.dart` |
| Event | `{feature}_event.dart` | `notifications_event.dart` |
| State | `{feature}_state.dart` | `notifications_state.dart` |
| Request DTO | `{name}_request_dto.dart` | `mark_read_request_dto.dart` |
| Response DTO | `{name}_response_dto.dart` | `notification_response_dto.dart` |
| Test | `{source_file}_test.dart` | `notifications_bloc_test.dart` |

## Feature-Based Modularization

- Cada feature DEBE tener las 4 capas: application/, domain/, infrastructure/, presentation/
- Codigo compartido va en `common/`, NUNCA en un feature especifico
- NUNCA crear carpeta `core/` o `shared/` — usar `common/`
- NUNCA crear carpeta `data/` — usar `infrastructure/`
- NUNCA anidar features dentro de otras features

## Testing

- **Foco**: BLoC tests = 70% de cobertura, Infrastructure = 20%, Domain = 10%
- **Pattern**: AAA (Arrange-Act-Assert)
- **BLoC Tests**: usar `blocTest` helper de bloc_test
- SIEMPRE testear estado inicial, caminos de exito y fallo
- `provideDummy<Result<T>>()` en setUpAll para tipos genericos
- Cerrar BLoC en tearDown
- Fake para analytics/logger (stub all methods), Mock para repos (verify specific calls)
- `seed:` para testear desde estados especificos

## Anti-Patterns (PROHIBIDOS)

| Anti-Pattern | Alternativa Correcta |
|-------------|---------------------|
| Capa de Entity separada | Freezed DTOs en domain/dtos/ |
| Clases Mapper | fromJson en factory del DTO |
| UseCase/Interactor classes | BLoCs llaman repos directamente |
| injectable / auto DI | Registro manual en di.dart |
| auto_route | go_router |
| ScreenUtil | MediaQuery, LayoutBuilder, Flex |
| Lanzar excepciones en negocio | Result<T> pattern |
| BLoC base abstracto | BLoCs independientes + helpers |
| Carpeta data/ | Usar infrastructure/ |
| Carpeta core/ o shared/ | Usar common/ |
| Importar UI library directamente | Usar capa de abstraccion UI del proyecto |
| Color values directos en widgets | Constantes centralizadas de colores |
