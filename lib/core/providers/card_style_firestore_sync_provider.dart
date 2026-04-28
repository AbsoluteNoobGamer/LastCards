import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/card_back_service.dart';
import '../services/firestore_profile_service.dart';
import 'auth_provider.dart';
import 'user_profile_provider.dart';

/// Raw Firestore public profile snapshots for the signed-in user.
final firestoreUserProfileSnapshotsProvider =
    StreamProvider<FirestoreUserProfile?>((ref) async* {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    yield null;
    return;
  }
  final service = ref.read(firestoreProfileServiceProvider);
  await for (final fp in service.profileStream(user)) {
    yield fp;
  }
});

/// Applies [cardBackSelectedId] / [jokerCoverSelectedId] / [cardFaceSet] from Firestore after login.
final cardStyleFirestoreSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<FirestoreUserProfile?>>(
    firestoreUserProfileSnapshotsProvider,
    (_, next) {
      final d = next.asData?.value;
      unawaited(applyFirestoreDeckPrefs(d));
    },
    fireImmediately: true,
  );
});

/// Only merges fields present on Firestore doc (missing keys leave local prefs unchanged).
Future<void> applyFirestoreDeckPrefs(FirestoreUserProfile? fp) async {
  if (fp == null) return;
  if (FirebaseAuth.instance.currentUser == null) return;
  await CardBackService.instance.init();
  // Suppress per-call Firestore write-back: each select* otherwise pushes all three
  // fields and mid-sequence writes would clobber not-yet-applied keys.
  const push = false;
  final back = fp.cardBackSelectedId?.trim();
  if (back != null && back.isNotEmpty) {
    await CardBackService.instance.selectDesign(back, pushToFirestore: push);
  }
  final joker = fp.selectedJokerCoverId?.trim();
  if (joker != null && joker.isNotEmpty) {
    await CardBackService.instance.selectJokerCover(joker, pushToFirestore: push);
  }
  final face = fp.cardFaceSetId?.trim();
  if (face != null && face.isNotEmpty) {
    await CardBackService.instance.selectCardFaceSet(face, pushToFirestore: push);
  }
}
