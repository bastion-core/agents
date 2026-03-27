# State Management

This document describes the pattern consistency requirements, BLoC conventions, repository pattern, error handling, dependency injection, and testing coverage expectations for Flutter applications using BLoC with Freezed.

## State Pattern

### BLoC Pattern

**Library**: flutter_bloc ^8.1.6

The BLoC pattern is the standard state management approach. All BLoCs follow these conventions:

- All dependencies are injected via constructor -- `getIt<T>()` is never accessed inside a BLoC
- Event handlers are private with `_on` prefix: `_onLoadHistory`, `_onRefresh`
- `event.map()` is used for exhaustive event handling (compile-time safety)
- Errors are handled with `result.when()` -- `try/catch` is not used for expected API failures
- Single responsibility: maximum 5-6 event types per BLoC, maximum 400 lines; BLoC is split if exceeded
- States are immutable -- Freezed `copyWith` is used for updates, no mutable internal variables
- User-facing error messages in states use translation keys (`.i18n`), not hardcoded strings

### BLoC Template (Correct Pattern)

```dart
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeRepository _repository;
  final TokenService _tokenService;
  final CombinedLogger _logger;

  HomeBloc(this._repository, this._tokenService, this._logger)
    : super(const HomeState.initial()) {
    on<HomeEvent>((event, emit) async {
      await event.map(
        loadHistory: (e) => _onLoadHistory(e, emit),
        refresh: (e) => _onRefresh(e, emit),
      );
    });
  }

  Future<void> _onLoadHistory(_LoadHistory event, Emitter<HomeState> emit) async {
    emit(const HomeState.loading());
    final result = await _repository.getHistory();
    result.when(
      success: (data) => emit(HomeState.loaded(data)),
      failure: (error) => emit(HomeState.error(error.toString())),
    );
  }
}
```

### Common BLoC Anti-Pattern (Direct Service Locator)

The following pattern is incorrect -- dependencies are never resolved via `getIt` inside a BLoC:

```dart
// INCORRECT
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeRepository _repository;
  final CombinedLogger _logger = getIt<CombinedLogger>(); // Direct getIt

  void _onLoadHistory(...) {
    final tokenService = getIt<TokenService>(); // Direct getIt inside method
  }
}
```

### State Management with Freezed

All states and events use the `@freezed` annotation. States are immutable. `copyWith()` is used for state updates. Equatable is not used -- Freezed replaces it.

```dart
@freezed
class LoginState with _$LoginState {
  const factory LoginState.initial() = _Initial;
  const factory LoginState.loading() = _Loading;
  const factory LoginState.success(UserDto user) = _Success;
  const factory LoginState.error(String message) = _Error;
}
```

## Data Flow

### Repository Pattern

All repositories have abstract interfaces in `domain/repositories/`. Implementations are in `infrastructure/*_repository_impl.dart`. Repositories return `Result<T>` type (never throw exceptions). BLoCs depend on repository interfaces, not implementations.

```dart
// Abstract interface (domain/repositories/)
abstract class AuthRepository {
  Future<Result<LoginResponseDto>> login(LoginRequestDto request);
}

// Implementation (infrastructure/)
class AuthRepositoryImpl implements AuthRepository {
  final AuthApiProvider _apiProvider;

  @override
  Future<Result<LoginResponseDto>> login(LoginRequestDto request) async {
    return await _apiProvider.login(request);
  }
}
```

### API Provider Pattern

All API providers extend `BaseApiProvider`. API calls return `Result<T>`. Dio is used for HTTP requests. Every API endpoint is documented with a comment showing HTTP method, path, and body:

```dart
/// Start charging session
/// POST /api/v1/charging/start
/// Body: { "evseId": int, "paymentMethodId": string }
Future<Result<StartChargingResponseDto>> startCharging(
  StartChargingRequestDto request,
) async { ... }
```

All DTOs use Freezed + json_serializable (Request DTOs have `toJson()`, Response DTOs have `fromJson()`). No hardcoded API URLs -- all endpoints are in `url_paths.dart`.

## Error Handling

### Result/Either Pattern

All async operations return `Result<T>`. The pattern uses `Result.success()` for successful operations and `Result.failure()` with specific `RequestError` types for errors. Errors are handled with the `.when()` method.

```dart
// Correct pattern
final result = await _repository.login(request);
result.when(
  success: (response) => emit(LoginState.success(response)),
  failure: (error) => emit(LoginState.error(error.message)),
);
```

The `try/catch` approach for expected API failures is not used:

