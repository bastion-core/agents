# State Management

This document describes the state management patterns, data flow, error handling, dependency injection, and testing strategy for Flutter applications using BLoC with Freezed sealed unions.

## State Pattern

### BLoC Pattern with Freezed

**Library**: flutter_bloc ^8.1.6

All BLoCs use Freezed for events and states, providing immutable sealed unions with exhaustive pattern matching. Events use `event.map()` for handling, states use `state.when()` for consumption in the UI.

### Conventions

- **Event naming**: Events describe user actions or system triggers in past tense or imperative. Examples: `checkUserExistence`, `login`, `reset`, `startChargingSession`, `updateProgress`.
- **State naming**: States describe the BLoC's current condition. Every BLoC includes `initial` and `loading` states. Examples: `initial`, `loading`, `userFound`, `loginSuccess`, `error`.
- **BLoC constructor**: BLoCs receive dependencies via constructor injection (not get_it directly). Dependencies are registered as factories in `di.dart`.

### Event Template (Freezed)

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part '{feature}_event.freezed.dart';

@freezed
class {Feature}Event with _${Feature}Event {
  const factory {Feature}Event.started() = _Started;
  const factory {Feature}Event.loadData() = _LoadData;
  const factory {Feature}Event.submitForm({
    required String field1,
    required String field2,
  }) = _SubmitForm;
  const factory {Feature}Event.reset() = _Reset;
}
```

### State Template (Freezed)

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part '{feature}_state.freezed.dart';

@freezed
class {Feature}State with _${Feature}State {
  const factory {Feature}State.initial() = _Initial;
  const factory {Feature}State.loading() = _Loading;
  const factory {Feature}State.loaded({
    required SomeDto data,
  }) = _Loaded;
  const factory {Feature}State.success({String? message}) = _Success;
  const factory {Feature}State.error(String message) = _Error;
}
```

### BLoC Template (event.map Pattern)

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '{feature}_event.dart';
import '{feature}_state.dart';
import '../../domain/repositories/{feature}_repository.dart';

class {Feature}Bloc extends Bloc<{Feature}Event, {Feature}State> {
  final {Feature}Repository _repository;
  final CombinedLogger _logger;

  {Feature}Bloc(this._repository, this._logger)
    : super(const {Feature}State.initial()) {
    on<{Feature}Event>((event, emit) async {
      await event.map(
        started: (_) => _onStarted(emit),
        loadData: (_) => _onLoadData(emit),
        submitForm: (e) => _onSubmitForm(e.field1, e.field2, emit),
        reset: (_) => _onReset(emit),
      );
    });
  }

  Future<void> _onStarted(Emitter<{Feature}State> emit) async {
    // initialization logic
  }

  Future<void> _onLoadData(Emitter<{Feature}State> emit) async {
    emit(const {Feature}State.loading());

    final result = await _repository.getData();

    result.when(
      success: (data) => emit({Feature}State.loaded(data: data)),
      failure: (error) => emit({Feature}State.error(error.message)),
    );
  }

  Future<void> _onSubmitForm(
    String field1,
    String field2,
    Emitter<{Feature}State> emit,
  ) async {
    if (field1.isEmpty || field2.isEmpty) return;

    emit(const {Feature}State.loading());

    final result = await _repository.submitForm(field1, field2);

    result.when(
      success: (_) => emit(const {Feature}State.success()),
      failure: (error) => emit({Feature}State.error(error.message)),
    );
  }

  Future<void> _onReset(Emitter<{Feature}State> emit) async {
    emit(const {Feature}State.initial());
  }
}
```

### Helper Pattern for Complex BLoCs

When a BLoC becomes too large (more than 6 event handlers or more than 200 lines), related event handlers are extracted into helper classes. Helpers receive the same dependencies as the BLoC and handle specific event groups.

**When to use**: Helpers are used when a BLoC manages multiple distinct concerns (e.g., QR scanning, session lifecycle, polling). Each helper handles a cohesive group of events.

**Location**: `features/{feature}/application/bloc/helpers/`

```dart
// In the BLoC constructor:
class ComplexBloc extends Bloc<ComplexEvent, ComplexState> {
  final GroupAHelper _groupAHelper;
  final GroupBHelper _groupBHelper;

  ComplexBloc({
    required SomeRepository repository,
    required CombinedLogger logger,
  }) : _groupAHelper = GroupAHelper(
         logger: logger,
         repository: repository,
       ),
       _groupBHelper = GroupBHelper(
         logger: logger,
         repository: repository,
       ),
       super(ComplexInitial()) {
    on<EventA>(_groupAHelper.onEventA);
    on<EventB>(_groupBHelper.onEventB);
  }
}

