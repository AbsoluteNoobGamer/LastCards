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
  Future<void> atomicUpdate({
    required String collection,
    required String docId,
    required Map<String, int> increments,
    Map<String, dynamic> defaultFields = const {},
    Map<String, String> stringFields = const {},
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

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
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        // 400 with ALREADY_EXISTS means the conditional create was skipped
        // (doc exists). Re-send with only the transforms + string overwrites.
        if (response.statusCode == 400 &&
            response.body.contains('ALREADY_EXISTS')) {
          await _updateExisting(
            token: token,
            docPath: docPath,
            transforms: transforms,
            stringFields: stringFields,
          );
          return;
        }
        _log.error(
            'Firestore atomicUpdate failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Firestore atomicUpdate error: $e');
    }
  }

  /// Applies increments and string overwrites to an already-existing document.
  Future<void> _updateExisting({
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
            'Firestore _updateExisting failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Firestore _updateExisting error: $e');
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
/// displayName: string
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
  /// Each player's [displayName] is persisted for leaderboard display.
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
  }) {
    // Fire-and-forget — game flow does not wait for persistence.
    unawaited(
        _persistResult(winnerUid: winnerUid, allPlayerUids: allPlayerUids));
  }

  Future<void> _persistResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
  }) async {
    _log.info('Recording ranked result — winner: $winnerUid, '
        'players: ${allPlayerUids.map((e) => e.uid).join(', ')}');

    final futures = <Future<void>>[];
    for (final entry in allPlayerUids) {
      final uid = entry.uid;
      final isWinner = uid == winnerUid;
      final ratingDelta = isWinner ? _kWinDelta : _kLossDelta;

      // Single atomic commit per player: creates with baseline defaults if the
      // doc is missing, then applies all increments. No double-counting, no
      // race between parallel calls for the same document.
      futures.add(
        _firestoreClient.atomicUpdate(
          collection: _collection,
          docId: uid,
          increments: {
            'rating': ratingDelta,
            if (isWinner) 'wins': 1,
            if (!isWinner) 'losses': 1,
            'gamesPlayed': 1,
          },
          defaultFields: {
            'rating': _kInitialRating,
            'wins': 0,
            'losses': 0,
            'leaves': 0,
            'gamesPlayed': 0,
          },
          stringFields: {
            'displayName': entry.displayName,
          },
        ),
      );
    }

    await Future.wait(futures);
    _log.info('Ranked result persisted.');
  }

  /// Records a leave penalty for a player who disconnected during a ranked game.
  void recordLeavePenalty(String uid, {required String displayName}) {
    unawaited(_persistLeavePenalty(uid, displayName: displayName));
  }

  static const _leaderboardOnline = 'leaderboard_online';
  static const _leaderboardBustOnline = 'leaderboard_bust_online';

  /// Casual (non-ranked) standard online games → [leaderboard_online].
  ///
  /// Only players with a non-empty [firebaseUid] are persisted (document id =
  /// Firebase Auth uid). Call only for sessions where results are
  /// server-authoritative (e.g. quickplay with full roster).
  void recordLeaderboardOnlineCasual({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
  }) {
    unawaited(_persistModeLeaderboard(
      collection: _leaderboardOnline,
      winnerPlayerId: winnerPlayerId,
      players: players,
    ));
  }

  /// Online Bust finals → [leaderboard_bust_online].
  void recordLeaderboardBustOnline({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
  }) {
    unawaited(_persistModeLeaderboard(
      collection: _leaderboardBustOnline,
      winnerPlayerId: winnerPlayerId,
      players: players,
    ));
  }

  Future<void> _persistModeLeaderboard({
    required String collection,
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
  }) async {
    _log.info(
        'Recording $collection — winner player: $winnerPlayerId, '
        'participants: ${players.map((p) => p.playerId).join(', ')}');

    final futures = <Future<void>>[];
    for (final p in players) {
      final uid = p.firebaseUid;
      if (uid == null || uid.isEmpty) continue;
      final won = p.playerId == winnerPlayerId;
      futures.add(
        _firestoreClient.atomicUpdate(
          collection: collection,
          docId: uid,
          increments: {
            'gamesPlayed': 1,
            if (won) 'wins': 1,
            if (!won) 'losses': 1,
          },
          defaultFields: {
            'wins': 0,
            'losses': 0,
            'gamesPlayed': 0,
          },
          stringFields: {
            'displayName': p.displayName,
          },
        ),
      );
    }

    await Future.wait(futures);
    _log.info('$collection result persisted.');
  }

  Future<void> _persistLeavePenalty(String uid,
      {required String displayName}) async {
    _log.info('Recording leave penalty for $uid');
    await _firestoreClient.atomicUpdate(
      collection: _collection,
      docId: uid,
      increments: {
        'rating': _kLeaveDelta,
        'leaves': 1,
        'gamesPlayed': 1,
      },
      defaultFields: {
        'rating': _kInitialRating,
        'wins': 0,
        'losses': 0,
        'leaves': 0,
        'gamesPlayed': 0,
      },
      stringFields: {
        'displayName': displayName,
      },
    );
  }

  /// Legacy no-op — superseded by [recordRankedResult].
  @Deprecated('Use recordRankedResult instead')
  void recordWin(String playerId) {}
}

/// Test double — counts mode-leaderboard calls without touching Firestore.
class FakeTrophyRecorder extends TrophyRecorder {
  FakeTrophyRecorder() : super._();

  int leaderboardOnlineCasualCalls = 0;
  int leaderboardBustOnlineCalls = 0;
  String? lastCasualWinnerPlayerId;
  List<({String playerId, String? firebaseUid, String displayName})>?
      lastCasualPlayers;
  String? lastBustWinnerPlayerId;
  List<({String playerId, String? firebaseUid, String displayName})>?
      lastBustPlayers;

  @override
  void recordLeaderboardOnlineCasual({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
  }) {
    leaderboardOnlineCasualCalls++;
    lastCasualWinnerPlayerId = winnerPlayerId;
    lastCasualPlayers = players;
  }

  @override
  void recordLeaderboardBustOnline({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
  }) {
    leaderboardBustOnlineCalls++;
    lastBustWinnerPlayerId = winnerPlayerId;
    lastBustPlayers = players;
  }
}
