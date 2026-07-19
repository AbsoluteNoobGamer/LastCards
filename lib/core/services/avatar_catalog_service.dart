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

  /// False until the first [refreshTitleEntitlements] finishes for this session.
  /// Title exclusives stay locked while this is false (fail-closed).
  final ValueNotifier<bool> entitlementsReady = ValueNotifier<bool>(false);

  /// `use_photo` or a catalog id. Never null after [init].
  final ValueNotifier<String> selectedId =
      ValueNotifier<String>(kAvatarUsePhotoId);

  /// Title exclusives currently owned (refreshed via [refreshTitleEntitlements]).
  final ValueNotifier<Set<AvatarExclusiveKind>> ownedTitles =
      ValueNotifier<Set<AvatarExclusiveKind>>(<AvatarExclusiveKind>{});

  Future<void>? _refreshInFlight;

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
    // Strip level-locked picks immediately; title picks wait for entitlements.
    await sanitizeSelection(allowPendingTitles: true);
    unawaited(refreshTitleEntitlements());
  }

  void _onLevelChanged() {
    unawaited(sanitizeSelection());
  }

  bool isUnlocked(AvatarDesign design) {
    if (design.isTitleExclusive) {
      // Never gate titles by player level — only live #1 entitlement.
      if (!entitlementsReady.value) return false;
      final kind = design.exclusiveKind;
      if (kind == null) return false;
      return ownedTitles.value.contains(kind);
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
      if (design == null) return;
      if (design.isTitleExclusive && !entitlementsReady.value) {
        await refreshTitleEntitlements();
      }
      if (!isUnlocked(design)) return;
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
    final design = avatarDesignById(id);
    if (design != null && design.isTitleExclusive) {
      await refreshTitleEntitlements();
      if (!isUnlocked(design)) return;
    }
    await select(id, pushToFirestore: false);
  }

  /// When [allowPendingTitles] is true, keep a title selection only until
  /// entitlements resolve (used during cold start before Firestore answers).
  Future<void> sanitizeSelection({bool allowPendingTitles = false}) async {
    await init();
    final id = selectedId.value;
    if (id == kAvatarUsePhotoId) return;
    final design = avatarDesignById(id);
    if (design == null) {
      await select(kAvatarUsePhotoId, pushToFirestore: true);
      return;
    }
    if (design.isTitleExclusive) {
      if (allowPendingTitles && !entitlementsReady.value) return;
      if (!isUnlocked(design)) {
        await select(kAvatarUsePhotoId, pushToFirestore: true);
      }
      return;
    }
    if (!isUnlocked(design)) {
      await select(kAvatarUsePhotoId, pushToFirestore: true);
    }
  }

  /// Clears #1 titles (e.g. on sign-out) so the next account never inherits them.
  Future<void> clearTitleEntitlements() async {
    entitlementsReady.value = true;
    ownedTitles.value = {};
    await sanitizeSelection();
  }

  /// [FirebaseAuth.instance] throws if no Firebase app exists yet (Firebase
  /// init still pending, skipped, or unavailable in a test sandbox) — treat
  /// that the same as "not signed in" rather than letting it propagate out
  /// of this method's `unawaited` call sites (see [AuthService._auth] for
  /// the same pattern).
  String? _currentFirebaseUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshTitleEntitlements() async {
    await init();
    final existing = _refreshInFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _refreshTitleEntitlementsBody();
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> _refreshTitleEntitlementsBody() async {
    final uid = _currentFirebaseUid();
    if (uid == null) {
      ownedTitles.value = {};
      entitlementsReady.value = true;
      await sanitizeSelection();
      return;
    }

    final owned = <AvatarExclusiveKind>{};
    Future<void> check({
      required String collection,
      required String orderField,
      required AvatarExclusiveKind kind,
    }) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .orderBy(orderField, descending: true)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) return;
        final top = snap.docs.first;
        if (top.id != uid) return;
        final data = top.data();
        // Require a positive score so an empty/zero stub doc cannot grant #1.
        final raw = data[orderField];
        final score = raw is num ? raw.toDouble() : 0;
        if (score <= 0) return;
        // Ranked boards seed a default rating — also require a win so idle
        // stub docs never unlock the crown.
        if (orderField == 'rating') {
          final wins = data['wins'];
          final winCount = wins is num ? wins.toDouble() : 0;
          if (winCount <= 0) return;
        }
        owned.add(kind);
      } catch (e, st) {
        // Fail closed for this board — do not grant the title.
        if (kDebugMode) {
          debugPrint(
            'Avatar title check failed ($collection / $orderField): $e\n$st',
          );
        }
      }
    }

    await Future.wait([
      check(
        collection: 'leaderboard_combos',
        orderField: 'comboCount',
        kind: AvatarExclusiveKind.comboKing,
      ),
      check(
        collection: 'ranked_stats',
        orderField: 'rating',
        kind: AvatarExclusiveKind.rankedCrown,
      ),
      check(
        collection: 'ranked_hardcore_stats',
        orderField: 'rating',
        kind: AvatarExclusiveKind.hardcoreCrown,
      ),
      check(
        collection: 'leaderboard_online',
        orderField: 'wins',
        kind: AvatarExclusiveKind.casualAce,
      ),
      check(
        collection: 'leaderboard_tournament_ai',
        orderField: 'wins',
        kind: AvatarExclusiveKind.tourneyAi,
      ),
      check(
        collection: 'leaderboard_tournament_online',
        orderField: 'wins',
        kind: AvatarExclusiveKind.tourneyOnline,
      ),
      check(
        collection: 'leaderboard_bust_online',
        orderField: 'wins',
        kind: AvatarExclusiveKind.bustOnline,
      ),
    ]);

    // If auth changed mid-flight, drop results for the stale uid.
    final still = FirebaseAuth.instance.currentUser?.uid;
    if (still != uid) return;

    ownedTitles.value = owned;
    entitlementsReady.value = true;
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