// Helper class:
class GroupAHelper {
  final CombinedLogger _logger;
  final SomeRepository _repository;

  GroupAHelper({
    required CombinedLogger logger,
    required SomeRepository repository,
  }) : _logger = logger,
       _repository = repository;

  Future<void> onEventA(
    EventA event,
    Emitter<ComplexState> emit,
  ) async {
    // handler logic
  }
}
```

### Alternative Event/State Style (Equatable-Based)

Some BLoCs use Equatable-based classes with `part of` directives instead of Freezed. This is acceptable for complex BLoCs where states carry many fields (more than 5) and need `copyWith` methods, or when event classes have complex hierarchies. Both styles are valid.

```dart
// Event file (part of bloc):
part of '{feature}_bloc.dart';

abstract class {Feature}Event extends Equatable {
  const {Feature}Event();
  @override
  List<Object?> get props => [];
}

class DoSomething extends {Feature}Event {
  final String param;
  const DoSomething(this.param);
  @override
  List<Object?> get props => [param];
}

// State file (part of bloc):
part of '{feature}_bloc.dart';

abstract class {Feature}State extends Equatable {
  const {Feature}State();
  @override
  List<Object?> get props => [];
}

class {Feature}Initial extends {Feature}State {}
class {Feature}Loading extends {Feature}State {}
class {Feature}Loaded extends {Feature}State {
  final SomeDto data;
  const {Feature}Loaded({required this.data});
  @override
  List<Object?> get props => [data];
}
```

## Data Flow

### BLoC UI Consumption

Three widget types are available for consuming BLoC state in the presentation layer:

#### BlocBuilder

Used for rebuilding widgets based on state changes. No side effects.

```dart
BlocBuilder<{Feature}Bloc, {Feature}State>(
  builder: (context, state) {
    return state.when(
      initial: () => const SizedBox.shrink(),
      loading: () => const CircularProgressIndicator(),
      loaded: (data) => DataWidget(data: data),
      error: (message) => ErrorWidget(message: message),
    );
  },
)
```

#### BlocConsumer

Used for side effects (navigation, snackbars) combined with widget rebuilds.

```dart
BlocConsumer<{Feature}Bloc, {Feature}State>(
  listener: (context, state) {
    state.whenOrNull(
      success: (_) => context.go(AppRoutes.home),
      error: (message) => {Project}Snackbar.showError(context, message),
    );
  },
  builder: (context, state) {
    return state.when(
      initial: () => FormWidget(),
      loading: () => const LoadingWidget(),
      success: (_) => const SizedBox.shrink(),
      error: (_) => FormWidget(),
    );
  },
)
```

#### BlocListener

Used for side effects only (no widget rebuild).

```dart
BlocListener<{Feature}Bloc, {Feature}State>(
  listener: (context, state) {
    state.whenOrNull(
      error: (message) => {Project}Snackbar.showError(context, message),
    );
  },
  child: SomeWidget(),
)
```

#### When to Use Each Widget

| Widget | Rebuild UI | Side Effects | Use Case |
|--------|-----------|-------------|----------|
| `BlocBuilder` | Yes | No | Pure UI rebuilds based on state |
| `BlocConsumer` | Yes | Yes | Navigation + snackbars + UI rebuild |
| `BlocListener` | No | Yes | Pure side effects (no rebuild needed) |

- `state.when()` is used for exhaustive pattern matching (covers all state variants)
- `state.whenOrNull()` is used for selective handling (only handle specific states)

### Global vs Local BLoC Providers

**Global BLoCs** are provided at app root via `MultiBlocProvider`. They persist across all screens. Only BLoCs whose state must survive navigation are provided globally (e.g., `ChargingSessionBloc`, `ConnectivityBloc`).

**Local BLoCs** are feature-specific and provided locally in their respective screens using `BlocProvider(create: (_) => getIt<{Feature}Bloc>())`. They are not provided globally.

## Error Handling

### Result<T>

Custom `Result<T>` sealed class (Either-like pattern).

**Location**: `common/infrastructure/networking/result.dart`

**Variants**:
- `Result.success(T data)` -- wraps successful data
- `Result.failure(RequestError error)` -- wraps error information

**Consumption**:

```dart
result.when(
  success: (data) {
    // handle success
  },
  failure: (error) {
    // handle failure
  },
);
```

### RequestError

Sealed class for categorized API errors.

**Location**: `common/infrastructure/networking/result.dart`

**Variants**:
- `RequestError.connectivity(message)` -- no internet connection
- `RequestError.response(error)` -- DioException with response data
- `RequestError.timeout(message)` -- request timed out
- `RequestError.unknown(message)` -- unexpected error

**Properties**:
- `type: String` -- error category for analytics (`'connectivity'`, `'timeout'`, `'response'`, `'unknown'`)
- `message: String` -- user-friendly error message

### Error Handling Rules

- All repositories and API providers return `Result<T>`
- Exceptions are not thrown in business logic
- `DioException` is caught in API providers
- A catch-all is provided for unexpected errors
- `error.message` is used for user-facing messages
- `error.type` is used for analytics classification

### API Provider Error Handling Template

```dart
class {Feature}ApiProvider extends BaseApiProvider {
  {Feature}ApiProvider(super.dio);

