import 'package:firebase_auth/firebase_auth.dart';

/// Service wrapping Firebase Auth for persistent user identity.
///
/// Supports anonymous sign-in (zero user friction) for quickplay trophies.
/// Call [signInAnonymouslyIfNeeded] at app start to ensure a token is ready.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get a fresh ID token to send to the game server.
  Future<String?> getIdToken() async {
    return _auth.currentUser?.getIdToken();
  }

  /// Sign in anonymously if no user is signed in.
  /// Gives every device a persistent UID with zero user friction.
  Future<void> signInAnonymouslyIfNeeded() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  Future<UserCredential> signInAnonymously() async {
    return _auth.signInAnonymously();
  }

  Future<void> signOut() => _auth.signOut();
}
