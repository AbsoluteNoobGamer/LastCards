import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_event.dart';

/// Stable Firestore doc id for two Firebase UIDs (matches server [matchupPairDocId]).
String matchupPairDocId(String uidA, String uidB) {
  final a = uidA.compareTo(uidB) <= 0 ? uidA : uidB;
  final b = uidA.compareTo(uidB) <= 0 ? uidB : uidA;
  return '${a}_$b';
}

/// Lifetime head-to-head vs [opponentUid] for the signed-in user.
///
/// Returns `null` when not signed in, the doc is missing, or read fails.
Future<HeadToHeadRecord?> fetchHeadToHeadForOpponent({
  required String opponentUid,
  String opponentName = '',
}) async {
  final viewerUid = FirebaseAuth.instance.currentUser?.uid;
  if (viewerUid == null ||
      viewerUid.isEmpty ||
      opponentUid.isEmpty ||
      viewerUid == opponentUid) {
    return null;
  }
  return fetchHeadToHeadBetween(
    viewerUid: viewerUid,
    opponentUid: opponentUid,
    opponentName: opponentName,
  );
}

/// Head-to-head between two Firebase accounts (viewer perspective).
Future<HeadToHeadRecord?> fetchHeadToHeadBetween({
  required String viewerUid,
  required String opponentUid,
  String opponentName = '',
}) async {
  if (viewerUid.isEmpty || opponentUid.isEmpty || viewerUid == opponentUid) {
    return null;
  }
  try {
    final docId = matchupPairDocId(viewerUid, opponentUid);
    final doc = await FirebaseFirestore.instance
        .collection('matchups')
        .doc(docId)
        .get();
    if (!doc.exists) return null;
    final d = doc.data() ?? <String, dynamic>{};

    int toInt(Object? v) => v is num ? v.toInt() : 0;
    final winsLow = toInt(d['winsLow']);
    final winsHigh = toInt(d['winsHigh']);
    final recentForLow = (d['recentForLow'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    final lowUid =
        viewerUid.compareTo(opponentUid) <= 0 ? viewerUid : opponentUid;
    final viewerIsLow = viewerUid == lowUid;
    final yourWins = viewerIsLow ? winsLow : winsHigh;
    final theirWins = viewerIsLow ? winsHigh : winsLow;
    final recentResults = viewerIsLow
        ? recentForLow
        : recentForLow
            .map((r) => r == 'win' ? 'loss' : 'win')
            .toList();

    if (yourWins == 0 && theirWins == 0 && recentResults.isEmpty) {
      return null;
    }

    return HeadToHeadRecord(
      opponentUid: opponentUid,
      opponentName: opponentName,
      yourWins: yourWins,
      theirWins: theirWins,
      recentResults: recentResults,
    );
  } catch (_) {
    return null;
  }
}
