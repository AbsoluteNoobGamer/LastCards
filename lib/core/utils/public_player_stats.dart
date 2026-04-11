import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/leaderboard/data/leaderboard_collections.dart';

typedef PublicModeStats = ({int wins, int losses, int gamesPlayed});

int _toInt(Object? v) => v is num ? v.toInt() : 0;

/// Server-backed leaderboard rows for [uid] (read-only Firestore).
Future<Map<LeaderboardMode, PublicModeStats>> fetchPublicModeStatsForUid(
    String uid) async {
  const zero = (wins: 0, losses: 0, gamesPlayed: 0);
  if (uid.isEmpty) {
    return {for (final m in LeaderboardMode.values) m: zero};
  }
  final results = <LeaderboardMode, PublicModeStats>{
    for (final m in LeaderboardMode.values) m: zero,
  };
  final firestore = FirebaseFirestore.instance;
  for (final mode in LeaderboardMode.values) {
    final collection = collectionForMode(mode);
    try {
      final doc = await firestore.collection(collection).doc(uid).get();
      if (doc.exists) {
        final d = doc.data() ?? {};
        results[mode] = (
          wins: _toInt(d['wins']),
          losses: _toInt(d['losses']),
          gamesPlayed: _toInt(d['gamesPlayed']),
        );
      }
    } catch (_) {}
  }
  return results;
}
