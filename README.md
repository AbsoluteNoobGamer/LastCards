# Last Cards

Premium competitive card game built with Flutter. Offline play uses the shared engine locally; online play uses the same rules on the server.

## Game rules

- [Rules by Mode](docs/rules-by-mode.md) — modes, special cards, and mode-specific behavior.

## Development

Prerequisites: Flutter **3.35.4** (see `pubspec.yaml`).

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Online server

The WebSocket client defaults to a production-style URL; override at build time with `--dart-define=WS_URL=wss://your-host/game` (see `lib/core/network/websocket_client.dart`).

The Dart server lives under `server/`. Deploy it so it matches the client’s shared engine after engine changes.

### CI

GitHub Actions runs `flutter analyze` and `flutter test` on pushes and pull requests to `main` or `master` (see `.github/workflows/flutter_ci.yml`).

## Flutter resources

- [Flutter documentation](https://docs.flutter.dev/)