  Future<Result<SomeDto>> getData(String id) async {
    try {
      final response = await dio.get(
        UrlPaths.someEndpoint(id),
      );

      final responseData = response.data as Map<String, dynamic>;
      final dataList = responseData['data'] as List<dynamic>?;

      if (dataList == null || dataList.isEmpty) {
        return Result.failure(
          RequestError.unknown(message: 'Data not found'),
        );
      }

      final data = dataList.first as Map<String, dynamic>;
      return Result.success(SomeDto.fromJson(data));
    } on DioException catch (e) {
      return Result.failure(RequestError.response(error: e));
    } catch (e) {
      return Result.failure(
        RequestError.unknown(message: 'Error fetching data'),
      );
    }
  }
}
```

## Dependency Injection

**Library**: get_it ^7.7.0
**Pattern**: Manual service locator with feature-grouped registration
**File**: `settings/di.dart`

### Registration Types

| Type | Use For | Behavior |
|------|---------|----------|
| `registerLazySingleton` | Services, repositories, API providers | Created once on first access, reused thereafter |
| `registerFactory` | BLoCs | New instance created every time it is requested |

### Setup Structure

```dart
final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // 1. External services (SharedPreferences, PackageInfo, Firebase)
  // 2. Dio setup (BaseOptions, interceptor)
  // 3. Feature dependencies (grouped by feature)
  // 4. Cross-cutting services (AppVersionService, AnalyticsService)
}
```

### Feature Registration Pattern

```dart
void _register{Feature}Dependencies() {
  // API Provider
  getIt.registerLazySingleton<{Feature}ApiProvider>(
    () => {Feature}ApiProvider(getIt<Dio>()),
  );

  // Repository (register abstract type)
  getIt.registerLazySingleton<{Feature}Repository>(
    () => {Feature}RepositoryImpl(apiProvider: getIt<{Feature}ApiProvider>()),
  );

  // Services (if applicable)
  getIt.registerLazySingleton<{Feature}Service>(
    () => {Feature}ServiceImpl(getIt<SomeDependency>()),
  );

  // BLoCs (always registerFactory)
  getIt.registerFactory<{Feature}Bloc>(
    () => {Feature}Bloc(
      getIt<{Feature}Repository>(),
      getIt<CombinedLogger>(),
      getIt<AnalyticsService>(),
    ),
  );
}
```

### DI Rules

- `registerFactory` is used for BLoCs (new instance per widget)
- `registerLazySingleton` is used for services and repositories
- Abstract types (interfaces) are registered pointing to concrete implementations
- Registrations are grouped by feature in private methods
- `injectable` and auto-DI packages are not used -- manual registration is preferred
- `getIt` is not accessed directly from BLoCs or repositories -- injection is via constructor
- `setupDependencies()` is called once in `main.dart` before `runApp()`

## Testing Strategy

### Libraries

- **flutter_test** (Flutter SDK)
- **bloc_test ^9.1.7** -- BLoC testing utilities
- **mockito ^5.4.4** -- Mocking framework

### Testing Focus

- **BLoC tests**: 70% of test coverage
- **Infrastructure tests**: 20% of test coverage
- **Domain logic tests**: 10% of test coverage

### Conventions

- **Pattern**: AAA (Arrange-Act-Assert)
- **Grouping**: `group()` for logical test sections (by event type, by scenario)
- **Naming**: Descriptive strings: `'emits [loading, success] when data is fetched'`

### BLoC Test Template

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:app/common/infrastructure/networking/result.dart';

import 'mocks/{feature}_mock.mocks.dart';

// Fake for services that need all methods stubbed
class FakeAnalyticsService extends Fake implements AnalyticsService {
  @override
  Future<void> logSomeEvent({required String param}) async {}
}

// Mock for services where specific calls need verification/stubbing
class MockCombinedLogger extends Mock implements CombinedLogger {}

void main() {
  late Mock{Feature}Repository mockRepository;
  late MockCombinedLogger mockLogger;
  late FakeAnalyticsService fakeAnalytics;
  late {Feature}Bloc bloc;

  // Provide dummy values for Result<T> types
  setUpAll(() {
    provideDummy<Result<SomeDto>>(
      Result.failure(RequestError.unknown(message: 'dummy')),
    );
  });

  setUp(() {
    mockRepository = Mock{Feature}Repository();
    mockLogger = MockCombinedLogger();
    fakeAnalytics = FakeAnalyticsService();

    bloc = {Feature}Bloc(
      mockRepository,
      mockLogger,
      fakeAnalytics,
    );
  });

  tearDown(() {
    bloc.close();
  });

  group('{Feature}Bloc', () {
    test('initial state is {Feature}State.initial()', () {
      expect(bloc.state, const {Feature}State.initial());
    });

    group('LoadData', () {
      blocTest<{Feature}Bloc, {Feature}State>(
        'emits [loading, loaded] when data is fetched successfully',
        build: () {
          when(mockRepository.getData())
              .thenAnswer((_) async => Result.success(testData));
          return bloc;
        },
        act: (bloc) => bloc.add(const {Feature}Event.loadData()),
        expect: () => [
          const {Feature}State.loading(),
          {Feature}State.loaded(data: testData),
        ],
        verify: (_) {
          verify(mockRepository.getData()).called(1);
        },
      );

      blocTest<{Feature}Bloc, {Feature}State>(
        'emits [loading, error] when fetch fails',
        build: () {
          when(mockRepository.getData()).thenAnswer(
            (_) async => Result.failure(
              RequestError.connectivity(message: 'No internet'),
            ),
          );
          return bloc;
        },
        act: (bloc) => bloc.add(const {Feature}Event.loadData()),
        expect: () => [
          const {Feature}State.loading(),
          isA<{Feature}State>().having(
            (s) => s.maybeWhen(error: (msg) => msg, orElse: () => ''),
            'error message',
            contains('No internet'),
          ),
        ],
      );
    });

    group('Reset', () {
      blocTest<{Feature}Bloc, {Feature}State>(
        'emits [initial] when reset from any state',
        build: () => bloc,
        seed: () => const {Feature}State.loading(),
        act: (bloc) => bloc.add(const {Feature}Event.reset()),
        expect: () => [const {Feature}State.initial()],
      );
    });
  });
}
```

