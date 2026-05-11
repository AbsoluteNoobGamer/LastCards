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

## 4. Firestore `app_config` / `app_update` (after the new build is available)

The start screen uses **`appUpdateSuggestionProvider`** → **`fetchAppUpdateSuggestion()`** (`lib/core/services/app_update_suggestion.dart`). Players on an **older** build see the banner when:

`PackageInfo.buildNumber` &lt; `latestBuildAndroid` (Android) or `latestBuildIos` (iOS).

After the new binary is on the store (or when you want old clients to prompt):

- [ ] Open Firebase Console → Firestore → **`app_config`** → document **`app_update`** (create if missing).
- [ ] Set **`latestBuildAndroid`** and **`latestBuildIos`** to the **`+N`** of the build you just shipped (same as `release_info.dart` output).
- [ ] Optional: **`latestVersionName`** — any string for the banner (e.g. `1.0.0`).
- [ ] **iOS:** **`iosStoreUrl`** must be a non-empty App Store URL, or the banner is **not** shown on iPhone/iPad.
- [ ] **Android:** **`androidStoreUrl`** is optional (Play listing default exists in code).

## 5. Server (if applicable)

- [ ] Deploy the game server when you change WebSocket protocol or authoritative rules in `server/`.
- [ ] MMR / ranked persistence on the server does not require an app update unless the client must understand new fields.

## 6. Smoke-test

- [ ] Install an **old** build (or lower Firestore build numbers temporarily in a test project) and confirm the optional update banner appears on the start screen.
- [ ] Dismiss banner → cold-start → still behind store → banner should show again unless you add persistent dismiss logic later.

---

**Quick reference:** `dart run tool/release_info.dart` → update Firestore → done.
