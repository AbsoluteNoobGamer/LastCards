import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_profile_service.dart';
import 'purchase_service.dart';

/// Permanent "unlocked early" entitlements for cosmetics outside the theme
/// system — card backs, joker covers, avatars, and reactions. An item lands
/// here when the player pays for it with coins or real money instead of
/// reaching its unlock level; level-based ownership is never stored (it's
/// always derived live from [PlayerLevelService]).
///
/// Mirrors how theme purchases persist ([ThemeService]/[ThemeNotifier]):
/// SharedPreferences for instant local truth, mirrored to the signed-in
/// user's `users/{uid}.unlockedCosmetics` map for cross-device sync
/// (union-merged on load — an unlock on any device sticks everywhere).
class CosmeticUnlockService {
  CosmeticUnlockService._();

  static final CosmeticUnlockService instance = CosmeticUnlockService._();

  static const String categoryCardBacks = 'cardBacks';
  static const String categoryJokers = 'jokers';
  static const String categoryAvatars = 'avatars';
  static const String categoryReactions = 'reactions';

  static const List<String> _categories = [
    categoryCardBacks,
    categoryJokers,
    categoryAvatars,
    categoryReactions,
  ];

  static String _prefsKey(String category) => 'cosmeticUnlocked_$category';

  /// Shared coin-price formula for unlocking a level-gated cosmetic early —
  /// same scaling the theme unlocks use (level × 15).
  static int coinCostForLevel(int unlockLevel) => unlockLevel * 15;

  final Map<String, Set<String>> _purchased = {
    for (final c in _categories) c: <String>{},
  };

  /// Bumped on every change — cheap single listenable for Locker tabs.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _initialized = false;
  StreamSubscription<User?>? _authSub;

  Set<String> idsFor(String category) => _purchased[category] ?? const {};

  bool isPurchased(String category, String id) =>
      _purchased[category]?.contains(id) ?? false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    for (final category in _categories) {
      _purchased[category] =
          (prefs.getStringList(_prefsKey(category)) ?? const []).toSet();
    }
    revision.value++;

    // Cash purchases complete asynchronously via the store — record the
    // entitlement when the grant lands. (Theme grants are consumed by
    // ThemeNotifier instead, which owns its own persistence.)
    PurchaseService.instance.lastCosmeticUnlockGrant
        .addListener(_onCosmeticUnlockGranted);

    // Cross-device sync: union-merge the remote set on sign-in. Guarded —
    // Firebase may be unavailable (tests, init failure).
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) unawaited(_syncFromFirestore(user.uid));
      });
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await _syncFromFirestore(uid);
    } catch (_) {
      // No Firebase — local prefs remain the sole source of truth.
    }
  }

  int _lastConsumedGrantNonce = 0;

  void _onCosmeticUnlockGranted() {
    final grant = PurchaseService.instance.lastCosmeticUnlockGrant.value;
    if (grant == null || grant.nonce <= _lastConsumedGrantNonce) return;
    if (!_categories.contains(grant.category)) return; // themes et al.
    _lastConsumedGrantNonce = grant.nonce;
    unawaited(markPurchased(grant.category, grant.itemId));
  }

  /// Records a permanent unlock. The caller is responsible for charging
  /// the player first (coins or a completed store purchase).
  Future<void> markPurchased(String category, String id) async {
    final set = _purchased[category];
    if (set == null || set.contains(id)) return;
    set.add(id);
    revision.value++;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(category), set.toList());
    await _pushToFirestore(category);
  }

  Future<void> _pushToFirestore(String category) async {
    final uid = _currentUid();
    if (uid == null) return;
    try {
      await FirestoreProfileService().updateUnlockedCosmetics(
        uid,
        category,
        _purchased[category]!.toList(),
      );
    } catch (_) {
      // Offline or rules rejection — local prefs remain source of truth;
      // the next sign-in sync retries.
    }
  }

  Future<void> _syncFromFirestore(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = snap.data()?['unlockedCosmetics'];
      if (raw is! Map) return;
      var changed = false;
      final prefs = await SharedPreferences.getInstance();
      for (final category in _categories) {
        final remote = raw[category];
        if (remote is! List) continue;
        final remoteIds = remote.whereType<String>().toSet();
        final local = _purchased[category]!;
        if (remoteIds.every(local.contains)) continue;
        // Union, never shrink — an unlock on any device sticks everywhere.
        local.addAll(remoteIds);
        await prefs.setStringList(_prefsKey(category), local.toList());
        changed = true;
      }
      if (changed) revision.value++;
    } catch (_) {
      // Offline or rules rejection — retried on the next sign-in.
    }
  }

  /// Null if signed out or Firebase was never initialized (tests).
  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Never called in production — exists so tests can tear down cleanly.
  void dispose() {
    _authSub?.cancel();
    PurchaseService.instance.lastCosmeticUnlockGrant
        .removeListener(_onCosmeticUnlockGranted);
  }
}
