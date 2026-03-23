import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

typedef RankedStatsSnapshot = ({
  int rating,
  int wins,
  int losses,
});

/// Ranked lifetime stats for the signed-in user from [ranked_stats].
///
/// Returns `null` if there is no Firebase user. If the document is missing,
/// returns rating 1000 and 0 wins/losses (same default as matchmaking MMR).
Future<RankedStatsSnapshot?> fetchRankedStatsForCurrentUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final doc =
        await FirebaseFirestore.instance.collection('ranked_stats').doc(uid).get();
    final d = doc.data() ?? <String, dynamic>{};
    int toInt(Object? v, int def) => v is num ? v.toInt() : def;
    return (
      rating: toInt(d['rating'], 1000),
      wins: toInt(d['wins'], 0),
      losses: toInt(d['losses'], 0),
    );
  } catch (_) {
    return (rating: 1000, wins: 0, losses: 0);
  }
}
