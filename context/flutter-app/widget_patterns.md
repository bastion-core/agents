# UI Component Patterns

This document describes the UI component architecture, discovery process, component categories, resolution flow, and usage rules for Flutter applications using a project-level UI abstraction layer.

## Component Architecture

The project uses a UI abstraction layer that wraps an underlying component library (e.g., a private git package or design system library) with project-prefixed widgets. Feature code interacts only with these project-level wrappers, never with the underlying library directly.

The abstraction layer typically lives in `common/ui/` and provides named factory constructors for common component variants (e.g., `{Project}Button.primary()`, `{Project}Text.title()`).

### Discovery Rule (Mandatory First Step)

Before writing any UI code, the project's UI abstraction layer must be discovered:

1. **Search for a shared UI folder**: look in `common/ui/`, `common/presentation/widgets/`, `shared/widgets/`, `core/design_system/`
2. **Identify wrapper components**: look for project-prefixed widgets (e.g., `{Project}Button`, `{Project}Text`, `{Project}TextField`)
3. **Identify the underlying library**: check `pubspec.yaml` for UI packages (e.g., a private git package, material_design, or a design system library)
4. **Identify color constants**: look for a centralized colors file (e.g., `{project}_colors.dart`, `app_colors.dart`, `theme_colors.dart`)
5. **Identify icon pack**: look for icon packages in `pubspec.yaml` (e.g., `phosphor_flutter`, `font_awesome_flutter`, `material_icons`)

The discovered components are the ones to use -- raw Flutter widgets are not used if an abstraction exists.

## Component Categories

A well-structured project has these component categories. During discovery, the project's components map to these categories:

| Category | Purpose | Example Components |
|----------|---------|-------------------|
| **Buttons** | User actions | `{Project}Button.primary()`, `.secondary()`, `.text()`, `.small()` |
| **Typography** | Text display | `{Project}Text.title()`, `.body()`, `.caption()`, `.label()` |
| **Inputs** | Data entry | `{Project}TextField()`, `.password()`, `.email()`, `.phone()` |
| **Feedback** | Notifications | `{Project}Snackbar.showSuccess()`, `.showError()`, `.showInfo()` |
| **Overlays** | Modal content | `{Project}BottomSheet.show()`, `{Project}Dialog()` |
| **Colors** | Centralized palette | `{Project}Colors.primary`, `.background`, `.error`, `.border` |
| **Icons** | Iconography | Icon pack from `pubspec.yaml` (PhosphorIcons, FontAwesome, etc.) |

## Component Resolution Flow

When a UI component is needed for a feature, the following resolution flow applies:

```
Need a UI component (e.g., a date picker)
    |
    +-- Does the project's UI abstraction have it?
    |   +-- YES -> Use it directly (e.g., {Project}DatePicker)
    |
    +-- Does the underlying library have a suitable component?
    |   +-- YES -> Create a customization wrapper:
    |           1. Wrap the library component in a project-prefixed widget
    |           2. Place it in common/ui/ or common/presentation/widgets/
    |           3. Apply project theme defaults (colors, typography, spacing)
    |           4. Expose named constructors for common variants
    |           5. Document the new component in the team's design system
    |
    +-- Neither has it?
        +-- Build from raw Flutter widgets:
            1. Create a reusable widget in common/ui/ or common/presentation/widgets/
            2. Use the project's color constants and typography
            3. Follow existing naming conventions ({Project}ComponentName)
            4. Add named constructors for variants
```

Raw library components are never used directly in feature code. They are always wrapped first in the project's UI abstraction layer.

## Component Templates

### Reference Example (Voltop Charging App)

The following is a reference example of a well-structured UI abstraction. Individual projects may use different names, variants, and colors. This serves as a model for understanding what a good UI layer looks like.

**Location**: `common/ui/voltop_ui.dart`
**Underlying Library**: `flutter_components_library` (private git package)
**Pattern**: Named factory constructors for variants

| Component | Variants |
|-----------|----------|
| `VoltopButton` | `.primary()`, `.secondary()`, `.neutral()`, `.text()`, `.small()` |
| `VoltopText` | `.display()`, `.title()`, `.subtitle()`, `.heading()`, `.body()`, `.secondary()`, `.caption()`, `.label()`, `.hint()` |
| `VoltopTextField` | `()`, `.phone()`, `.password()`, `.pin()`, `.otp()`, `.email()` |
| `VoltopPhoneField` | `()`, `.latinAmerica()` |
| `VoltopSnackbar` | `.showSuccess()`, `.showError()`, `.showInfo()`, `.showWelcome()` |
| `VoltopBottomSheet` | `.show()` + `VoltopBottomSheetContainer` + `VoltopBottomSheetHeader` |
| `VoltopColors` | `.background`, `.surface`, `.primary`, `.secondary`, `.error`, `.warning`, `.success`, `.border`, `.gradientPrimary` |
| Icons | `PhosphorIcon(PhosphorIcons.iconName())` |

### Usage Examples

```dart
// Buttons
{Project}Button.primary(text: 'continue_button'.i18n, onPressed: () {})
{Project}Button.secondary(text: 'cancel_button'.i18n, onPressed: () {})

// Typography
{Project}Text.heading('charging_title'.i18n)
{Project}Text.body('description'.i18n)
{Project}Text.caption('hint_text'.i18n)

// Inputs
{Project}TextField.phone(controller: phoneController)
{Project}TextField.password(controller: passwordController)
{Project}TextField.email(controller: emailController)

// Feedback
{Project}Snackbar.showSuccess(context, 'success_message'.i18n)
{Project}Snackbar.showError(context, 'error_message'.i18n)
{Project}Snackbar.showInfo(context, 'info_message'.i18n)

// Overlays
{Project}BottomSheet.show(context: context, child: MyWidget())

// Colors
Container(color: {Project}Colors.primary)
Container(color: {Project}Colors.background)
Container(color: {Project}Colors.surface)

// Icons (using project's icon pack, e.g., phosphor_flutter)
PhosphorIcon(PhosphorIcons.iconName())
```

### Raw Flutter Widgets Allowed For

Layout and structural widgets that have no project UI equivalent are used directly:

- **Layout**: `Row`, `Column`, `Stack`, `Expanded`, `Container`, `Padding`, `SizedBox`
- **Structural**: `Scaffold`, `AppBar`, `SafeArea`, `CustomScrollView`, `ListView`
- **Navigation**: `Navigator`, `GoRouter`
- **Special-purpose**: Widgets with no project UI equivalent

### Responsive Design

Native Flutter responsive design is used instead of third-party responsive utility packages:

- `MediaQuery` for screen dimensions
- `LayoutBuilder` for parent constraints
- `Flex` widgets for flexible layouts

## Rules and Constraints

1. The project's UI abstraction components are used instead of raw Flutter widgets when an equivalent exists
2. The project's centralized color constants are used instead of raw `Color` values or `Colors.*` from Flutter
3. The project's icon pack (discovered from `pubspec.yaml`) is used for all icons
4. The underlying UI library is not imported directly in feature code -- the abstraction layer is the import target
5. Responsive utility packages like `ScreenUtil` are not used -- native Flutter responsive design (`MediaQuery`, `LayoutBuilder`, `Flex`) is sufficient
6. New colors are not added outside the project's centralized colors file
7. Raw library components are not used in feature code without wrapping them first in the UI abstraction
8. When a needed component does not exist in the abstraction layer, it is created following the Component Resolution Flow above before being used in feature code
9. All user-facing text uses translation keys with `.i18n` extension -- no hardcoded strings in any language
10. `SizedBox` is preferred over `Container` for whitespace/spacing
