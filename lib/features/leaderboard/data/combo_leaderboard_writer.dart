import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/shared/leaderboard/display_name_leaderboard_rules.dart';

import 'local_combo_leaderboard_store.dart';

/// Firestore collection name for the cross-mode longest-combo leaderboard.
const String comboLeaderboardCollection = 'leaderboard_combos';

/// Records a new combo, raising the player's stored record only if
/// [comboCount] actually beats what's already there — local storage always,
/// Firestore only when signed in (so guests still get instant local
/// feedback, and the online board only ever moves up, never down).
class ComboLeaderboardWriter {
  ComboLeaderboardWriter._();

  static final ComboLeaderboardWriter instance = ComboLeaderboardWriter._();

  Future<void> recordComboIfBest({
    required String uid,
    required String displayName,
    required int comboCount,
    required List<CardModel> cards,
  }) async {
    if (!isLeaderboardEligibleDisplayName(displayName)) return;

    final (_, isNewLocalRecord) =
        await LocalComboLeaderboardStore.instance.recordIfBest(
      uid: uid,
      displayName: displayName,
      comboCount: comboCount,
      cards: cards,
      achievedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (!isNewLocalRecord) return;

    // Only push to Firestore when this uid is the signed-in user (prevents
    // unauthorized writes for guests / OfflineGameState.localId).
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid == null || firebaseUid != uid) return;

    try {
      final docRef =
          FirebaseFirestore.instance.collection(comboLeaderboardCollection).doc(uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final existing = (snap.data()?['comboCount'] as num?)?.toInt() ?? 0;
        if (existing >= comboCount) return;
        tx.set(
          docRef,
          {
            'displayName': displayName,
            'comboCount': comboCount,
            'cards': cards.map((c) => c.toJson()).toList(),
            'achievedAt': FieldValue.serverTimestamp(),
          },
        );
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Combo leaderboard Firestore write failed: $e\n$st');
      }
    }
  }
}
