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

// ── Pure stat maps (unit-tested; used by [TrophyRecorder]) ───────────────────

/// Firestore increment + default-field maps for one ranked player at game end.
({Map<String, int> increments, Map<String, dynamic> defaultFields})
    rankedResultStatMaps({
  required bool isWinner,
  required int playerCount,
}) {
  final n = playerCount.clamp(2, 7);
  final hasBracket = playerCount >= 2;
  final ratingDelta = isWinner ? _kWinDelta : _kLossDelta;
  return (
    increments: {
      'rating': ratingDelta,
      if (isWinner) 'wins': 1,
      if (!isWinner) 'losses': 1,
      'gamesPlayed': 1,
      if (hasBracket) 'gamesPlayed_$n': 1,
      if (hasBracket && isWinner) 'wins_$n': 1,
      if (hasBracket && !isWinner) 'losses_$n': 1,
    },
    defaultFields: {
      'rating': _kInitialRating,
      'wins': 0,
      'losses': 0,
      'leaves': 0,
      'gamesPlayed': 0,
      if (hasBracket) 'wins_$n': 0,
      if (hasBracket) 'losses_$n': 0,
      if (hasBracket) 'gamesPlayed_$n': 0,
    },
  );
}

/// Firestore increment + default-field maps for a ranked leave penalty.
({Map<String, int> increments, Map<String, dynamic> defaultFields})
    rankedLeavePenaltyStatMaps() {
  return (
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
  );
}

/// Firestore increment + default-field maps for casual/bust online leaderboards.
({Map<String, int> increments, Map<String, dynamic> defaultFields})
    modeLeaderboardStatMaps({
  required bool won,
  required int playerCount,
}) {
  final n = playerCount.clamp(2, 10);
  return (
    increments: {
      'gamesPlayed': 1,
      if (won) 'wins': 1,
      if (!won) 'losses': 1,
      'gamesPlayed_$n': 1,
      if (won) 'wins_$n': 1,
      if (!won) 'losses_$n': 1,
    },
    defaultFields: {
      'wins': 0,
      'losses': 0,
      'gamesPlayed': 0,
      'wins_$n': 0,
      'losses_$n': 0,
      'gamesPlayed_$n': 0,
    },
  );
}

