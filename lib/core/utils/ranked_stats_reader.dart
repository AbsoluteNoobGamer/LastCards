import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

typedef RankedStatsSnapshot = ({
  int rating,
  int wins,
  int losses,
});

/// Ranked lifetime stats for the signed-in user from [ranked_stats].
///
/// Returns `null` if there is no Firebase user, if the document does not exist
/// (user has never played ranked), or on read failure.
Future<RankedStatsSnapshot?> fetchRankedStatsForCurrentUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return fetchRankedStatsForUid(uid);
}

/// Ranked stats for any user (same collection the server writes).
Future<RankedStatsSnapshot?> fetchRankedStatsForUid(String uid) async {
  return _fetchRankedDoc(uid, 'ranked_stats');
}

/// Hardcore ranked (30s turns, etc.) — `ranked_hardcore_stats` on the server.
Future<RankedStatsSnapshot?> fetchRankedHardcoreStatsForUid(String uid) async {
  return _fetchRankedDoc(uid, 'ranked_hardcore_stats');
}

Future<RankedStatsSnapshot?> fetchRankedHardcoreStatsForCurrentUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return fetchRankedHardcoreStatsForUid(uid);
}

Future<RankedStatsSnapshot?> _fetchRankedDoc(
    String uid, String collection) async {
  if (uid.isEmpty) return null;
  try {
    final doc =
        await FirebaseFirestore.instance.collection(collection).doc(uid).get();
    if (!doc.exists) return null;
    final d = doc.data() ?? <String, dynamic>{};
    int toInt(Object? v, int def) => v is num ? v.toInt() : def;
    return (
      rating: toInt(d['rating'], 1000),
      wins: toInt(d['wins'], 0),
      losses: toInt(d['losses'], 0),
    );
  } catch (_) {
    return null;
  }
}
