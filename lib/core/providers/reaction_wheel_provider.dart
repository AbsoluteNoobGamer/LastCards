import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/reactions/reaction_catalog.dart';
import '../services/player_level_service.dart';
import '../services/reaction_wheel_service.dart';
import 'auth_provider.dart';
import 'user_profile_provider.dart';

/// Starter-row reactions (catalog indices), persisted locally and merged from Firestore.
final reactionWheelProvider =
    StateNotifierProvider<ReactionWheelNotifier, List<int>>((ref) {
  final n = ReactionWheelNotifier(ref);
  ref.listen<AsyncValue<dynamic>>(authStateProvider, (_, next) {
    next.whenData((dynamic user) {
      if (user != null) {
        unawaited(n.refreshFromFirestore());
      }
    });
  });
  return n;
});

class ReactionWheelNotifier extends StateNotifier<List<int>> {
  ReactionWheelNotifier(this._ref)
      : super(List<int>.generate(kStarterReactionCount, (i) => i)) {
    PlayerLevelService.instance.currentLevel.addListener(_onLevelChanged);
    unawaited(_init());
  }

  final Ref _ref;

  void _onLevelChanged() => unawaited(reapplyUnlockSanitize());

  Future<void> _init() async {
    final raw = await ReactionWheelService.instance.loadSlots();
    final level = PlayerLevelService.instance.currentLevel.value;
    var sanitized =
        ReactionWheelService.instance.sanitizeForLevel(raw, level);
    state = sanitized;
    if (FirebaseAuth.instance.currentUser != null) {
      await refreshFromFirestore();
    }
  }

  @override
  void dispose() {
    PlayerLevelService.instance.currentLevel.removeListener(_onLevelChanged);
    super.dispose();
  }

  Future<void> reapplyUnlockSanitize() async {
    final prev = state;
    final level = PlayerLevelService.instance.currentLevel.value;
    final next = ReactionWheelService.instance.sanitizeForLevel(prev, level);
    if (!_listEq(prev, next)) {
      await _persist(next);
    }
  }

  Future<void> refreshFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile =
        await _ref.read(firestoreProfileServiceProvider).getProfileForUid(uid);
    final fw = profile?.reactionWheel;
    final level = PlayerLevelService.instance.currentLevel.value;
    if (fw != null && fw.length == kStarterReactionCount) {
      final sanitized = ReactionWheelService.instance.sanitizeForLevel(fw, level);
      await _persist(sanitized, syncFirebase: false);
    }
  }

  Future<void> setSlot(int slotIndex, int catalogId) async {
    if (slotIndex < 0 || slotIndex >= kStarterReactionCount) return;
    final level = PlayerLevelService.instance.currentLevel.value;
    if (!isReactionUnlockedForLevel(catalogId, level)) return;
    final next = [...state];
    next[slotIndex] = catalogId;
    await _persist(next);
  }

  Future<void> setWheel(List<int> slots) async {
    final level = PlayerLevelService.instance.currentLevel.value;
    final sanitized =
        ReactionWheelService.instance.sanitizeForLevel(slots, level);
    await _persist(sanitized);
  }

  Future<void> restoreDefaults() async {
    await _persist(
      List<int>.generate(kStarterReactionCount, (i) => i),
    );
  }

  Future<void> _persist(List<int> sanitized, {bool syncFirebase = true}) async {
    await ReactionWheelService.instance.saveSlots(sanitized);
    state = sanitized;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (syncFirebase && uid != null) {
      unawaited(
        _ref
            .read(firestoreProfileServiceProvider)
            .updateReactionWheel(uid, sanitized),
      );
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
