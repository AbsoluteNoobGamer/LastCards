import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'logger.dart';

/// Minimal Firestore REST client authenticated via a Google service account.
///
/// Reads credentials from the [_credentialsJson] environment variable
/// (`GOOGLE_CREDENTIALS_JSON`), which should contain the full JSON of a
/// Firebase/GCP service account key file.
///
/// If credentials are absent, all writes are silently skipped.
///
/// Shared by [TrophyRecorder]/[MatchupRecorder] (ranked stats, leaderboards,
/// head-to-head) and [WalletService] (coin wallet) — every server-side
/// Firestore write in this codebase goes through this one client.
class FirestoreClient {
  FirestoreClient._();
  static final FirestoreClient instance = FirestoreClient._();

  final _log = Logger('FirestoreClient');

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scope = 'https://www.googleapis.com/auth/datastore';

  String? _projectId;
  String? _clientEmail;
  String? _privateKeyPem;

  String? _cachedToken;
  DateTime? _tokenExpiry;

  bool _initCalled = false;

  /// Initialises credentials from the GOOGLE_CREDENTIALS_JSON env var.
  void init() {
    if (_initCalled) return;
    _initCalled = true;
    final raw = Platform.environment['GOOGLE_CREDENTIALS_JSON'];
    if (raw == null || raw.isEmpty) {
      _log.info(
          'GOOGLE_CREDENTIALS_JSON not set — Firestore writes are disabled.');
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _projectId = json['project_id'] as String?;
      _clientEmail = json['client_email'] as String?;
      _privateKeyPem = json['private_key'] as String?;
      _log.info('Firestore credentials loaded for project "$_projectId".');
    } catch (e) {
      _log.error('Failed to parse GOOGLE_CREDENTIALS_JSON: $e');
    }
  }

  bool get _configured =>
      _projectId != null && _clientEmail != null && _privateKeyPem != null;

  /// Whether [GOOGLE_CREDENTIALS_JSON] was parsed successfully.
  bool get isFirestoreConfigured => _configured;

  /// Firebase/GCP project id from credentials, or null if not configured.
  String? get firestoreProjectId => _projectId;

