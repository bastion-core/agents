# UI Component Patterns

This document describes the 3-layer component architecture, the mandatory base library, project wrapper patterns, centralized component requirements, and import rules for Flutter applications.

## Component Architecture

The UI component architecture follows a **3-layer pattern** that ensures visual consistency, makes it easy to customize the design system per project, and allows swapping the underlying library without touching feature code.

### Layer 1: Base Library (`flutter_components_library`)

Provides generic, reusable UI components (buttons, text, text fields, snackbars, bottom sheets, etc.). Added as a dependency in `pubspec.yaml` from the [Voltop Flutter Components Library](https://github.com/Voltop-SAS/flutter-components-library).

Every project uses `flutter_components_library` as the base component library.

### Layer 2: Project Wrappers (`lib/common/ui/{project}_ui.dart`)

Each project creates its own wrapper components (`{Project}Button`, `{Project}Text`, `{Project}TextField`, etc.) that internally import and configure `flutter_components_library` with project-specific styles, colors, and defaults.

The wrapper file lives at `lib/common/ui/{project}_ui.dart` (or an equivalent barrel file).

### Layer 3: Feature UI (`lib/features/*/presentation/`)

Screens and widgets only import the project wrappers. They never import `flutter_components_library` directly.

### Architecture Diagram

```
+-----------------------------------------------------+
|  Feature Screens & Widgets (presentation/)           |
|  -> ONLY imports: {project}_ui.dart                  |
+-----------------------------------------------------+
|  Project Wrappers (lib/common/ui/{project}_ui.dart)  |
|  -> Imports: flutter_components_library              |
|  -> Exports: {Project}Button, {Project}Text, etc.    |
+-----------------------------------------------------+
|  flutter_components_library (base package)            |
|  -> github.com/Voltop-SAS/flutter-components-library |
+-----------------------------------------------------+
```

## Component Categories

The project wrappers cover the following component categories:

| Category | Project Component | Replaces |
|----------|------------------|----------|
| **Buttons** | `{Project}Button.primary()`, `.secondary()` | `ElevatedButton`, `TextButton`, `OutlinedButton` |
| **Typography** | `{Project}Text.heading()`, `.body()`, `.caption()` | `Text` widget |
| **Inputs** | `{Project}TextField()`, `.phone()`, `.password()` | `TextField` widget |
| **Feedback** | `{Project}Snackbar.showSuccess()`, `.showError()`, `.showInfo()` | `ScaffoldMessenger.showSnackBar()` |
| **Overlays** | `{Project}BottomSheet.show()` | `showModalBottomSheet()` |
| **Colors** | `{Project}Colors.primary`, `.background`, `.error` | `Color(0xFF...)`, `Colors.*` |

## Component Resolution Flow

When a UI component is needed, the following resolution applies:

1. **Check project wrappers first**: Look in `lib/common/ui/{project}_ui.dart` for an existing component
2. **If not in wrappers but in base library**: Create a corresponding project wrapper before using it
3. **If not in base library**: Build a new component in `common/ui/` using the project's color constants and typography

## Component Templates

### Project Wrapper File Example

```dart
// lib/common/ui/acme_ui.dart
import 'package:flutter_components_library/flutter_components_library.dart';

class AcmeButton {
  static Widget primary({required String text, required VoidCallback onPressed}) {
    return ComponentsButton.primary(
      text: text,
      onPressed: onPressed,
      // Project-specific customization
      borderRadius: 12,
      textStyle: AcmeTextStyles.button,
    );
  }
}
```

### Feature Screen Usage (Correct)

```dart
// lib/features/auth/presentation/screens/login_screen.dart
import 'package:acme_app/common/ui/acme_ui.dart';

// Using project wrappers
AcmeButton.primary(text: 'continue_button'.i18n, onPressed: () {})
AcmeText.heading('charging_title'.i18n)
AcmeTextField.phone(controller: phoneController)
AcmeSnackbar.showError(context, 'error_message'.i18n)
AcmeBottomSheet.show(context: context, child: MyWidget())
```

### Feature Screen Usage (Incorrect)

```dart
// Bypasses project wrapper -- NOT allowed
import 'package:flutter_components_library/flutter_components_library.dart';
ComponentsButton.primary(text: 'Continue', onPressed: () {})
ComponentsText.heading('Title')
```

### Raw Flutter Widgets Allowed For

The following raw Flutter widgets are acceptable in feature code because they have no project UI equivalent:

- **Layout**: `Row`, `Column`, `Stack`, `Expanded`, `Container`, `Padding`, `SizedBox`
- **Structural**: `Scaffold`, `AppBar`, `SafeArea`, `CustomScrollView`, `ListView`
- **Navigation**: `Navigator`, `GoRouter`
- **Special-purpose**: Widgets with no project UI equivalent

### Color Usage

All colors use `{Project}Colors.*` from the project's color palette file. Inline `Color(0xFF...)` values and `Colors.*` from Flutter are not used (except `Colors.transparent`, which is acceptable).

```dart
// Correct
color: {Project}Colors.primary
backgroundColor: {Project}Colors.background

// Incorrect
color: Color(0xFF0FC7E1)
color: Colors.blue
```

### Bottom Sheet and Snackbar Wrappers

`{Project}BottomSheet.show()` is used instead of raw `showModalBottomSheet()`. The wrapper provides `isScrollControlled: true`, `backgroundColor: Colors.transparent`, and `useSafeArea: true` by default.

`{Project}Snackbar` is used instead of `ScaffoldMessenger.showSnackBar`.

## Rules and Constraints

### Mandatory Requirements

1. `flutter_components_library` is listed in `pubspec.yaml` dependencies
2. A project wrapper file exists at `lib/common/ui/{project}_ui.dart` (or equivalent barrel file)
3. The project wrapper file imports `flutter_components_library` and re-exports customized components
4. Custom project components (`{Project}Button`, `{Project}Text`, etc.) wrap and configure the base library components with project-specific theming

### Import Rules

1. Feature/screen code never imports `flutter_components_library` directly -- only the project wrapper
2. Only `lib/common/ui/` files import the base library
3. When the base library adds new components, the project creates corresponding wrappers before using them

### Centralized Component Checklist

- All UI elements use the project's centralized UI components (`{Project}Button`, `{Project}Text`, `{Project}TextField`, `{Project}Snackbar`, `{Project}BottomSheet`)
- No raw Flutter widgets when a project UI equivalent exists:
  - `Text` -> `{Project}Text`
  - `ElevatedButton` -> `{Project}Button.primary`
  - `TextField` -> `{Project}TextField`
  - `SnackBar` -> `{Project}Snackbar`
  - `showModalBottomSheet` -> `{Project}BottomSheet.show`
- No direct imports of `flutter_components_library` in feature code
- All colors use `{Project}Colors.*`
- No inline `Color(0xFF...)` values
- No `Colors.*` from Flutter (except `Colors.transparent`)

### Internationalization Requirements

All user-facing text uses translation keys with `.i18n` extension. No hardcoded strings in any language.

```dart
// Correct
{Project}Text.heading('charging_title'.i18n)
{Project}Button.primary(text: 'continue_button'.i18n, onPressed: () {})
{Project}Text.body('hello_user'.i18n.fill([userName]))
{Project}Snackbar.showError(context, 'connection_error'.i18n)

// Incorrect
{Project}Text.heading('Charging Stations')
{Project}Button.primary(text: 'Continue', onPressed: () {})
```

Only non-translatable content may remain hardcoded: brand names, country codes, currency codes, technical identifiers.

### Spacing and Dimensions

- Consistent spacing values are used throughout the app
- Repeated padding/margin values are defined as constants
- `SizedBox` is preferred over `Container` for whitespace
