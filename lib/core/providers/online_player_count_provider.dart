import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live `count` from Firestore `metadata/online_count` (field `count`).
/// Null while loading or if missing; update the document server-side for accuracy.
final onlinePlayerCountProvider = StreamProvider<int?>((ref) {
  return FirebaseFirestore.instance
      .collection('metadata')
      .doc('online_count')
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    final v = snap.data()?['count'];
    if (v is num) return v.toInt();
    return null;
  });
});
