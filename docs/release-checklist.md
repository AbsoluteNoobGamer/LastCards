# Release checklist (mobile)

Use this whenever you ship a **new build** to Google Play or the App Store. The marketing version (`1.0.0`) can stay the same; what matters for the optional in-app update banner is the **`+N` build number** in `pubspec.yaml` and matching Firestore fields.

## 1. Version & changelog

- [ ] Bump **`version` in `pubspec.yaml`**: increment **`+N`** for every store upload (e.g. `1.0.0+15` → `1.0.0+16`). You can keep `1.0.0` unchanged.
- [ ] Note what changed (for yourself or release notes in the store).

## 2. Print Firestore targets

From the repo root:

```bash
dart run tool/release_info.dart
```

Copy the suggested `latestBuildAndroid` / `latestBuildIos` values for step 4. The script reads `pubspec.yaml` and prints the exact integers to set after the build is live.

## 3. Build & upload

- [ ] `flutter build appbundle` / `flutter build ipa` (or your CI path).
- [ ] Upload to Play Console / App Store Connect and submit for review as you normally do.

## 4. Firestore `app_config` / `app_update` — **REQUIRED, do not skip this step**

The start screen uses **`appUpdateSuggestionProvider`** → **`fetchAppUpdateSuggestion()`** (`lib/core/services/app_update_suggestion.dart`). Players on an **older** build see the banner when:

`PackageInfo.buildNumber` &lt; `latestBuildAndroid` (Android) or `latestBuildIos` (iOS).

**This is not automatic.** Nothing about uploading a build to a store updates
Firestore — for ~2 months and ~39 builds this step was silently skipped
(hand-editing Firestore via Console, easy to forget), which meant **no user
ever got an update prompt at all**, regardless of how far behind they were.

Once the build is **actually approved and live** on the store (not just
uploaded — announcing it earlier sends players to a store page with nothing
new to install), run from `server/`:

```bash
GOOGLE_CREDENTIALS_JSON="$(cat /path/to/service-account.json)" \
  dart run bin/publish_release.dart
```

- [ ] Confirms the version from `pubspec.yaml`, shows what it's about to set, asks to confirm.
- [ ] Sets `latestBuildAndroid` / `latestBuildIos` / `latestVersionName`.
- [ ] Warns if `iosStoreUrl` isn't set — **that field has no code fallback**;
      if it's ever missing, the banner and forced-update gate silently never
      show on iOS, no matter how stale the build is. First time only (or to
      change the link), pass `--ios-store-url=https://apps.apple.com/app/id<your-app-id>`.
- [ ] The running server polls this doc every 10 minutes and pushes a
      notification to the `app_updates` topic when `latestVersionName` changes
      — no separate push step needed.

Manual Firebase Console editing (`app_config` → `app_update`) still works as a
fallback if the script can't run, but prefer the script — it's the only path
that reliably gets exercised.

## 5. Server (if applicable)

- [ ] Deploy the game server when you change WebSocket protocol or authoritative rules in `server/`.
- [ ] MMR / ranked persistence on the server does not require an app update unless the client must understand new fields.

## 6. Smoke-test

- [ ] Install an **old** build (or lower Firestore build numbers temporarily in a test project) and confirm the optional update banner appears on the start screen.
- [ ] Dismiss banner → cold-start → still behind store → banner should show again unless you add persistent dismiss logic later.

---

**Quick reference:** `dart run tool/release_info.dart` → update Firestore → done.