  /// Returns a valid OAuth2 access token, refreshing if needed.
  Future<String?> _getAccessToken() async {
    if (!_configured) return null;

    // Return cached token if still valid with a 60-second buffer.
    final expiry = _tokenExpiry;
    if (_cachedToken != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 60)))) {
      return _cachedToken;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = JWT(
        {
          'iss': _clientEmail,
          'scope': _scope,
          'aud': _tokenUrl,
          'iat': now,
          'exp': now + 3600,
        },
        issuer: _clientEmail,
      );
      // Sign with the service account RSA private key (RS256).
      final signed = payload.sign(
        RSAPrivateKey(_privateKeyPem!),
        algorithm: JWTAlgorithm.RS256,
      );

      final response = await _sendWithRetry(() => http.post(
            Uri.parse(_tokenUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              'assertion': signed,
            },
          ));

      if (response.statusCode != 200) {
        _log.error(
            'Failed to obtain access token: ${response.statusCode} ${response.body}');
        return null;
      }
      final tokenJson = jsonDecode(response.body) as Map<String, dynamic>;
      _cachedToken = tokenJson['access_token'] as String?;
      final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      return _cachedToken;
    } catch (e) {
      _log.error('Error obtaining access token: $e');
      return null;
    }
  }

  /// Retries [send] a couple of times on transient connection-level failures
  /// (TLS handshake dropped, connection closed before headers) — seen
  /// intermittently against Google's own endpoints from this host. Callers
  /// don't queue or reconcile a failed write afterward, so without this a
  /// single network blip silently drops a ranked-stat/trophy/wallet update.
  /// Non-transient failures (bad status codes, JSON errors) are unaffected —
  /// they're handled by the caller's own try/catch after this rethrows.
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() send,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      try {
        return await send();
      } on http.ClientException {
        if (attempt >= maxAttempts) rethrow;
      } on HandshakeException {
        if (attempt >= maxAttempts) rethrow;
      } on SocketException {
        if (attempt >= maxAttempts) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 250 * attempt));
    }
  }

  /// Atomically updates a Firestore document with multiple field increments
  /// and string overwrites in a single commit.
  ///
  /// If the document does not exist it is created with [defaultFields] as
  /// baseline values, then the [increments] are applied on top via field
  /// transforms. If the document already exists, only the increments and
  /// [stringFields] are applied.
  ///
  /// This avoids the race condition of multiple parallel calls each trying to
  /// create the same document, and avoids double-counting because default
  /// values do NOT include the deltas.
  /// Returns `true` if the commit succeeded, `false` if skipped (no credentials),
  /// auth failed, or Firestore returned an error.
  Future<bool> atomicUpdate({
    required String collection,
    required String docId,
    required Map<String, int> increments,
    Map<String, dynamic> defaultFields = const {},
    Map<String, String> stringFields = const {},
  }) async {
    final token = await _getAccessToken();
    if (token == null) return false;

    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents:commit');

    final docPath =
        'projects/$_projectId/databases/(default)/documents/$collection/$docId';

    // Build field transforms for atomic increments.
    final transforms = <Map<String, dynamic>>[
      for (final e in increments.entries)
        {
          'fieldPath': e.key,
          'increment': {'integerValue': '${e.value}'},
        },
    ];

    // Merge all baseline + string fields for the conditional create.
    final allDefaults = <String, dynamic>{...defaultFields, ...stringFields};

    final body = jsonEncode({
      'writes': [
        // Conditional create: only applies when the doc does NOT exist.
        // Sets baseline values (without deltas) so increments work correctly.
        {
          'updateMask': {
            'fieldPaths': allDefaults.keys.toList(),
          },
          'update': {
            'name': docPath,
            'fields': {
              for (final e in allDefaults.entries)
                e.key: _firestoreValue(e.value),
            },
          },
          'currentDocument': {'exists': false},
        },
        // Field transforms (increments) — always applied whether the doc was
        // just created or already existed.
        {
          'transform': {
            'document': docPath,
            'fieldTransforms': transforms,
          },
        },
        // Overwrite string fields (e.g. displayName) on every update so they
        // stay current even for existing documents.
        if (stringFields.isNotEmpty)
          {
            'updateMask': {
              'fieldPaths': stringFields.keys.toList(),
            },
            'update': {
              'name': docPath,
              'fields': {
                for (final e in stringFields.entries)
                  e.key: _firestoreValue(e.value),
              },
            },
          },
      ],
    });

    try {
      final response = await _sendWithRetry(() => http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          ));
      if (response.statusCode == 200) return true;
      // Conditional create fails when the doc already exists. Firestore may
      // return 400 or 409 (ALREADY_EXISTS). Re-send with only the transforms +
      // string overwrites.
      if ((response.statusCode == 400 || response.statusCode == 409) &&
          response.body.contains('ALREADY_EXISTS')) {
        return _updateExisting(
          token: token,
          docPath: docPath,
          transforms: transforms,
          stringFields: stringFields,
        );
      }
      _log.error(
          'Firestore atomicUpdate failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      _log.error('Firestore atomicUpdate error: $e');
      return false;
    }
  }

  /// Applies increments and string overwrites to an already-existing document.
  Future<bool> _updateExisting({
    required String token,
    required String docPath,
    required List<Map<String, dynamic>> transforms,
    Map<String, String> stringFields = const {},
  }) async {
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents:commit');

    final body = jsonEncode({
      'writes': [
        {
          'transform': {
            'document': docPath,
            'fieldTransforms': transforms,
          },
        },
        if (stringFields.isNotEmpty)
          {
            'updateMask': {
              'fieldPaths': stringFields.keys.toList(),
            },
            'update': {
              'name': docPath,
              'fields': {
                for (final e in stringFields.entries)
                  e.key: _firestoreValue(e.value),
              },
            },
          },
      ],
    });

    try {
      final response = await _sendWithRetry(() => http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          ));
      if (response.statusCode == 200) return true;
      _log.error(
          'Firestore _updateExisting failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      _log.error('Firestore _updateExisting error: $e');
      return false;
    }
  }

  /// Converts a Dart value to its Firestore REST representation.
  Map<String, dynamic> _firestoreValue(dynamic v) {
    if (v is String) return {'stringValue': v};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is List<String>) {
      return {
        'arrayValue': {
          'values': [for (final s in v) {'stringValue': s}],
        },
      };
    }
    return {'nullValue': null};
  }

  /// Reads a document and returns decoded field values, or null if missing.
  Future<Map<String, dynamic>?> getDocumentFields({
    required String collection,
    required String docId,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/$collection/$docId');

    try {
      final response = await _sendWithRetry(
          () => http.get(uri, headers: {'Authorization': 'Bearer $token'}));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        _log.error(
            'Firestore getDocumentFields failed (${response.statusCode}): ${response.body}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = json['fields'] as Map<String, dynamic>?;
      if (fields == null) return {};
      return {
        for (final e in fields.entries) e.key: _decodeFirestoreValue(e.value),
      };
    } catch (e) {
      _log.error('Firestore getDocumentFields error: $e');
      return null;
    }
  }

  dynamic _decodeFirestoreValue(Map<String, dynamic> v) {
    if (v.containsKey('stringValue')) return v['stringValue'] as String;
    if (v.containsKey('integerValue')) {
      return int.parse(v['integerValue'] as String);
    }
    if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
    if (v.containsKey('arrayValue')) {
      final values =
          (v['arrayValue'] as Map<String, dynamic>?)?['values'] as List?;
      if (values == null) return <String>[];
      return [
        for (final item in values)
          if (item is Map<String, dynamic> &&
              item.containsKey('stringValue'))
            item['stringValue'] as String,
      ];
    }
    return null;
  }

  /// PATCH [fields] onto [collection]/[docId]. Returns false when skipped/failed.
  Future<bool> setDocumentFields({
    required String collection,
    required String docId,
    required Map<String, dynamic> fields,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return false;

    final docPath =
        'projects/$_projectId/databases/(default)/documents/$collection/$docId';
    final query = fields.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeComponent(k)}')
        .join('&');
    final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/$docPath?$query');

    final body = jsonEncode({
      'fields': {
        for (final e in fields.entries) e.key: _firestoreValue(e.value),
      },
    });

    try {
      final response = await _sendWithRetry(() => http.patch(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          ));
      if (response.statusCode == 200) return true;
      _log.error(
          'Firestore setDocumentFields failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      _log.error('Firestore setDocumentFields error: $e');
      return false;
    }
  }
}
