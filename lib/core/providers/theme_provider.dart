import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme_data.dart';
import '../theme/app_themes.dart';
import '../services/theme_service.dart';
import '../services/analytics_service.dart';
import '../services/firestore_profile_service.dart';
import '../services/player_level_service.dart';
import '../services/purchase_service.dart';
import 'user_profile_provider.dart' show firestoreProfileServiceProvider;

// ── State ─────────────────────────────────────────────────────────────────────

class ThemeState {
  const ThemeState({
    required this.activeIndex,
    required this.theme,
    this.trialThemeId,
    this.trialGamesRemaining,
    this.trialedThemeIds = const {},
    this.purchasedThemeIds = const {},
  });

  final int activeIndex;
  final AppThemeData theme;

  /// Non-null while the active theme is being trialed (below the player's
  /// unlock level, on borrowed games).
  final String? trialThemeId;
  final int? trialGamesRemaining;

  /// Theme ids whose one-shot trial has already been spent (started, win
  /// or lose) — the Locker uses this to stop offering a trial CTA on them.
  final Set<String> trialedThemeIds;

  /// Theme ids permanently unlocked outside the level-gate — via coins or a
  /// real-money cash purchase (both grant the same permanent entitlement).
  final Set<String> purchasedThemeIds;

  bool get isTrialActive => trialThemeId != null;

  /// True if [theme] can be equipped outright: reached by level, or
  /// permanently unlocked via [purchasedThemeIds].
  bool isUnlocked(AppThemeData theme, int level) =>
      theme.minUnlockLevel <= level || purchasedThemeIds.contains(theme.id);

