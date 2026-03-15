import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

/// Service wrapping Firebase Auth for persistent user identity.
///
/// Supports Google sign-in and anonymous sign-in. Both give a persistent
/// account: Google across devices, anonymous on the same device.
///
/// All accessors are resilient: if Firebase is not initialised (e.g. missing
/// google-services.json), every method degrades gracefully instead of throwing.
class AuthService {
  /// Lazily resolve [FirebaseAuth.instance] so that constructing an
  /// [AuthService] never throws, even when no Firebase app exists.
  FirebaseAuth? get _auth {
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
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: _webClientId,
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
    } catch (e, st) {
      debugPrint('Google sign-in failed: $e');
      debugPrint('StackTrace: $st');
      return GoogleSignInResult.failure(e.toString());
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth?.signOut();
  }
}
