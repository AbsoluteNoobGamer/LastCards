import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../firebase_options.dart';
import 'account_deletion_service.dart';
import 'firestore_profile_service.dart';

/// Result of a Google sign-in attempt.
sealed class GoogleSignInResult {
  const GoogleSignInResult();
  const factory GoogleSignInResult.success(UserCredential credential) =
      GoogleSignInSuccess;
  const factory GoogleSignInResult.cancelled() = GoogleSignInCancelled;
  const factory GoogleSignInResult.failure(String message) =
      GoogleSignInFailure;
}

class GoogleSignInSuccess extends GoogleSignInResult {
  final UserCredential credential;
  const GoogleSignInSuccess(this.credential);
}

class GoogleSignInCancelled extends GoogleSignInResult {
  const GoogleSignInCancelled();
}

class GoogleSignInFailure extends GoogleSignInResult {
  final String message;
  const GoogleSignInFailure(this.message);
}

/// Result of a Sign in with Apple attempt (iOS / macOS).
sealed class AppleSignInResult {
  const AppleSignInResult();
  const factory AppleSignInResult.success(UserCredential credential) =
      AppleSignInSuccess;
  const factory AppleSignInResult.cancelled() = AppleSignInCancelled;
  const factory AppleSignInResult.failure(String message) =
      AppleSignInFailure;
}

class AppleSignInSuccess extends AppleSignInResult {
  final UserCredential credential;
  const AppleSignInSuccess(this.credential);
}

class AppleSignInCancelled extends AppleSignInResult {
  const AppleSignInCancelled();
}

class AppleSignInFailure extends AppleSignInResult {
  final String message;
  const AppleSignInFailure(this.message);
}

/// Result of permanently deleting the signed-in Firebase account.
sealed class AccountDeletionResult {
  const AccountDeletionResult();
  const factory AccountDeletionResult.success() = AccountDeletionSuccess;
  const factory AccountDeletionResult.cancelled() = AccountDeletionCancelled;
  const factory AccountDeletionResult.failure(String message) =
      AccountDeletionFailure;
}

class AccountDeletionSuccess extends AccountDeletionResult {
  const AccountDeletionSuccess();
}

class AccountDeletionCancelled extends AccountDeletionResult {
  const AccountDeletionCancelled();
}

class AccountDeletionFailure extends AccountDeletionResult {
  final String message;
  const AccountDeletionFailure(this.message);
}

String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

bool _isApplePlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Display name from Apple given/family name (only sent on first authorization).
String? displayNameFromAppleNameParts({
  String? givenName,
  String? familyName,
}) {
  final given = givenName?.trim() ?? '';
  final family = familyName?.trim() ?? '';
  final name = [given, family].where((s) => s.isNotEmpty).join(' ');
  return name.isEmpty ? null : name;
}

/// Display name from Apple ID credential (only provided on first authorization).
String? displayNameFromAppleCredential(
  AuthorizationCredentialAppleID credential,
) =>
    displayNameFromAppleNameParts(
      givenName: credential.givenName,
      familyName: credential.familyName,
    );

String _firebaseAuthFailureMessage(
  FirebaseAuthException e, {
  required String providerLabel,
}) {
  switch (e.code) {
    case 'invalid-credential':
    case 'operation-not-allowed':
      if (providerLabel == 'Apple') {
        return 'Apple sign-in is not fully configured in Firebase. '
            'In Firebase Console → Authentication → Sign-in method, enable Apple '
            'and add your Apple Team ID, Services ID, Key ID, and .p8 private key.';
      }
      return 'Google sign-in is not enabled or misconfigured in Firebase.';
    default:
      return e.message ?? e.toString();
  }
}

/// Service wrapping Firebase Auth for persistent user identity.
///
/// Supports Google sign-in and anonymous sign-in. Both give a persistent
/// account: Google across devices, anonymous on the same device.
///
/// All accessors are resilient: if Firebase is not initialised (e.g. missing
/// google-services.json), every method degrades gracefully instead of throwing.
class AuthService {
  /// Production uses the default constructor; tests may pass [firebaseAuth].
  AuthService({FirebaseAuth? firebaseAuth}) : _firebaseAuth = firebaseAuth;