  ThemeState copyWith({
    int? activeIndex,
    AppThemeData? theme,
    String? trialThemeId,
    int? trialGamesRemaining,
    Set<String>? trialedThemeIds,
    Set<String>? purchasedThemeIds,
    bool clearTrial = false,
  }) {
    return ThemeState(
      activeIndex: activeIndex ?? this.activeIndex,
      theme: theme ?? this.theme,
      trialThemeId: clearTrial ? null : (trialThemeId ?? this.trialThemeId),
      trialGamesRemaining:
          clearTrial ? null : (trialGamesRemaining ?? this.trialGamesRemaining),
      trialedThemeIds: trialedThemeIds ?? this.trialedThemeIds,
      purchasedThemeIds: purchasedThemeIds ?? this.purchasedThemeIds,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier(this._service, this._firestoreProfileServiceFactory)
      : super(ThemeState(
          activeIndex: ThemeService.defaultThemeIndex,
          theme: kAppThemes[ThemeService.defaultThemeIndex],
        ));

  final ThemeService _service;

  /// Lazy — constructing [FirestoreProfileService] touches
  /// `FirebaseFirestore.instance`, which throws if Firebase was never
  /// initialized (e.g. widget tests). Only resolved inside the try/catch
  /// blocks below, and only once we already know a user is signed in.
  final FirestoreProfileService Function() _firestoreProfileServiceFactory;

  bool _purchaseListenerAttached = false;
  int _lastConsumedThemeUnlockNonce = 0;

  /// Loads the persisted theme index (and any in-progress trial) on app start.
  ///
  /// Falls back to the default theme if the persisted selection is a theme
  /// the player is no longer (or not yet) high enough level to have and
  /// isn't covered by an in-progress trial.
  Future<void> loadFromPrefs() async {
    var idx = (await _service.loadThemeIndex())
        .clamp(0, kAppThemes.length - 1);
    final level = PlayerLevelService.instance.currentLevel.value;
    final trial = await _service.loadTrialState();
    final trialedIds = await _service.loadTrialedThemeIds();
    final isTrialingThisTheme =
        trial != null && trial.themeId == kAppThemes[idx].id;

    var purchasedIds = await _service.loadPurchasedThemeIds();
    final uid = _currentUid();
    if (uid != null) {
      final remoteIds = await _fetchRemotePurchasedThemeIds(uid);
      if (remoteIds != null && !remoteIds.every(purchasedIds.contains)) {
        // Union, never shrink — a theme unlocked on any device stays
        // unlocked everywhere.
        purchasedIds = {...purchasedIds, ...remoteIds};
        await _service.savePurchasedThemeIds(purchasedIds);
      }
    }

    final isPurchased = purchasedIds.contains(kAppThemes[idx].id);

    if (kAppThemes[idx].minUnlockLevel > level &&
        !isTrialingThisTheme &&
        !isPurchased) {
      idx = ThemeService.defaultThemeIndex;
      state = ThemeState(
        activeIndex: idx,
        theme: kAppThemes[idx],
        trialedThemeIds: trialedIds,
        purchasedThemeIds: purchasedIds,
      );
    } else {
      state = ThemeState(
        activeIndex: idx,
        theme: kAppThemes[idx],
        trialThemeId: isTrialingThisTheme ? trial.themeId : null,
        trialGamesRemaining: isTrialingThisTheme ? trial.gamesRemaining : null,
        trialedThemeIds: trialedIds,
        purchasedThemeIds: purchasedIds,
      );
    }

    if (!_purchaseListenerAttached) {
      _purchaseListenerAttached = true;
      PurchaseService.instance.lastCosmeticUnlockGrant
          .addListener(_onThemeUnlockGranted);
    }
  }

  /// Changes the active theme and persists the selection. Switching away
  /// from an in-progress trial forfeits it — trials are one-shot.
  Future<void> setTheme(int index) async {
    final idx = index.clamp(0, kAppThemes.length - 1);
    if (state.isTrialActive && kAppThemes[idx].id != state.trialThemeId) {
      await _service.saveTrialState(null);
    }
    state = ThemeState(
      activeIndex: idx,
      theme: kAppThemes[idx],
      trialedThemeIds: state.trialedThemeIds,
      purchasedThemeIds: state.purchasedThemeIds,
    );
    await _service.saveThemeIndex(idx);
    AnalyticsService.instance.logThemeChanged(themeId: kAppThemes[idx].id);
  }

  /// Equips a below-level theme on a one-shot trial: [AppThemeData.trialGames]
  /// completed games (any mode) before it auto-reverts to whatever was
  /// active beforehand. No-ops if this theme has no trial or was already
  /// trialed once.
  Future<void> startTrial(int index) async {
    final idx = index.clamp(0, kAppThemes.length - 1);
    final theme = kAppThemes[idx];
    final trialGames = theme.trialGames;
    if (trialGames == null) return;
    if ((await _service.loadTrialedThemeIds()).contains(theme.id)) return;

    final revertThemeId = state.theme.id;
    final trial = ThemeTrialState(
      themeId: theme.id,
      gamesRemaining: trialGames,
      revertThemeId: revertThemeId,
    );
    await _service.saveTrialState(trial);
    await _service.markThemeTrialed(theme.id);
    await _service.saveThemeIndex(idx);
    state = ThemeState(
      activeIndex: idx,
      theme: theme,
      trialThemeId: trial.themeId,
      trialGamesRemaining: trial.gamesRemaining,
      trialedThemeIds: {...state.trialedThemeIds, theme.id},
      purchasedThemeIds: state.purchasedThemeIds,
    );
    AnalyticsService.instance.logThemeChanged(themeId: theme.id);
  }

  /// Adds [extraGames] to an already-active trial (e.g. paid for with coins
  /// by the caller — this method only extends the trial itself, it doesn't
  /// touch the wallet). No-ops if no trial is active.
  Future<void> extendActiveTrial(int extraGames) async {
    if (!state.isTrialActive) return;
    final current = await _service.loadTrialState();
    if (current == null) return;
    final extended = current.copyWith(
      gamesRemaining: current.gamesRemaining + extraGames,
    );
    await _service.saveTrialState(extended);
    state = state.copyWith(trialGamesRemaining: extended.gamesRemaining);
  }

  /// Permanently unlocks [index] outside the level-gate. The caller is
  /// responsible for actually charging the player (coins or cash) before
  /// calling this — it only records the entitlement. No-ops if already
  /// unlocked by level or a prior purchase.
  Future<void> unlockThemePermanently(int index) async {
    final idx = index.clamp(0, kAppThemes.length - 1);
    final theme = kAppThemes[idx];
    final level = PlayerLevelService.instance.currentLevel.value;
    if (state.isUnlocked(theme, level)) return;

    final updated = {...state.purchasedThemeIds, theme.id};
    await _service.savePurchasedThemeIds(updated);
    state = state.copyWith(purchasedThemeIds: updated);
    unawaited(_syncPurchasedThemeIdsToFirestore(updated));
    AnalyticsService.instance.logThemeChanged(themeId: theme.id);
  }

  /// True if [theme] is next in line for a cash unlock: every earlier theme
  /// in [kAppThemes]' level order (up to [theme]) is already owned by level,
  /// coins, or a prior cash purchase. Keeps progression intact for paying
  /// users — no buying your way past themes you haven't reached yet.
  bool canCashUnlock(AppThemeData theme) {
    if (theme.cashUnlockProductId == null) return false;
    final level = PlayerLevelService.instance.currentLevel.value;
    final index = kAppThemes.indexWhere((t) => t.id == theme.id);
    for (var i = 0; i < index; i++) {
      final earlier = kAppThemes[i];
      // Only earlier themes actually in this cash-unlock ladder count —
      // free default themes (e.g. Arena Neon, appended after the ladder)
      // don't gate anything.
      if (earlier.cashUnlockProductId == null &&
          earlier.coinUnlockCost == null) {
        continue;
      }
      if (!state.isUnlocked(earlier, level)) return false;
    }
    return true;
  }

  void _onThemeUnlockGranted() {
    final grant = PurchaseService.instance.lastCosmeticUnlockGrant.value;
    if (grant == null || grant.nonce <= _lastConsumedThemeUnlockNonce) return;
    if (grant.category != 'themes') return;
    _lastConsumedThemeUnlockNonce = grant.nonce;
    final idx = kAppThemes.indexWhere((t) => t.id == grant.itemId);
    if (idx >= 0) unawaited(unlockThemePermanently(idx));
  }

  Future<void> _syncPurchasedThemeIdsToFirestore(Set<String> ids) async {
    final uid = _currentUid();
    if (uid == null) return;
    try {
      await _firestoreProfileServiceFactory()
          .updateUnlockedThemeIds(uid, ids.toList());
    } catch (_) {
      // Offline, rules rejection, or Firebase never initialized (tests) —
      // local cache remains source of truth; the next loadFromPrefs()
      // reconciliation will retry.
    }
  }

  Future<Set<String>?> _fetchRemotePurchasedThemeIds(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = snap.data()?['unlockedThemeIds'];
      if (raw is! List) return null;
      return raw.whereType<String>().toSet();
    } catch (_) {
      return null;
    }
  }

  /// Null if signed out, or if Firebase hasn't been initialized (e.g. widget
  /// tests that never call `Firebase.initializeApp()`) — never let a missing
  /// plugin binding throw out of an earning hook mid-game.
  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Call once per completed game (any mode). No-ops unless a trial is
  /// active; reverts to the pre-trial theme once games run out.
  Future<void> recordGameCompleted() async {
    if (!state.isTrialActive) return;
    final remaining = (state.trialGamesRemaining ?? 1) - 1;
    if (remaining <= 0) {
      final trial = await _service.loadTrialState();
      await _service.saveTrialState(null);
      var revertIdx = ThemeService.defaultThemeIndex;
      if (trial != null) {
        final found = kAppThemes.indexWhere((t) => t.id == trial.revertThemeId);
        if (found >= 0) revertIdx = found;
      }
      state = ThemeState(
        activeIndex: revertIdx,
        theme: kAppThemes[revertIdx],
        trialedThemeIds: state.trialedThemeIds,
        purchasedThemeIds: state.purchasedThemeIds,
      );
      await _service.saveThemeIndex(revertIdx);
      return;
    }
    await _service.saveTrialState(
      ThemeTrialState(
        themeId: state.trialThemeId!,
        gamesRemaining: remaining,
        revertThemeId: (await _service.loadTrialState())!.revertThemeId,
      ),
    );
    state = state.copyWith(trialGamesRemaining: remaining);
  }

  @override
  void dispose() {
    if (_purchaseListenerAttached) {
      PurchaseService.instance.lastCosmeticUnlockGrant
          .removeListener(_onThemeUnlockGranted);
    }
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final themeServiceProvider =
    Provider<ThemeService>((_) => const ThemeService());

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier(
    ref.read(themeServiceProvider),
    () => ref.read(firestoreProfileServiceProvider),
  );
});
