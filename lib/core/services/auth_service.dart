import 'package:firebase_auth/firebase_auth.dart';

/// Service wrapping Firebase Auth for persistent user identity.
///
/// Supports anonymous sign-in (zero user friction) for quickplay trophies.
/// Call [signInAnonymouslyIfNeeded] at app start to ensure a token is ready.
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

  /// Sign in anonymously if no user is signed in.
  /// Gives every device a persistent UID with zero user friction.
  Future<void> signInAnonymouslyIfNeeded() async {
    final auth = _auth;
    if (auth == null || auth.currentUser != null) return;
    await auth.signInAnonymously();
  }

  Future<UserCredential?> signInAnonymously() async {
    return _auth?.signInAnonymously();
  }

  Future<void> signOut() async => _auth?.signOut();
}
