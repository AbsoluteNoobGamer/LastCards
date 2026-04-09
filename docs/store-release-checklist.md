# Store release checklist (Google Play & App Store)

Use this when preparing production builds for **Last Cards** (`com.lastcards.app`).

## Already in the repo

- Android release signing is wired in `android/app/build.gradle.kts` via `key.properties`.
- App version: `pubspec.yaml` → `version: x.y.z+build` (build number must increase per upload).
- iOS `PrivacyInfo.xcprivacy`, camera/photo usage strings, Sign in with Apple entitlement (`Runner/Runner.entitlements`).
- Firebase options are generated in `lib/firebase_options.dart`; `google-services.json` / `GoogleService-Info.plist` are gitignored — add them locally or in CI from Firebase.

## Android (Google Play)

1. **Play Console** — Create the app with package name `com.lastcards.app`.
2. **Upload key** — Copy `android/key.properties.example` to `android/key.properties`, point `storeFile` at your keystore, set passwords and alias. Enable **Play App Signing** in Play Console (recommended).
3. **Build** — From project root: `flutter build appbundle`.
4. **Firebase** — Ensure the Android app in Firebase matches the package name; download `google-services.json` into `android/app/`.
5. **Data safety** — Complete the Data safety form (Firebase Auth, Firestore, Storage, account data, etc.).
6. **Listings** — Screenshots, feature graphic, short/full description, privacy policy URL.

## iOS (App Store)

1. **Apple Developer** — App ID `com.lastcards.app`, enable **Sign In with Apple** capability (matches `Runner/Runner.entitlements`).
2. **Certificates & provisioning** — Xcode: select your team, signing for Release; archive for distribution.
3. **Firebase** — Download `GoogleService-Info.plist` into `ios/Runner/` for release builds.
4. **Firebase Auth: Apple** — In Firebase Console → Authentication → Sign-in method → Apple: add your Apple Developer Team ID, Services ID, Key ID, and private key (`.p8`) per Firebase docs. Without this, Sign in with Apple in the app will fail after Apple’s login sheet.
5. **App Store Connect** — Privacy nutrition labels, export compliance (encryption), screenshots, support URL, privacy policy URL.
6. **Build** — e.g. `flutter build ipa` or archive in Xcode; distribute via TestFlight before submitting for review.

## Cross-cutting

- **Backend** — Production WebSocket/API URLs and Firestore rules reviewed for production traffic.
- **Policies** — Public privacy policy (and terms if applicable) that match actual data practices and store questionnaires.
