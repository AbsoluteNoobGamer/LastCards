import 'dart:async';

import 'package:last_cards/shared/leaderboard/display_name_leaderboard_rules.dart';

import 'firestore_client.dart';
import 'logger.dart';

part 'matchup_recorder.dart';

// ── Rating constants ───────────────────────────────────────────────────────────

const _kInitialRating = 1000;

/// 4-player leave delta (historic flat value). Prefer [rankedLeaveDelta].
const kRankedLeaveRatingDelta = -35;

/// Ranked win MMR by table size. 4-player stays at the historic +25.
int rankedWinDelta(int playerCount) {
  switch (playerCount.clamp(2, 7)) {
    case 2:
      return 15;
    case 3:
      return 20;
    case 4:
      return 25;
    case 5:
      return 30;
    case 6:
      return 35;
    default:
      return 40;
  }
}

/// Ranked loss MMR by table size. 4-player stays at the historic −15.
int rankedLossDelta(int playerCount) {
  switch (playerCount.clamp(2, 7)) {
    case 2:
      return -10;
    case 3:
      return -12;
    case 4:
      return -15;
    case 5:
      return -18;
    case 6:
      return -20;
    default:
      return -22;
  }
}

/// Ranked leave/abandon MMR by table size. Always worse than [rankedLossDelta]
/// at the same size. 4-player stays at the historic −35.
int rankedLeaveDelta(int playerCount) {
  switch (playerCount.clamp(2, 7)) {
    case 2:
      return -25;
    case 3:
      return -30;
    case 4:
      return -35;
    case 5:
      return -40;
    case 6:
      return -45;
    default:
      return -50;
  }
}

// ── Pure stat maps (unit-tested; used by [TrophyRecorder]) ───────────────────

/// Firestore increment + default-field maps for one ranked player at game end.
({Map<String, int> increments, Map<String, dynamic> defaultFields})
    rankedResultStatMaps({
  required bool isWinner,
  required int playerCount,
}) {
  final n = playerCount.clamp(2, 7);
  final hasBracket = playerCount >= 2;
  final ratingDelta =
      isWinner ? rankedWinDelta(playerCount) : rankedLossDelta(playerCount);
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
///
/// Counts as a loss for global and per-bracket stats (same roster size as normal
/// ranked games via [playerCount]).
({Map<String, int> increments, Map<String, dynamic> defaultFields})
    rankedLeavePenaltyStatMaps({int playerCount = 4}) {
  final n = playerCount.clamp(2, 7);
  final hasBracket = playerCount >= 2;
  return (
    increments: {
      'rating': rankedLeaveDelta(playerCount),
      'leaves': 1,
      'losses': 1,
      'gamesPlayed': 1,
      if (hasBracket) 'gamesPlayed_$n': 1,
      if (hasBracket) 'losses_$n': 1,
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

/// Whether [displayName] may be written to leaderboard / ranked stat docs.
bool modeLeaderboardDisplayNameEligible(String displayName) =>
    isLeaderboardEligibleDisplayName(displayName);

// ── Trophy persistence (implemented by [TrophyRecorder]) ─────────────────────

/// Hooks for ranked MMR and mode leaderboards used by [GameSession].
///
/// Production code uses [TrophyRecorder.instance]; tests may supply a
/// lightweight implementation that records call counts without Firestore.
abstract class TrophyPersistence {
  /// [rankedHardcore] uses Firestore `ranked_hardcore_stats` instead of `ranked_stats`.
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
    bool rankedHardcore = false,
  });

  void recordLeavePenalty(String uid,
      {required String displayName,
      bool rankedHardcore = false,
      int playerCount = 4});

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
/// losses:      int   (+1 on normal loss; ranked disconnect also increments)
/// leaves:      int   (+1 on disconnect / abandon mid-match only)
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
  final _firestoreClient = FirestoreClient.instance;

  static const _collection = 'ranked_stats';
  static const _collectionHardcore = 'ranked_hardcore_stats';

  /// Records the result of a completed ranked game for every participant.
  ///
  /// [winnerUid] receives [rankedWinDelta]; all other [allPlayerUids]
  /// receive [rankedLossDelta]. All get gamesPlayed incremented.
  /// Each player's [displayName] is persisted for leaderboard display.
  ///
  /// [playerCount] (2–7) is used to also increment per-bracket fields
  /// (`wins_N`, `losses_N`, `gamesPlayed_N`) for filterable leaderboard views.
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
    bool rankedHardcore = false,
  }) {
    // Fire-and-forget — game flow does not wait for persistence.
    unawaited(_persistResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: playerCount,
        collection: rankedHardcore ? _collectionHardcore : _collection));
  }

  Future<void> _persistResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
    required String collection,
  }) async {
    final n = playerCount.clamp(2, 7);
    final hasBracket = playerCount >= 2;
    _log.info('Recording ranked result (${hasBracket ? "${n}p" : "?"}) — '
        'winner: $winnerUid, '
        'players: ${allPlayerUids.map((e) => e.uid).join(', ')}');

    final futures = <Future<bool>>[];
    for (final entry in allPlayerUids) {
      if (!modeLeaderboardDisplayNameEligible(entry.displayName)) {
        _log.info(
          'Skipping ranked write for ${entry.uid}: '
          'display name "${entry.displayName}" is not leaderboard-eligible',
        );
        continue;
      }
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
          collection: collection,
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
  void recordLeavePenalty(String uid,
      {required String displayName,
      bool rankedHardcore = false,
      int playerCount = 4}) {
    if (!modeLeaderboardDisplayNameEligible(displayName)) return;
    unawaited(_persistLeavePenalty(uid,
        displayName: displayName,
        collection: rankedHardcore ? _collectionHardcore : _collection,
        playerCount: playerCount));
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
      if (!modeLeaderboardDisplayNameEligible(p.displayName)) {
        _log.info(
          'Skipping $collection write for ${p.firebaseUid}: '
          'display name "${p.displayName}" is not leaderboard-eligible',
        );
        continue;
      }
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
      {required String displayName,
      required String collection,
      int playerCount = 4}) async {
    _log.info('Recording leave penalty for $uid');
    final maps = rankedLeavePenaltyStatMaps(playerCount: playerCount);
    final ok = await _firestoreClient.atomicUpdate(
      collection: collection,
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
  FirestoreClient.instance.init();
  unawaited(
    FirestoreClient.instance.atomicUpdate(
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
  FirestoreClient.instance.init();
  await FirestoreClient.instance.setDocumentFields(
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
  FirestoreClient.instance.init();
  final client = FirestoreClient.instance;
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