### Mock Generation

**File**: `test/features/{feature}/application/bloc/mocks/{feature}_mock.dart`

```dart
import 'package:mockito/annotations.dart';
import 'package:app/features/{feature}/domain/repositories/{feature}_repository.dart';

@GenerateMocks([{Feature}Repository, SomeService])
void main() {}
```

After creating or modifying `@GenerateMocks`, run code generation:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Key Testing Patterns

#### provideDummy

Used in `setUpAll()` for complex generic types that Mockito cannot auto-generate stubs for:

```dart
setUpAll(() {
  provideDummy<Result<SomeDto>>(
    Result.failure(RequestError.unknown(message: 'dummy')),
  );
});
```

#### seed

Used in `blocTest` to start from a specific state:

```dart
blocTest<Bloc, State>(
  'resets from loaded state',
  build: () => bloc,
  seed: () => const State.loaded(data: someData),
  act: (bloc) => bloc.add(const Event.reset()),
  expect: () => [const State.initial()],
);
```

#### Sequential Events

`Future.delayed` is used between events in `act:` to test sequential event flows:

```dart
act: (bloc) async {
  bloc.add(const {Feature}Event.loadData());
  await Future.delayed(const Duration(milliseconds: 100));
  bloc.add(const {Feature}Event.submit());
},
```

#### Fake vs Mock

| Type | Use For | Example |
|------|---------|---------|
| `Fake` (`extends Fake implements Service`) | Services where all methods need no-op implementations | `AnalyticsService`, `CombinedLogger` |
| `Mock` (`extends Mock implements Service`) | Services where calls need verification and return value stubbing | Repositories, services with specific return values |

#### verifyNever

`verifyNever(mock.method(any))` asserts a method was not called (e.g., when input validation prevents API call).

### Testing Rules

- Initial state is always tested
- Success and failure paths are tested for each event
- Dummy values are provided for `Result<T>` types in `setUpAll`
- BLoC is closed in `tearDown`
- `blocTest` helper is used for BLoC tests
- `Fake` is used for analytics/logger services (stub all methods)
- `Mock` is used for repositories and services (verify specific calls)
- Edge cases are tested: empty input, null values, error states
- Sequential events are tested with `Future.delayed`
- State transitions from specific seed states are tested
