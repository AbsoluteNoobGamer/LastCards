# Flutter Feature-First Architecture Guide

This guide defines how to add and evolve features in this project without harming maintainability.

## 1) Architecture Overview

Use **feature-first + clean architecture**:

- `presentation` -> depends on `domain`
- `data` -> depends on `domain`
- `domain` -> depends on nothing (pure Dart rules)

Dependency flow:

`presentation -> domain <- data`

Rules:
- UI never talks directly to API/database.
- Domain never imports Flutter.
- Data implements domain contracts, not the other way around.

---

## 2) Folder Responsibilities

## `lib/core/`
Global, cross-cutting concerns.

Put here:
- theme (`app_theme.dart`, colors, typography)
- infrastructure (`network`, serialization helpers, error handling)
- global providers/utilities used across many features

Do not put:
- feature-specific screens/use cases/entities

Good:
- `lib/core/network/websocket_client.dart`
- `lib/core/theme/app_theme.dart`

Bad:
- `lib/core/profile/profile_screen.dart`

## `lib/shared/` (recommended)
Reusable, non-feature-owned components.

Put here:
- reusable widgets (`AppButton`, `AppTextField`)
- common extensions/helpers used across features

Do not put:
- business rules
- single-feature-only widgets

## `lib/features/<feature_name>/`
Everything a feature needs, grouped together.

### `presentation/`
UI + UI state orchestration.

Put here:
- screens/pages
- widgets
- controllers/notifiers/providers
- input validation for UI forms

Do not put:
- HTTP/WebSocket/DB calls
- core business rules

### `domain/`
Business logic contracts and intent.

Put here:
- entities
- repository abstractions/contracts
- use cases

Do not put:
- Flutter imports
- JSON DTOs

### `data/`
External data wiring and mapping.

Put here:
- repository implementations
- datasources (remote/local)
- models/DTOs
- mappers

Do not put:
- widget code
- navigation logic

---

## 3) Example Folder Tree

```text
lib/
  app/
    app.dart
    router/
      app_routes.dart
    di/
      providers.dart

  core/
    network/
    theme/
    errors/
    utils/

  shared/
    widgets/
    extensions/

  features/
    sample_feature/
      domain/
        entities/
          sample_entity.dart
        repositories/
          sample_repository.dart
        usecases/
          get_sample_usecase.dart
      data/
        datasources/
          sample_remote_datasource.dart
          sample_local_datasource.dart
        models/
          sample_model.dart
        repositories/
          sample_repository_impl.dart
        mappers/
          sample_mapper.dart
      presentation/
        screens/
          sample_screen.dart
        widgets/
          sample_card.dart
        controllers/
          sample_notifier.dart
```

---

## 4) Feature Creation Checklist

1. **Create feature folder**
   - `lib/features/<new_feature>/domain|data|presentation`

2. **Add domain layer**
   - Entity: `domain/entities/<feature>.dart`
   - Repository contract: `domain/repositories/<feature>_repository.dart`
   - Use cases: `domain/usecases/<action>_<feature>_usecase.dart`

3. **Add data layer**
   - DTO/model: `data/models/<feature>_model.dart`
   - Datasource(s): `data/datasources/<feature>_remote_datasource.dart`
   - Repo impl: `data/repositories/<feature>_repository_impl.dart`
   - Mapper(s): `data/mappers/<feature>_mapper.dart`

4. **Add presentation layer**
   - Screen: `presentation/screens/<feature>_screen.dart`
   - State: `presentation/controllers/<feature>_notifier.dart`
   - Reusable widgets under `presentation/widgets/`

5. **Register DI**
   - Register providers and dependencies in `app/di/providers.dart` or feature provider file.

6. **Add routes/navigation**
   - Add route key in `app/router/app_routes.dart`
   - Map route to screen builder

7. **Write tests**
   - Unit tests for use cases/repo/mappers
   - Widget tests for screen and widgets
   - Integration flow for key user path

Common mistakes:
- skipping repository abstraction
- putting DTO in domain
- calling datasource directly from UI
- giant screen files with mixed business logic

---

## 5) Testing Structure

```text
test/
  unit/
    features/
      sample_feature/
        domain/usecases/
          get_sample_usecase_test.dart
        data/repositories/
          sample_repository_impl_test.dart
        data/mappers/
          sample_mapper_test.dart

  widget/
    features/
      sample_feature/
        presentation/screens/
          sample_screen_test.dart
        presentation/widgets/
          sample_card_test.dart

  integration/
    features/
      sample_feature/
        sample_feature_flow_test.dart
```

Test boundaries:
- **Domain unit tests:** pure business behavior, no Flutter bindings.
- **Data unit tests:** repo behavior with mocked datasource.
- **State tests:** notifier/provider transitions and side effects.
- **Widget tests:** rendering + user interaction + state output.
- **Integration tests:** end-to-end critical flows.

---

## 6) Naming Conventions

| Type | Convention | Example |
|---|---|---|
| File | `snake_case.dart` | `offline_game_engine.dart` |
| Class | `PascalCase` | `OfflineGameState` |
| Screen Widget | `<Feature>Screen` | `LeaderboardScreen` |
| Reusable Widget | `<Role>Widget` or `<Feature><Role>` | `StatusBarWidget` |
| Repository Contract | `<Feature>Repository` | `ProfileRepository` |
| Repository Impl | `<Feature>RepositoryImpl` | `ProfileRepositoryImpl` |
| Use case | `<Action><Feature>Usecase` | `GetProfileUsecase` |
| Provider/Notifier file | `<feature>_provider.dart`, `<feature>_notifier.dart` | `game_provider.dart` |
| Test file | `<source_name>_test.dart` | `offline_game_engine_test.dart` |

Recommended:
- avoid temporary prefixes (`demo_`, `temp_`, `new_`)
- avoid ambiguous names (`utils.dart`, `helpers.dart`)
- prefer intent-driven names (`validate_end_turn_usecase.dart`)

---

## 7) UI Structure Guidelines

For scalable UI:

- Keep screen files focused on layout + orchestration.
- Extract widgets when:
  - block repeats
  - block exceeds ~60-100 lines
  - block has independent test value
- Use **smart/container** widgets for state wiring.
- Use **dumb/presentational** widgets for rendering only.
- Keep business rules out of widgets; call use cases/notifiers.

Theme and constants:
- Global theme/colors/typography in `core/theme/`.
- Feature-only constants in feature presentation folder.
- Avoid hardcoded styles/colors in many places.

---

## 8) Design Principles to Enforce

- **SOLID**
  - SRP: one reason to change per class/file
  - DIP: depend on abstractions (domain contracts)
- **DRY**
  - extract repeated UI/components/mappers
- **Separation of concerns**
  - UI != business logic != persistence
- **Feature isolation**
  - feature can evolve with minimal cross-feature impact
- **No circular dependencies**
  - never import presentation into data/domain
- **No direct data access from UI**
  - always through notifier/use case/repository contract

---

## 9) Common Anti-Patterns to Avoid

- Putting HTTP/WebSocket calls inside widgets.
- Storing JSON DTOs as domain entities.
- Massive god screens/controllers with mixed concerns.
- Feature code under `core/` just for convenience.
- Overusing export barrels that hide ownership.
- Introducing compatibility shims permanently.
- Writing tests only for happy paths.

---

## 10) Practical “Definition of Done” for New Features

A feature is considered done when:
- folder/layers follow feature-first structure
- domain contracts + use cases exist
- data implementation is behind interfaces
- UI uses providers/notifiers, not datasources directly
- route + DI wiring added
- unit + widget tests exist for critical behavior
- naming follows conventions in this guide

