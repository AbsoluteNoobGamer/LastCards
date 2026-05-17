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
    for (final viewer in humans) {
      final viewerUid = viewer.firebaseUid!;
      final rows = <Map<String, dynamic>>[];
      final viewerWon = winnerPlayerId == viewer.playerId;

      for (final opp in humans) {
        if (opp.playerId == viewer.playerId) continue;
        final oppUid = opp.firebaseUid!;
        final row = await _recordPair(
          viewerUid: viewerUid,
          viewerPlayerId: viewer.playerId,
          opponentUid: oppUid,
          opponentName: opp.displayName,
          viewerWon: viewerWon,
        );
        if (row != null) rows.add(row);
      }
      if (rows.isNotEmpty) {
        out[viewer.playerId] = rows;
      }
    }
    return out;
  }

  Future<Map<String, dynamic>?> _recordPair({
    required String viewerUid,
    required String viewerPlayerId,
    required String opponentUid,
    required String opponentName,
    required bool viewerWon,
  }) async {
    final docId = matchupPairDocId(viewerUid, opponentUid);
    final lowUid = viewerUid.compareTo(opponentUid) <= 0 ? viewerUid : opponentUid;
    final viewerIsLow = viewerUid == lowUid;
    final resultForLow = viewerIsLow
        ? (viewerWon ? 'win' : 'loss')
        : (viewerWon ? 'loss' : 'win');

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

    final highUid =
        viewerUid.compareTo(opponentUid) <= 0 ? opponentUid : viewerUid;

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

    final yourWins = viewerIsLow ? winsLow : winsHigh;
    final theirWins = viewerIsLow ? winsHigh : winsLow;
    final recentResults = viewerIsLow
        ? recentForLow
        : recentForLow.map((r) => r == 'win' ? 'loss' : 'win').toList();

    return headToHeadRow(
      opponentUid: opponentUid,
      opponentName: opponentName,
      yourWins: yourWins,
      theirWins: theirWins,
      recentResults: recentResults,
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
