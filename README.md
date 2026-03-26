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

### Firebase (Auth, Firestore, Storage)

The app is wired to Firebase project **`lastcards-d4396`** (see `lib/firebase_options.dart`). For leaderboards, profiles, and ranked stats you must:

1. In [Firebase Console](https://console.firebase.google.com/) for that project, enable **Authentication** (e.g. Google / anonymous) as needed.
2. Create a **Cloud Firestore** database (Native mode). If Firestore is not created, the client logs `NOT_FOUND` (“database (default) does not exist”) and realtime features will not work.
3. Enable **Firebase Storage** if you use avatar uploads from the profile screen.

### CI

GitHub Actions runs `flutter analyze` and `flutter test` on pushes and pull requests to `main` or `master` (see `.github/workflows/flutter_ci.yml`).

## Flutter resources

- [Flutter documentation](https://docs.flutter.dev/)