  final FirebaseAuth? _firebaseAuth;

  /// Lazily resolve [FirebaseAuth.instance] so that constructing an
  /// [AuthService] never throws, even when no Firebase app exists.
  FirebaseAuth? get _auth {
    if (_firebaseAuth != null) return _firebaseAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _auth?.currentUser;

  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream.empty();

  /// Get a fresh ID token to send to the game server.
  /// Returns null when Firebase is unavailable.
  Future<String?> getIdToken() async {
    try {
      return await _auth?.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  /// Sign in anonymously (guest). Creates a persistent UID on this device.
  Future<UserCredential?> signInAnonymously() async {
    return _auth?.signInAnonymously();
  }

  /// Web client ID (client_type: 3) from google-services.json. Required on Android.
  /// iOS client is 72j3iqllj78..., Web client is mu1oaec2glj5k8...
  static const String _webClientId =
      '941909760769-mu1oaec2glj5k8jl3vnlbvti5tjl5k54.apps.googleusercontent.com';

  /// Sign in with Google. Works on Android, iOS, and web.
  ///
  /// Returns [GoogleSignInResult.success] with credential on success.
  /// Returns [GoogleSignInResult.cancelled] when the user closes the picker.
  /// Returns [GoogleSignInResult.failure] with error message on technical failure.
  Future<GoogleSignInResult> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      return GoogleSignInResult.failure('Firebase is not initialized');
    }
    try {
      final iosClientId = DefaultFirebaseOptions.ios.iosClientId;
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: _webClientId,
        clientId: _isApplePlatform() ? iosClientId : null,
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        return GoogleSignInResult.cancelled();
      }
      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      final accessToken = authentication.accessToken;
      if (idToken == null) {
        return GoogleSignInResult.failure(
          'Could not get ID token. '
          'Use the Web client ID (not iOS/Android) from Firebase Console.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );
      final userCredential = await auth.signInWithCredential(credential);
      return GoogleSignInResult.success(userCredential);
    } on FirebaseAuthException catch (e, st) {
      if (kDebugMode) {
        debugPrint('Google sign-in failed: $e');
        debugPrint('StackTrace: $st');
      }
      return GoogleSignInResult.failure(
        _firebaseAuthFailureMessage(e, providerLabel: 'Google'),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Google sign-in failed: $e');
        debugPrint('StackTrace: $st');
      }
      return GoogleSignInResult.failure(e.toString());
    }
  }

  /// Sign in with Apple (required on iOS App Store when Google sign-in exists).
  ///
  /// Returns [AppleSignInResult.failure] on unsupported platforms (e.g. web,
  /// Android) or when Sign in with Apple is unavailable.
  Future<AppleSignInResult> signInWithApple() async {
    final auth = _auth;
    if (auth == null) {
      return AppleSignInResult.failure('Firebase is not initialized');
    }
    if (kIsWeb) {
      return AppleSignInResult.failure(
        'Sign in with Apple is not available on web. Use Google or guest.',
      );
    }
    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        return AppleSignInResult.failure(
          'Sign in with Apple is not available on this device.',
        );
      }
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final idToken = appleCredential.identityToken;
      if (idToken == null) {
        return AppleSignInResult.failure(
          'Could not get Apple identity token.',
        );
      }
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential = await auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      if (user != null) {
        final appleName = displayNameFromAppleCredential(appleCredential);
        final authName = user.displayName?.trim();
        if (appleName != null &&
            (authName == null || authName.isEmpty)) {
          await user.updateDisplayName(appleName);
          await user.reload();
        }
        await FirestoreProfileService().syncAuthToPublicProfileIfNeeded(user);
      }
      return AppleSignInResult.success(userCredential);
    } on FirebaseAuthException catch (e, st) {
      if (kDebugMode) {
        debugPrint('Apple sign-in failed: $e');
        debugPrint('StackTrace: $st');
      }
      return AppleSignInResult.failure(
        _firebaseAuthFailureMessage(e, providerLabel: 'Apple'),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Apple sign-in failed: $e');
        debugPrint('StackTrace: $st');
      }
      final message = e.toString();
      if (message.contains('canceled') || message.contains('cancelled')) {
        return const AppleSignInResult.cancelled();
      }
      return AppleSignInResult.failure(message);
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google sign-out may fail (e.g. user signed in anonymously); continue.
    }
    await _auth?.signOut();
  }

