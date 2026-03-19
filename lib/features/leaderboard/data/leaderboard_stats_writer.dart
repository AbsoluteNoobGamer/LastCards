import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'local_leaderboard_store.dart';
import 'package:flutter/foundation.dart';

/// Writes leaderboard stats both locally and to Firestore (when authenticated).
///
/// Firestore write failures are non-fatal; local stats ensure offline matches
/// still show up and online matches remain visible immediately.
///
/// Online-mode collections are **server-only** in Firestore security rules;
/// the app never writes them from the client — only [LocalLeaderboardStore]
/// is updated here for instant UI; authoritative counts come from the game
/// server (Admin SDK).
class LeaderboardStatsWriter {
  LeaderboardStatsWriter._();

  static final LeaderboardStatsWriter instance = LeaderboardStatsWriter._();

  /// Collections written only by the game server (`allow write: if false` in rules).
  static const Set<String> firestoreServerOnlyCollections = {
    'leaderboard_online',
    'leaderboard_tournament_online',
    'leaderboard_bust_online',
  };

  Future<void> recordModeResult({
    required String collectionName,
    required String uid,
    required String displayName,
    required int deltaWins,
    required int deltaLosses,
    required int deltaGamesPlayed,
  }) async {
    // Always update local first for instant UI feedback.
    await LocalLeaderboardStore.instance.incrementEntry(
      collectionName: collectionName,
      uid: uid,
      displayName: displayName,
      deltaWins: deltaWins,
      deltaLosses: deltaLosses,
      deltaGamesPlayed: deltaGamesPlayed,
    );

    if (firestoreServerOnlyCollections.contains(collectionName)) {
      return;
    }

    // Only attempt Firestore write when this uid belongs to the current
    // signed-in Firebase user (prevents unauthorized writes for guests).
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid == null || firebaseUid != uid) return;

    try {
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(uid)
          .set(
            {
              'displayName': displayName,
              'wins': FieldValue.increment(deltaWins),
              'losses': FieldValue.increment(deltaLosses),
              'gamesPlayed': FieldValue.increment(deltaGamesPlayed),
            },
            SetOptions(merge: true),
          );
    } catch (e, st) {
      // Keep silent for release builds, but still allow debugging.
      debugPrint('Leaderboard Firestore write failed: $e\n$st');
    }
  }
}

