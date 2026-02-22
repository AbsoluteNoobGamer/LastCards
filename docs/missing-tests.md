# Missing Test Coverage Review

This document captures the biggest test gaps after the refactor and renaming pass.

## Current Coverage Snapshot

Existing tests cover:
- Core offline gameplay engine rules in depth (`test/engine_test.dart`)
- Engine-level e2e flow (`test/e2e_gameplay_test.dart`)
- Integrated gameplay log rendering (`test/integrated_game_log_test.dart`)
- Audio service behavior and integration (`test/audio_service_test.dart`, `test/swoosh_audio_integration_test.dart`)

Largest uncovered areas:
- App shell and routing
- Riverpod provider behavior (`game_provider`, `connection_provider`, event wiring)
- WebSocket client and game event handler
- Most presentation screens/widgets outside integrated log
- Settings/AI selector state and interaction behavior

## High-Priority Missing Tests

## 1) Networking + State Sync (Unit)

### `lib/core/network/websocket_client.dart`
- Connect success sets `connected` state.
- Failed connection transitions to reconnecting/disconnected path.
- Exponential backoff retry behavior (attempt count and stop at max retries).
- `send()` no-op when disconnected.
- `disconnect()` marks manual disconnect and stops reconnect attempts.

### `lib/core/network/game_event_handler.dart`
- Parses incoming raw JSON and emits typed events.
- Filters (`stateSnapshots`, `cardPlays`, `cardDraws`, etc.) only emit matching events.
- Outgoing helper methods send correct action payloads.

### `lib/core/providers/game_provider.dart`
- Snapshot event replaces full state.
- Card played event updates discard top/second.
- Draw event clamps draw pile count to non-negative.
- Turn change and penalty events update only intended fields.
- Notifier actions (`playCards`, `drawCard`, `declareJoker`) call event handler with correct args.

### `lib/core/providers/connection_provider.dart`
- Emits initial connection state immediately.
- Propagates connection state changes from `WebSocketClient`.
- Proper cleanup on dispose (listener removal + stream close).

## 2) App Bootstrapping + Routing (Widget)

### `lib/app/app.dart` and `lib/app/router/app_routes.dart`
- App starts on `AppRoutes.start`.
- Route map resolves `start`, `lobby`, and `game` to expected screen types.
- Unknown route behavior (if intentionally unsupported, assert current behavior).

## 3) Gameplay Screen Behavior (Widget)

### `lib/features/gameplay/presentation/screens/table_screen.dart`
- Offline mode renders expected structure with no live state.
- Turn timer expiry path:
  - Ends turn when no queen lock.
  - Forces draw when queen lock is active.
- End turn button enabled/disabled behavior follows `validateEndTurn`.
- Offline path for draw/play actions updates visible UI state.
- Win dialog appears when a player empties hand.

## Medium-Priority Missing Tests

## 4) Start/Practice/Lobby Flow (Widget)

### `lib/features/start/presentation/screens/start_screen.dart`
- Primary actions navigate/open expected targets:
  - AI selector bottom sheet opens from "Play with AI" and "Practice Mode".
  - "Play Online" transitions to lobby.
- Secondary actions open settings/rules/leaderboard correctly.

### `lib/features/start/presentation/widgets/ai_selector_modal.dart`
- Selection returns expected player count.
- Cancel/close behavior does not trigger navigation callback.

### `lib/features/practice/presentation/screens/offline_practice_screen.dart`
- Renders "No leaderboard impact" badge.
- Back button pops route.
- Embeds gameplay table with selected player count.

### `lib/features/lobby/presentation/screens/lobby_screen.dart`
- Join/Create actions navigate to game route.
- Ready toggle state + button label/color switch.
- Inputs accept/edit expected values.

## 5) Settings Persistence (Unit + Widget)

### `lib/features/settings/presentation/widgets/settings_modal.dart`
- `SettingsNotifier` loads defaults when prefs are absent.
- Each update method persists to `SharedPreferences`.
- Toggle actions update state and persist bool values.
- "Mute All Audio" switch calls `audioService.toggleMute()`.

## 6) Gameplay Widgets (Widget)

Add focused rendering/interaction tests for:
- `card_widget.dart` (selection, tap, visual state)
- `draw_pile_widget.dart` (enabled/disabled tap behavior)
- `status_bar_widget.dart` (timer and end-turn affordance)
- `hud_overlay_widget.dart` (active suit/penalty/connection indicators)
- `player_hand_widget.dart` and `player_zone_widget.dart` (hand display + states)
- `turn_indicator_overlay.dart` (directional indicator updates)

## Lower-Priority / Regression Safety

## 7) Additional Screens (Widget)
- `rules_screen.dart`: renders content sections and scroll behavior.
- `leaderboard_screen.dart`: empty/loading/content states.

## 8) Golden Tests (Optional)
- Stabilize key UI snapshots for:
  - Start screen hero section
  - Table HUD/status bar
  - Card visuals (front/back/joker)

## Suggested Execution Order

1. Networking + providers (highest regression risk).
2. App routing smoke tests.
3. Table screen behavior-critical widget tests.
4. Settings + start/practice/lobby interaction tests.
5. Remaining gameplay widget and informational screen tests.

## Minimal Target to Reach "Production Baseline"

If time is limited, implement this minimum first:
- 8-12 tests across `websocket_client`, `game_event_handler`, `game_provider`, `connection_provider`
- 3-4 app routing/startup widget tests
- 5-7 table screen behavior tests (timer, end-turn, offline play/draw, win dialog)
- 3-5 settings notifier/persistence tests

