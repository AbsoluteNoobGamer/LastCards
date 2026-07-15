part of 'trophy_recorder.dart';

// ── Pure helpers (unit-tested) ────────────────────────────────────────────────

/// Stable Firestore doc id for two Firebase UIDs.
String matchupPairDocId(String uidA, String uidB) {
  final a = uidA.compareTo(uidB) <= 0 ? uidA : uidB;
  final b = uidA.compareTo(uidB) <= 0 ? uidB : uidA;
  return '${a}_$b';
}

/// After one game, append [resultForLow] ("win" | "loss") from the low-UID player's view.
List<String> appendRecentResult(List<String> current, String resultForLow,
    {int maxLen = 5}) {
  final next = [...current, resultForLow];
  if (next.length <= maxLen) return next;
  return next.sublist(next.length - maxLen);
}

/// Head-to-head row for one opponent, from the viewer's perspective.
Map<String, dynamic> headToHeadRow({
  required String opponentUid,
  required String opponentName,
  required int yourWins,
  required int theirWins,
  required List<String> recentResults,
}) {
  return {
    'opponentUid': opponentUid,
    'opponentName': opponentName,
    'yourWins': yourWins,
    'theirWins': theirWins,
    'recentResults': recentResults,
  };
}

// ── Persistence ───────────────────────────────────────────────────────────────

/// Records lifetime head-to-head between human Firebase accounts.
abstract class MatchupPersistence {
  /// Updates all human pairs and returns per-viewer [playerId] → H2H rows.
  Future<Map<String, List<Map<String, dynamic>>>> recordGameEnd({
    required String winnerPlayerId,
    required List<
        ({String playerId, String? firebaseUid, String displayName})> players,
  });
}

class MatchupRecorder implements MatchupPersistence {
  MatchupRecorder._();
  static final MatchupRecorder instance = MatchupRecorder._();

  final _log = Logger('MatchupRecorder');
  final _firestore = _FirestoreClient.instance;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> recordGameEnd({
    required String winnerPlayerId,
    required List<
        ({String playerId, String? firebaseUid, String displayName})> players,
  }) async {
    final humans = players
        .where((p) => modeLeaderboardUidEligible(p.firebaseUid))
        .toList();
    if (humans.length < 2) return {};

    final out = <String, List<Map<String, dynamic>>>{};
    // Each unordered pair is recorded exactly once — recording per *ordered*
    // pair (every viewer against every opponent) would call _recordPair
    // twice for the same two players, both writes landing on the same
    // sorted-UID doc: every real game would double-count winsLow/winsHigh
    // and append two duplicate entries to recentForLow instead of one.
    for (var i = 0; i < humans.length; i++) {
      for (var j = i + 1; j < humans.length; j++) {
        final a = humans[i];
        final b = humans[j];
        final pair = await _recordPair(
          aUid: a.firebaseUid!,
          aName: a.displayName,
          aWon: winnerPlayerId == a.playerId,
          bUid: b.firebaseUid!,
          bName: b.displayName,
        );
        if (pair == null) continue;
        out.putIfAbsent(a.playerId, () => []).add(pair.forA);
        out.putIfAbsent(b.playerId, () => []).add(pair.forB);
      }
    }
    return out;
  }

  Future<({Map<String, dynamic> forA, Map<String, dynamic> forB})?>
      _recordPair({
    required String aUid,
    required String aName,
    required bool aWon,
    required String bUid,
    required String bName,
  }) async {
    final docId = matchupPairDocId(aUid, bUid);
    final lowUid = aUid.compareTo(bUid) <= 0 ? aUid : bUid;
    final highUid = aUid.compareTo(bUid) <= 0 ? bUid : aUid;
    final aIsLow = aUid == lowUid;
    final lowWon = aIsLow ? aWon : !aWon;
    final resultForLow = lowWon ? 'win' : 'loss';

    final existing = await _firestore.getDocumentFields(
      collection: 'matchups',
      docId: docId,
    );

    var winsLow = _intField(existing, 'winsLow');
    var winsHigh = _intField(existing, 'winsHigh');
    var recentForLow = _stringListField(existing, 'recentForLow');

    if (resultForLow == 'win') {
      winsLow++;
    } else {
      winsHigh++;
    }
    recentForLow = appendRecentResult(recentForLow, resultForLow);

    final ok = await _firestore.setDocumentFields(
      collection: 'matchups',
      docId: docId,
      fields: {
        'uidLow': lowUid,
        'uidHigh': highUid,
        'winsLow': winsLow,
        'winsHigh': winsHigh,
        'recentForLow': recentForLow,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!ok) return null;

    final recentForHigh =
        recentForLow.map((r) => r == 'win' ? 'loss' : 'win').toList();

    return (
      forA: headToHeadRow(
        opponentUid: bUid,
        opponentName: bName,
        yourWins: aIsLow ? winsLow : winsHigh,
        theirWins: aIsLow ? winsHigh : winsLow,
        recentResults: aIsLow ? recentForLow : recentForHigh,
      ),
      forB: headToHeadRow(
        opponentUid: aUid,
        opponentName: aName,
        yourWins: aIsLow ? winsHigh : winsLow,
        theirWins: aIsLow ? winsLow : winsHigh,
        recentResults: aIsLow ? recentForHigh : recentForLow,
      ),
    );
  }

  int _intField(Map<String, dynamic>? doc, String key) {
    final v = doc?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  List<String> _stringListField(Map<String, dynamic>? doc, String key) {
    final v = doc?[key];
    if (v is! List) return const [];
    return v.whereType<String>().toList();
  }
}

/// No-op for tests without Firestore.
class NoOpMatchupRecorder implements MatchupPersistence {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> recordGameEnd({
    required String winnerPlayerId,
    required List<
        ({String playerId, String? firebaseUid, String displayName})> players,
  }) async =>
      {};
}