/// Whether a participant should persist to mode leaderboards (Firestore doc id).
bool modeLeaderboardUidEligible(String? firebaseUid) =>
    firebaseUid != null && firebaseUid.isNotEmpty;

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

  bool _initCalled = false;

  /// Initialises credentials from the GOOGLE_CREDENTIALS_JSON env var.
  void init() {
    if (_initCalled) return;
    _initCalled = true;
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
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode == 200) return true;
      // 400 with ALREADY_EXISTS means the conditional create was skipped
      // (doc exists). Re-send with only the transforms + string overwrites.
      if (response.statusCode == 400 &&
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
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode == 200) return true;
      _log.error(
          'Firestore _updateExisting failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      _log.error('Firestore _updateExisting error: $e');
      return false;
    }
  }

  /// Overwrites [fields] on [collection]/[docId] via PATCH (not increment).
  /// Creates the document if missing. Skips when credentials are not configured.
  Future<void> _setDocumentFields({
    required String collection,
    required String docId,
    required Map<String, dynamic> fields,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

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
      final response = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        _log.error(
            'Firestore _setDocumentFields failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Firestore _setDocumentFields error: $e');
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

// ── Trophy persistence (implemented by [TrophyRecorder]) ─────────────────────

/// Hooks for ranked MMR and mode leaderboards used by [GameSession].
///
/// Production code uses [TrophyRecorder.instance]; tests may supply a
/// lightweight implementation that records call counts without Firestore.
abstract class TrophyPersistence {
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
  });

  void recordLeavePenalty(String uid, {required String displayName});

  void recordLeaderboardOnlineCasual({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  });

  void recordLeaderboardBustOnline({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  });
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
class TrophyRecorder implements TrophyPersistence {
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
  ///
  /// [playerCount] (2–7) is used to also increment per-bracket fields
  /// (`wins_N`, `losses_N`, `gamesPlayed_N`) for filterable leaderboard views.
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
  }) {
    // Fire-and-forget — game flow does not wait for persistence.
    unawaited(_persistResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: playerCount));
  }

  Future<void> _persistResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
  }) async {
    final n = playerCount.clamp(2, 7);
    final hasBracket = playerCount >= 2;
    _log.info('Recording ranked result (${hasBracket ? "${n}p" : "?"}) — '
        'winner: $winnerUid, '
        'players: ${allPlayerUids.map((e) => e.uid).join(', ')}');

    final futures = <Future<bool>>[];
    for (final entry in allPlayerUids) {
      final uid = entry.uid;
      final isWinner = uid == winnerUid;
      final maps = rankedResultStatMaps(
        isWinner: isWinner,
        playerCount: playerCount,
      );

      // Single atomic commit per player: creates with baseline defaults if the
      // doc is missing, then applies all increments. No double-counting, no
      // race between parallel calls for the same document.
      futures.add(
        _firestoreClient.atomicUpdate(
          collection: _collection,
          docId: uid,
          increments: maps.increments,
          defaultFields: maps.defaultFields,
          stringFields: {
            'displayName': entry.displayName,
          },
        ),
      );
    }

    final results = await Future.wait(futures);
    final failed = results.where((r) => !r).length;
    if (failed == 0) {
      _log.info('Ranked result persisted.');
    } else if (!_firestoreClient.isFirestoreConfigured) {
      _log.warning(
        'Ranked result not persisted: Firestore credentials missing '
        '(GOOGLE_CREDENTIALS_JSON). In-game MMR deltas are still sent; '
        'profile and leaderboard read from Firestore and will not change until '
        'the server is configured with a service account for the app Firebase project.',
      );
    } else {
      _log.error(
        'Ranked Firestore write failed for $failed of ${results.length} players.',
      );
    }
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
  ///
  /// [playerCount] is the number of human participants in this session (2–7).
  /// Global totals (`wins`, `losses`, `gamesPlayed`) and per-bracket fields
  /// (`wins_N`, `losses_N`, `gamesPlayed_N`) are both incremented.
  void recordLeaderboardOnlineCasual({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  }) {
    unawaited(_persistModeLeaderboard(
      collection: _leaderboardOnline,
      winnerPlayerId: winnerPlayerId,
      players: players,
      playerCount: playerCount,
    ));
  }

  /// Online Bust finals → [leaderboard_bust_online].
  ///
  /// [playerCount] is the number of participants in the final bust session.
  void recordLeaderboardBustOnline({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  }) {
    unawaited(_persistModeLeaderboard(
      collection: _leaderboardBustOnline,
      winnerPlayerId: winnerPlayerId,
      players: players,
      playerCount: playerCount,
    ));
  }

  Future<void> _persistModeLeaderboard({
    required String collection,
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  }) async {
    final n = playerCount.clamp(2, 10);
    _log.info(
        'Recording $collection (${n}p) — winner player: $winnerPlayerId, '
        'participants: ${players.map((p) => p.playerId).join(', ')}');

    final futures = <Future<bool>>[];
    for (final p in players) {
      if (!modeLeaderboardUidEligible(p.firebaseUid)) continue;
      final uid = p.firebaseUid!;
      final won = p.playerId == winnerPlayerId;
      final maps = modeLeaderboardStatMaps(won: won, playerCount: playerCount);
      futures.add(
        _firestoreClient.atomicUpdate(
          collection: collection,
          docId: uid,
          increments: maps.increments,
          defaultFields: maps.defaultFields,
          stringFields: {
            'displayName': p.displayName,
          },
        ),
      );
    }

    if (futures.isEmpty) return;

    final results = await Future.wait(futures);
    final failed = results.where((r) => !r).length;
    if (failed == 0) {
      _log.info('$collection (${n}p) result persisted.');
    } else if (!_firestoreClient.isFirestoreConfigured) {
      _log.warning(
        '$collection not persisted: GOOGLE_CREDENTIALS_JSON unset (same as ranked_stats).',
      );
    } else {
      _log.error(
        '$collection Firestore write failed for $failed of ${results.length} players.',
      );
    }
  }

  Future<void> _persistLeavePenalty(String uid,
      {required String displayName}) async {
    _log.info('Recording leave penalty for $uid');
    final maps = rankedLeavePenaltyStatMaps();
    final ok = await _firestoreClient.atomicUpdate(
      collection: _collection,
      docId: uid,
      increments: maps.increments,
      defaultFields: maps.defaultFields,
      stringFields: {
        'displayName': displayName,
      },
    );
    if (!ok && !_firestoreClient.isFirestoreConfigured) {
      _log.warning('Leave penalty not persisted: Firestore credentials missing.');
    }
  }

  /// Legacy no-op — superseded by [recordRankedResult].
  @Deprecated('Use recordRankedResult instead')
  void recordWin(String playerId) {}
}

/// Syncs the public Firestore doc `metadata/online_count` (`count` field) with
/// concurrent WebSocket connections to this game server: [delta] is +1 on
/// connect and -1 on disconnect. Skips writes when `GOOGLE_CREDENTIALS_JSON`
/// is not configured (same as other Firestore writes).
void syncOnlineServerPresenceDelta(int delta) {
  if (delta == 0) return;
  _FirestoreClient.instance.init();
  unawaited(
    _FirestoreClient.instance.atomicUpdate(
      collection: 'metadata',
      docId: 'online_count',
      increments: {'count': delta},
      defaultFields: {'count': 0},
    ),
  );
}

/// Resets `metadata/online_count` `count` to [value] (default `0`) using a
/// document set/overwrite, not increment. Call once at process startup so a
/// crash does not leave a stale total before new [syncOnlineServerPresenceDelta]
/// updates. No-op when `GOOGLE_CREDENTIALS_JSON` is unset.
Future<void> syncOnlineServerPresenceReset({int value = 0}) async {
  _FirestoreClient.instance.init();
  await _FirestoreClient.instance._setDocumentFields(
    collection: 'metadata',
    docId: 'online_count',
    fields: {'count': value},
  );
}

/// Logs whether Firestore persistence is configured. Call once from [main].
///
/// Without `GOOGLE_CREDENTIALS_JSON`, the server still sends in-game MMR deltas
/// but [ranked_stats] and leaderboards never update in Firestore.
void logGameServerFirestoreStartupStatus() {
  final log = Logger('GameServer');
  _FirestoreClient.instance.init();
  final client = _FirestoreClient.instance;
  if (client.isFirestoreConfigured) {
    log.info(
      'Firestore writes enabled (project "${client.firestoreProjectId}"). '
      'Ranked MMR and leaderboards persist to this project.',
    );
  } else {
    log.warning(
      'GOOGLE_CREDENTIALS_JSON is not set: ranked_stats, mode leaderboards, '
      'and online presence will NOT persist. Use a service account key from the '
      'same Firebase project as the app (see lib/firebase_options.dart → projectId).',
    );
  }
}
