import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'logger.dart';

// ── Rating constants ───────────────────────────────────────────────────────────

const _kWinDelta = 25;
const _kLossDelta = -15;
const _kLeaveDelta = -20;
const _kInitialRating = 1000;

// ── Firestore client ──────────────────────────────────────────────────────────

/// Minimal Firestore REST client authenticated via a Google service account.
///
/// Reads credentials from the [_credentialsJson] environment variable
/// (`GOOGLE_CREDENTIALS_JSON`), which should contain the full JSON of a
/// Firebase/GCP service account key file.
///
/// If credentials are absent, all writes are silently skipped.
class _FirestoreClient {
  _FirestoreClient._();
  static final _FirestoreClient instance = _FirestoreClient._();

  final _log = Logger('FirestoreClient');

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scope = 'https://www.googleapis.com/auth/datastore';

  String? _projectId;
  String? _clientEmail;
  String? _privateKeyPem;

  String? _cachedToken;
  DateTime? _tokenExpiry;

  /// Initialises credentials from the GOOGLE_CREDENTIALS_JSON env var.
  void init() {
    final raw = Platform.environment['GOOGLE_CREDENTIALS_JSON'];
    if (raw == null || raw.isEmpty) {
      _log.info(
          'GOOGLE_CREDENTIALS_JSON not set — ranked stat writes are disabled.');
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

      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signed,
        },
      );

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

  /// Atomically increments a numeric field in a Firestore document.
  ///
  /// If the document does not exist it is created with [defaultFields] merged
  /// into the update, so new users start at a sensible baseline.
  Future<void> incrementField({
    required String collection,
    required String docId,
    required String field,
    required int delta,
    Map<String, dynamic> defaultFields = const {},
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

    // Build a Firestore write with a field transform (increment).
    // We also set default values for missing fields using a merge patch.
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents:commit');

    // Compute the full document path.
    final docPath =
        'projects/$_projectId/databases/(default)/documents/$collection/$docId';

    // Build field transforms for atomic increment.
    final transforms = <Map<String, dynamic>>[
      {
        'fieldPath': field,
        'increment': {'integerValue': '$delta'},
      },
    ];

    final body = jsonEncode({
      'writes': [
        // Patch with defaults (creates the doc if missing, merges otherwise).
        {
          'updateMask': {
            'fieldPaths': defaultFields.keys.toList(),
          },
          'update': {
            'name': docPath,
            'fields': {
              for (final e in defaultFields.entries)
                e.key: _firestoreValue(e.value),
            },
          },
          'currentDocument': {'exists': false},
        },
        // Field transform (increment) — always applied.
        {
          'transform': {
            'document': docPath,
            'fieldTransforms': transforms,
          },
        },
      ],
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        // 400 with "document already exists" is OK — fall through to plain increment.
        if (response.statusCode == 400 &&
            response.body.contains('ALREADY_EXISTS')) {
          await _plainIncrement(
              token: token,
              docPath: docPath,
              field: field,
              delta: delta);
          return;
        }
        _log.error(
            'Firestore increment failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Firestore increment error: $e');
    }
  }

  /// Plain increment for an already-existing document.
  Future<void> _plainIncrement({
    required String token,
    required String docPath,
    required String field,
    required int delta,
  }) async {
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents:commit');

    final body = jsonEncode({
      'writes': [
        {
          'transform': {
            'document': docPath,
            'fieldTransforms': [
              {
                'fieldPath': field,
                'increment': {'integerValue': '$delta'},
              },
            ],
          },
        },
      ],
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        _log.error(
            'Firestore plain increment failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Firestore plain increment error: $e');
    }
  }

  /// Converts a Dart value to its Firestore REST representation.
  Map<String, dynamic> _firestoreValue(dynamic v) {
    if (v is String) return {'stringValue': v};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    return {'nullValue': null};
  }
}

// ── TrophyRecorder ────────────────────────────────────────────────────────────

/// Server-side ranked stat recorder.
///
/// On game end, call [recordRankedResult] to persist rating changes for all
/// players. On disconnect, call [recordLeavePenalty].
///
/// **Firestore schema** (`ranked_stats/{uid}`)
/// ```
/// rating:      int   (starts at 1000, clamped to 0)
/// wins:        int
/// losses:      int
/// leaves:      int
/// gamesPlayed: int
/// ```
///
/// **Environment setup**
/// Set `GOOGLE_CREDENTIALS_JSON` to the JSON content of a Firebase service
/// account key. Download it from Firebase Console → Project Settings →
/// Service Accounts → Generate New Private Key.
class TrophyRecorder {
  TrophyRecorder._() {
    _firestoreClient.init();
  }
  static final TrophyRecorder instance = TrophyRecorder._();

  final _log = Logger('TrophyRecorder');
  final _firestoreClient = _FirestoreClient.instance;

  static const _collection = 'ranked_stats';

  /// Records the result of a completed ranked game for every participant.
  ///
  /// [winnerUid] receives +[_kWinDelta] rating; all other [allPlayerUids]
  /// receive [_kLossDelta] rating. All get gamesPlayed incremented.
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid})> allPlayerUids,
  }) {
    // Fire-and-forget — game flow does not wait for persistence.
    unawaited(_persistResult(winnerUid: winnerUid, allPlayerUids: allPlayerUids));
  }

  Future<void> _persistResult({
    required String winnerUid,
    required List<({String playerId, String uid})> allPlayerUids,
  }) async {
    _log.info('Recording ranked result — winner: $winnerUid, '
        'players: ${allPlayerUids.map((e) => e.uid).join(', ')}');

    final futures = <Future<void>>[];
    for (final entry in allPlayerUids) {
      final uid = entry.uid;
      final isWinner = uid == winnerUid;
      final ratingDelta = isWinner ? _kWinDelta : _kLossDelta;

      futures.addAll([
        _firestoreClient.incrementField(
          collection: _collection,
          docId: uid,
          field: 'rating',
          delta: ratingDelta,
          defaultFields: {'rating': _kInitialRating + ratingDelta},
        ),
        _firestoreClient.incrementField(
          collection: _collection,
          docId: uid,
          field: isWinner ? 'wins' : 'losses',
          delta: 1,
          defaultFields: {isWinner ? 'wins' : 'losses': 1},
        ),
        _firestoreClient.incrementField(
          collection: _collection,
          docId: uid,
          field: 'gamesPlayed',
          delta: 1,
          defaultFields: {'gamesPlayed': 1},
        ),
      ]);
    }

    await Future.wait(futures);
    _log.info('Ranked result persisted.');
  }

  /// Records a leave penalty for a player who disconnected during a ranked game.
  void recordLeavePenalty(String uid) {
    unawaited(_persistLeavePenalty(uid));
  }

  Future<void> _persistLeavePenalty(String uid) async {
    _log.info('Recording leave penalty for $uid');
    await Future.wait([
      _firestoreClient.incrementField(
        collection: _collection,
        docId: uid,
        field: 'rating',
        delta: _kLeaveDelta,
        defaultFields: {'rating': _kInitialRating + _kLeaveDelta},
      ),
      _firestoreClient.incrementField(
        collection: _collection,
        docId: uid,
        field: 'leaves',
        delta: 1,
        defaultFields: {'leaves': 1},
      ),
      _firestoreClient.incrementField(
        collection: _collection,
        docId: uid,
        field: 'gamesPlayed',
        delta: 1,
        defaultFields: {'gamesPlayed': 1},
      ),
    ]);
  }

  /// Legacy no-op — superseded by [recordRankedResult].
  @Deprecated('Use recordRankedResult instead')
  void recordWin(String playerId) {}
}
