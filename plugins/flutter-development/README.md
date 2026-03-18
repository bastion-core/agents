# Flutter Development Plugin

Specialized agents for Flutter and Dart mobile development and code review, enforcing Clean Architecture with Feature-Based Modularization, BLoC+Freezed state management, and Result<T> error handling.

## Available Agents

### Development Agents

#### mobile-flutter.md
Flutter Mobile Development Agent specializing in Clean Architecture with Feature-Based Modularization for production-ready Flutter apps (iOS + Android).

**Use cases**:
- Implement new features following Clean Architecture (4 layers)
- Create BLoCs with Freezed events/states
- Build API integrations with Result<T> error handling
- Set up dependency injection with get_it
- Generate comprehensive BLoC tests

**Architecture**: Clean Architecture with 4 layers (Presentation, Application/BLoC, Domain, Infrastructure)

### Code Review Agents

#### reviewer-mobile-flutter.md
Comprehensive code reviewer for Flutter mobile PRs, combining architecture analysis, code quality validation, and testing coverage assessment.

**Review dimensions**:
- Architecture (30%): Clean Architecture compliance, dependency direction, layer separation
- Code Quality (40%): Dart/Freezed patterns, BLoC checks, repository/API/DTO/DI validation
- Testing (30%): BLoC tests with bloc_test, mock patterns, coverage targets

#### reviewer-flutter-app.md (legacy)
General Flutter code reviewer. Superseded by reviewer-mobile-flutter for projects using Clean Architecture with BLoC+Freezed.

## Technology Stack

- **Framework**: Flutter SDK + Dart SDK ^3.7.2
- **State Management**: flutter_bloc ^8.1.6 + Freezed
- **HTTP Client**: Dio ^5.6.0
- **DI**: get_it ^7.7.0
- **Routing**: go_router ^14.2.0
- **Error Handling**: Result<T> sealed class
- **Testing**: bloc_test + Mockito

## Usage

```bash
# Install agents
./scripts/sync-agents.sh
# Select: mobile-flutter, reviewer-mobile-flutter
```