  /// Permanently deletes the signed-in account and associated app data.
  ///
  /// Re-authenticates when required (Google / Apple). Guest accounts skip reauth.
  Future<AccountDeletionResult> deleteAccount({
    AccountDeletionService? deletionService,
  }) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) {
      return const AccountDeletionResult.failure('Not signed in');
    }

    final reauth = await _reauthenticateForAccountDeletion(user);
    if (reauth == _ReauthOutcome.cancelled) {
      return const AccountDeletionResult.cancelled();
    }
    if (reauth == _ReauthOutcome.failed) {
      return const AccountDeletionResult.failure(
        'Could not verify your identity. Sign in again and retry.',
      );
    }

    final purge = deletionService ?? AccountDeletionService();
    try {
      await purge.purgeUserData(user.uid);
      await user.delete();
    } on FirebaseAuthException catch (e, st) {
      if (kDebugMode) {
        debugPrint('Account deletion failed: $e\n$st');
      }
      final msg = e.message ?? e.code;
      if (e.code == 'requires-recent-login') {
        return const AccountDeletionResult.failure(
          'For security, sign in again and retry account deletion.',
        );
      }
      return AccountDeletionResult.failure(msg);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Account deletion failed: $e\n$st');
      }
      return AccountDeletionResult.failure(e.toString());
    }

    await AccountDeletionService.clearLocalUserData();
    await signOut();
    return const AccountDeletionResult.success();
  }

  Future<_ReauthOutcome> _reauthenticateForAccountDeletion(User user) async {
    if (user.isAnonymous) return _ReauthOutcome.ok;

    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (providers.contains('google.com')) {
      return _reauthenticateWithGoogle(user);
    }
    if (providers.contains('apple.com')) {
      return _reauthenticateWithApple(user);
    }
    // Unknown provider — attempt delete without reauth (may fail with
    // requires-recent-login).
    return _ReauthOutcome.ok;
  }

  Future<_ReauthOutcome> _reauthenticateWithGoogle(User user) async {
    try {
      final iosClientId = DefaultFirebaseOptions.ios.iosClientId;
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: _webClientId,
        clientId: _isApplePlatform() ? iosClientId : null,
      );
      final account = await googleSignIn.signIn();
      if (account == null) return _ReauthOutcome.cancelled;
      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null) return _ReauthOutcome.failed;
      final credential = GoogleAuthProvider.credential(
        accessToken: authentication.accessToken,
        idToken: idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return _ReauthOutcome.ok;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Google reauth failed: $e\n$st');
      }
      return _ReauthOutcome.failed;
    }
  }

  Future<_ReauthOutcome> _reauthenticateWithApple(User user) async {
    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) return _ReauthOutcome.failed;
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final idToken = appleCredential.identityToken;
      if (idToken == null) return _ReauthOutcome.failed;
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      await user.reauthenticateWithCredential(oauthCredential);
      return _ReauthOutcome.ok;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Apple reauth failed: $e\n$st');
      }
      final message = e.toString();
      if (message.contains('canceled') || message.contains('cancelled')) {
        return _ReauthOutcome.cancelled;
      }
      return _ReauthOutcome.failed;
    }
  }
}

enum _ReauthOutcome { ok, cancelled, failed }
