import 'dart:convert';

import 'package:http/http.dart' as http;

/// Verifies Firebase ID tokens via the Identity Toolkit REST API.
///
/// Set [FIREBASE_API_KEY] (your Firebase Web API key) as an environment
/// variable when deploying. If unset, verification is skipped and returns null.
class FirebaseAuthVerifier {
  FirebaseAuthVerifier._({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Production singleton; uses a default [http.Client].
  static final FirebaseAuthVerifier instance = FirebaseAuthVerifier._();

  /// Verifier that uses [client] for HTTP (e.g. [MockClient] in tests).
  factory FirebaseAuthVerifier.withClient(http.Client client) =>
      FirebaseAuthVerifier._(httpClient: client);

  final http.Client _http;

  static const _lookupUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup';

  String? get _apiKey => _envApiKey;
  static String? _envApiKey;

  /// Set the API key (e.g. from Platform.environment['FIREBASE_API_KEY']).
  /// If not set, the verifier cannot validate tokens.
  static void setApiKey(String? key) {
    _envApiKey = key;
  }

  /// Verifies the [idToken] and returns the Firebase UID (sub/localId) if valid.
  ///
  /// Returns null if the API key is not configured, the token is invalid,
  /// or verification fails.
  Future<String?> verifyToken(String idToken) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }

    try {
      final response = await _http.post(
        Uri.parse('$_lookupUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final users = data['users'] as List<dynamic>?;
      if (users == null || users.isEmpty) {
        return null;
      }

      final user = users.first as Map<String, dynamic>;
      return user['localId'] as String?;
    } catch (_) {
      return null;
    }
  }
}
