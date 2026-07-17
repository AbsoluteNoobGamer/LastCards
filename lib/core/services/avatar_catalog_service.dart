import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/avatars/avatar_catalog.dart';
import 'player_level_service.dart';

/// Selection + unlock state for in-game avatar cosmetics.
class AvatarCatalogService {
  AvatarCatalogService._();
  static final AvatarCatalogService instance = AvatarCatalogService._();

  static const _prefsSelectedKey = 'avatar_selected_id';

  bool _initialized = false;

  /// `use_photo` or a catalog id. Never null after [init].
  final ValueNotifier<String> selectedId =
      ValueNotifier<String>(kAvatarUsePhotoId);

  /// Title exclusives currently owned (refreshed via [refreshTitleEntitlements]).
  final ValueNotifier<Set<AvatarExclusiveKind>> ownedTitles =
      ValueNotifier<Set<AvatarExclusiveKind>>(<AvatarExclusiveKind>{});

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsSelectedKey);
    if (saved != null && isKnownAvatarId(saved)) {
      selectedId.value = saved;
    }
    await PlayerLevelService.instance.init();
    PlayerLevelService.instance.currentLevel.addListener(_onLevelChanged);
    _initialized = true;
    await sanitizeSelection();
  }

  void _onLevelChanged() {
    unawaited(sanitizeSelection());
  }

  bool isUnlocked(AvatarDesign design) {
    if (design.isTitleExclusive) {
      return ownedTitles.value.contains(design.exclusiveKind);
    }
    return PlayerLevelService.instance.currentLevel.value >= design.unlockLevel;
  }

  /// Cosmetic id to stamp onto [PlayerModel] for online/offline play, or null
  /// when using photo/initials.
  String? get equippedCosmeticId {
    final id = selectedId.value;
    if (id == kAvatarUsePhotoId) return null;
    final design = avatarDesignById(id);
    if (design == null || !isUnlocked(design)) return null;
    return id;
  }

  Future<void> select(String id, {bool pushToFirestore = true}) async {
    await init();
    if (!isKnownAvatarId(id)) return;
    if (id != kAvatarUsePhotoId) {
      final design = avatarDesignById(id);
      if (design == null || !isUnlocked(design)) return;
    }
    selectedId.value = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSelectedKey, id);
    if (pushToFirestore) {
      unawaited(_pushSelectionToFirestore(id));
    }
  }

  Future<void> applyFromFirestore(String? firestoreId) async {
    await init();
    final id = firestoreId?.trim();
    if (id == null || id.isEmpty || !isKnownAvatarId(id)) return;
    await select(id, pushToFirestore: false);
  }

  Future<void> sanitizeSelection() async {
    await init();
    final id = selectedId.value;
    if (id == kAvatarUsePhotoId) return;
    final design = avatarDesignById(id);
    if (design == null || !isUnlocked(design)) {
      await select(kAvatarUsePhotoId, pushToFirestore: true);
    }
  }

  Future<void> refreshTitleEntitlements() async {
    await init();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ownedTitles.value = {};
      await sanitizeSelection();
      return;
    }

    final owned = <AvatarExclusiveKind>{};
    Future<void> check({
      required String collection,
      required String orderField,
      required bool descending,
      required AvatarExclusiveKind kind,
    }) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .orderBy(orderField, descending: descending)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) return;
        if (snap.docs.first.id == uid) owned.add(kind);
      } catch (_) {
        // Best-effort — offline / rules may block; titles stay locked.
      }
    }

    await Future.wait([
      check(
        collection: 'leaderboard_combos',
        orderField: 'comboCount',
        descending: true,
        kind: AvatarExclusiveKind.comboKing,
      ),
      check(
        collection: 'ranked_stats',
        orderField: 'rating',
        descending: true,
        kind: AvatarExclusiveKind.rankedCrown,
      ),
      check(
        collection: 'ranked_hardcore_stats',
        orderField: 'rating',
        descending: true,
        kind: AvatarExclusiveKind.hardcoreCrown,
      ),
      check(
        collection: 'leaderboard_online',
        orderField: 'wins',
        descending: true,
        kind: AvatarExclusiveKind.casualAce,
      ),
      check(
        collection: 'leaderboard_tournament_ai',
        orderField: 'wins',
        descending: true,
        kind: AvatarExclusiveKind.tourneyAi,
      ),
      check(
        collection: 'leaderboard_tournament_online',
        orderField: 'wins',
        descending: true,
        kind: AvatarExclusiveKind.tourneyOnline,
      ),
      check(
        collection: 'leaderboard_bust_online',
        orderField: 'wins',
        descending: true,
        kind: AvatarExclusiveKind.bustOnline,
      ),
    ]);

    ownedTitles.value = owned;
    await sanitizeSelection();
  }

  Future<void> _pushSelectionToFirestore(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'avatarSelectedId': id},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
