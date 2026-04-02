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

**Ranked MMR and Firestore leaderboards:** the game server persists to Firestore (`ranked_stats`, mode leaderboards, online presence). Set the environment variable **`GOOGLE_CREDENTIALS_JSON`** to the **full JSON** of a Firebase [service account key](https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk) from the **same** project as the app (`projectId` in `lib/firebase_options.dart`, currently `lastcards-d4396`). If this variable is missing, players still see MMR **deltas** at the end of a match (computed in memory), but **profile and leaderboard** will not update because nothing is written to Firestore. On startup, the server logs whether Firestore persistence is enabled.

### Firebase (Auth, Firestore, Storage)

The app is wired to Firebase project **`lastcards-d4396`** (see `lib/firebase_options.dart`). For leaderboards, profiles, and ranked stats you must:

1. In [Firebase Console](https://console.firebase.google.com/) for that project, enable **Authentication** (e.g. Google / anonymous) as needed.
2. Create a **Cloud Firestore** database (Native mode). If Firestore is not created, the client logs `NOT_FOUND` (“database (default) does not exist”) and realtime features will not work.
3. Enable **Firebase Storage** if you use avatar uploads from the profile screen.

### CI

On pushes and pull requests to `main` or `master`, [`.github/workflows/flutter_ci.yml`](.github/workflows/flutter_ci.yml) runs:

- Firestore rules unit tests (`npm ci`, `npm run test:firestore-rules`)
- `flutter analyze` and `flutter test` for the app
- `dart analyze` for the `server/` package

## Flutter resources

- [Flutter documentation](https://docs.flutter.dev/)