```dart
// Incorrect pattern
try {
  final response = await _repository.login(request);
  emit(LoginState.success(response));
} catch (e) {
  emit(LoginState.error(e.toString()));
}
```

### Navigation

GoRouter is used exclusively for navigation:

- `context.go()` for navigation with replacement
- `context.push()` for adding to stack
- `context.pop()` only for dismissing modals
- `Navigator.push()` is not mixed with GoRouter

## Dependency Injection

**Library**: GetIt v7.7.0
**File**: `settings/di.dart`

### Registration Rules

| Type | Registration | Reason |
|------|-------------|--------|
| BLoCs | `registerFactory` | New instance per widget; prevents memory leaks and state contamination |
| Services | `registerLazySingleton` | Shared single instance |
| Repositories | `registerLazySingleton` | Shared single instance |

```dart
// Correct -- Factory for BLoC
getIt.registerFactory<LoginBloc>(
  () => LoginBloc(getIt<AuthRepository>()),
);

// Incorrect -- Singleton for BLoC (causes memory leaks)
getIt.registerSingleton<ChargingSessionBloc>(
  ChargingSessionBloc(/* ... */),
);
```

All dependencies are registered in `settings/di.dart`. BLoCs are registered as Factory (not Singleton). Services and repositories are registered as LazySingleton.

## Testing Strategy

### BLoC Test Requirements

- **Target BLoC coverage**: 95%+
- `blocTest<B, S>()` from `bloc_test` package is the standard test helper
- Mockito with `@GenerateMocks` is used for mocking repositories and services

### Dummy Values for Sealed Types

Dummy values are provided for sealed `Result<T>` types that Mockito cannot auto-generate:

```dart
setUpAll(() {
  provideDummy<Result<MyResponseDto>>(
    Result.failure(RequestError.unknown(message: 'dummy')),
  );
});
```

### Test Structure

```dart
void main() {
  late MockRepository mockRepository;
  late FeatureBloc bloc;

  setUpAll(() {
    provideDummy<Result<SomeDto>>(
      Result.failure(RequestError.unknown(message: 'dummy')),
    );
  });

  setUp(() {
    mockRepository = MockRepository();
    bloc = FeatureBloc(mockRepository);
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state is ...', () {
    expect(bloc.state, const FeatureState.initial());
  });

  group('EventName', () {
    blocTest<FeatureBloc, FeatureState>(
      'emits [loading, loaded] when data fetched successfully',
      build: () {
        when(mockRepository.getData())
            .thenAnswer((_) async => Result.success(testData));
        return bloc;
      },
      act: (bloc) => bloc.add(const FeatureEvent.loadData()),
      expect: () => [
        const FeatureState.loading(),
        FeatureState.loaded(data: testData),
      ],
      verify: (_) {
        verify(mockRepository.getData()).called(1);
      },
    );
  });
}
```

### Test Naming and Organization

- `test('initial state is ...', ...)` -- verifies initial state
- `group('EventName', () { ... })` -- groups tests by event
- Test names describe: what is tested + conditions + expected outcome
- `verify()` confirms repository/service calls
- `verifyNever()` confirms methods are not called in error paths

### Coverage Targets

| Component | Target Coverage |
|-----------|----------------|
| BLoCs | 95%+ (comprehensive tests required) |
| Repositories | 80% (success responses, HTTP error handling, data transformation) |
| Services | 75% (critical services required) |
| DTOs | 60% of critical ones (serialization roundtrip, nullable fields) |

### Fake vs Mock

| Type | Use For | Example |
|------|---------|---------|
| `Fake` (`extends Fake implements Service`) | Services where all methods need no-op implementations | `AnalyticsService`, `CombinedLogger` |
| `Mock` (`extends Mock implements Service`) | Services where calls need verification and return value stubbing | Repositories, services with specific return values |

### Test Quality Checklist

- Tests follow AAA pattern (Arrange, Act, Assert)
- Tests use proper mocks (mockito with `@GenerateMocks`)
- Tests are independent (no shared state, proper `setUp`/`tearDown`)
- Tests have descriptive names
- Tests verify behavior, not implementation
- All tests pass before committing (`flutter test`)

### Test Scope

- **Unit Tests** (70% of effort): All BLoCs, repositories, critical services, DTO serialization
- **Widget Tests** (20% of effort): Critical screens (login, OTP, payment), form validation, button states, loading indicators
- **Integration Tests** (10% of effort): Critical user flows (login flow, charging session flow, payment flow)
