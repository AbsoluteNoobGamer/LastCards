import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/currency_service.dart';
import '../services/firestore_profile_service.dart';
import '../services/player_level_service.dart';
import 'user_profile_provider.dart' show firestoreProfileServiceProvider;

// ── Reward amounts ───────────────────────────────────────────────────────────

/// Coin amounts for every way a player can earn currency. Kept together so
/// balance tuning doesn't require hunting across every call site.
abstract final class CurrencyRewards {
  static const int matchWin = 15;
  static const int matchLoss = 5;
  static const int bustRoundSurvive = 5;
  static const int bustRoundEliminated = 2;
  static const int tournamentRound = 8;
  static const int tournamentWin = 50;

  /// Per level gained (a multi-level jump from a large XP award pays out
  /// proportionally).
  static const int perLevelUp = 20;

  static const int dailyRewardBase = 10;

  /// Added per extra consecutive day, capped at [dailyStreakCapDays] days'
  /// worth of bonus so the reward doesn't grow unbounded.
  static const int dailyStreakBonusPerDay = 5;
  static const int dailyStreakCapDays = 7;

  static int dailyRewardForStreak(int streak) {
    final bonusDays = (streak - 1).clamp(0, dailyStreakCapDays - 1);
    return dailyRewardBase + dailyStreakBonusPerDay * bonusDays;
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class CurrencyState {
  const CurrencyState({this.balance = 0, this.walletVersion = 0});

  final int balance;

  /// Local cache of the last known server wallet-mutation counter — see
  /// [CurrencyService.loadWalletVersion].
  final int walletVersion;

  CurrencyState copyWith({int? balance, int? walletVersion}) => CurrencyState(
        balance: balance ?? this.balance,
        walletVersion: walletVersion ?? this.walletVersion,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CurrencyNotifier extends StateNotifier<CurrencyState> {
  CurrencyNotifier(this._service, this._firestoreProfileServiceFactory)
      : super(const CurrencyState());

  final CurrencyService _service;

  /// Lazy — constructing [FirestoreProfileService] touches
  /// `FirebaseFirestore.instance`, which throws if Firebase was never
  /// initialized (e.g. widget tests). Only resolved inside the try/catch
  /// blocks below, and only once we already know a user is signed in.
  final FirestoreProfileService Function() _firestoreProfileServiceFactory;

  static const _usersCollection = 'users';

  int? _lastRewardedLevel;
  bool _levelListenerAttached = false;

  /// Loads the persisted balance on app start, reconciles with the signed-in
  /// player's Firestore doc (cross-device sync), and arms the level-up
  /// reward listener. Safe to call multiple times.
  Future<void> loadFromPrefs() async {
    final localBalance = await _service.loadBalance();
    final localWalletVersion = await _service.loadWalletVersion();
    state = state.copyWith(
      balance: localBalance,
      walletVersion: localWalletVersion,
    );

    final uid = _currentUid();
    if (uid != null) {
      final remote = await _fetchRemoteWallet(uid);
      if (remote != null) {
        if (remote.walletVersion > localWalletVersion) {
          // A server-authoritative mutation (e.g. a settled wager) landed
          // since our last sync — trust it outright, even if it's a
          // decrease, rather than the max-of-two logic below silently
          // undoing a legitimate loss with a stale higher local cache.
          await applyServerBalance(
            remote.balance,
            walletVersion: remote.walletVersion,
          );
        } else if (remote.balance != localBalance) {
          // No server-authoritative delta since last sync — take whichever
          // is higher, to avoid losing coins earned offline on either this
          // device or another one.
          final reconciled =
              remote.balance > localBalance ? remote.balance : localBalance;
          state = state.copyWith(balance: reconciled);
          await _persist(reconciled, uid: uid);
        }
      }
    }

    // Establish the level-up reward baseline once: on the very first run of
    // this feature, don't retroactively pay out for levels already earned
    // before currency existed.
    await PlayerLevelService.instance.init();
    _lastRewardedLevel = await _service.loadLastRewardedLevel();
    if (_lastRewardedLevel == null) {
      _lastRewardedLevel = PlayerLevelService.instance.currentLevel.value;
      await _service.saveLastRewardedLevel(_lastRewardedLevel!);
    }

    if (!_levelListenerAttached) {
      _levelListenerAttached = true;
      PlayerLevelService.instance.currentLevel.addListener(_onLevelChanged);
    }
  }

  void _onLevelChanged() {
    final newLevel = PlayerLevelService.instance.currentLevel.value;
    final last = _lastRewardedLevel ?? newLevel;
    if (newLevel <= last) return;
    final levelsGained = newLevel - last;
    _lastRewardedLevel = newLevel;
    unawaited(_service.saveLastRewardedLevel(newLevel));
    unawaited(addCoins(CurrencyRewards.perLevelUp * levelsGained));
  }

  /// Credits [amount] coins and persists locally + to Firestore (if signed
  /// in). Call this from every earning hook (match completion, tournament
  /// rounds, daily reward, etc).
  Future<void> addCoins(int amount) async {
    if (amount <= 0) return;
    final next = state.balance + amount;
    state = state.copyWith(balance: next);
    await _persist(next);
  }

  /// Attempts to deduct [amount] coins. Returns false (no-op) if the balance
  /// is insufficient.
  Future<bool> spendCoins(int amount) async {
    if (amount <= 0) return true;
    if (state.balance < amount) return false;
    final next = state.balance - amount;
    state = state.copyWith(balance: next);
    await _persist(next);
    return true;
  }

  /// Grants the once-per-calendar-day login reward if it hasn't been claimed
  /// today, updating the consecutive-day streak. Returns the amount awarded
  /// (0 if already claimed today). Call on start-screen load.
  Future<int> claimDailyRewardIfDue() async {
    final today = _epochDay(DateTime.now());
    final saved = await _service.loadDailyRewardState();
    if (saved.epochDay == today) return 0;

    final isConsecutive = saved.epochDay != null && today - saved.epochDay! == 1;
    final streak = isConsecutive ? saved.streak + 1 : 1;
    final reward = CurrencyRewards.dailyRewardForStreak(streak);

    await _service.saveDailyRewardState(epochDay: today, streak: streak);
    await addCoins(reward);
    return reward;
  }

  /// Applies an already-known server-authoritative (balance, walletVersion)
  /// pair — e.g. from [loadFromPrefs]'s own reconciliation read. Persists to
  /// the LOCAL cache only: the server already wrote Firestore directly via
  /// its own service-account path, so a client re-write here would be
  /// redundant, and a no-op if [walletVersion] isn't newer than what's cached
  /// (stale/out-of-order call).
  Future<void> applyServerBalance(
    int balance, {
    required int walletVersion,
  }) async {
    if (walletVersion <= state.walletVersion) return;
    state = state.copyWith(balance: balance, walletVersion: walletVersion);
    await _service.saveBalance(balance);
    await _service.saveWalletVersion(walletVersion);
  }

  /// Applies the local player's net coin delta from a settled wager
  /// (`wager_settled`, arrived over the game WebSocket this session). The
  /// server already applied the equivalent change directly to Firestore —
  /// this only updates the local cache so the balance chip / win dialog
  /// reflect it immediately, without a redundant client-side Firestore write.
  ///
  /// Unlike [applyServerBalance] this has no walletVersion to compare (the
  /// event only carries a delta, not the resulting counter) — safe because
  /// it's applied at most once per match, right when the delta arrives.
  Future<void> applyWagerDelta(int delta) async {
    if (delta == 0) return;
    final next = state.balance + delta;
    state = state.copyWith(balance: next);
    await _service.saveBalance(next);
  }

  int _epochDay(DateTime time) =>
      DateTime(time.year, time.month, time.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  Future<void> _persist(int balance, {String? uid}) async {
    await _service.saveBalance(balance);
    final resolvedUid = uid ?? _currentUid();
    if (resolvedUid == null) return;
    try {
      await _firestoreProfileServiceFactory().updateCoins(resolvedUid, balance);
    } catch (_) {
      // Offline, rules rejection, or Firebase never initialized (tests) —
      // local cache remains source of truth; the next loadFromPrefs()
      // reconciliation will retry.
    }
  }

  Future<({int balance, int walletVersion})?> _fetchRemoteWallet(
    String uid,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(uid)
          .get();
      final data = snap.data();
      final coins = data?['coins'];
      final balance = coins is int ? coins : (coins as num?)?.toInt();
      if (balance == null) return null;
      final version = data?['walletVersion'];
      final walletVersion =
          version is int ? version : (version as num?)?.toInt() ?? 0;
      return (balance: balance, walletVersion: walletVersion);
    } catch (_) {
      return null;
    }
  }

  /// Null if signed out, or if Firebase hasn't been initialized (e.g. widget
  /// tests that never call `Firebase.initializeApp()`) — never let a missing
  /// plugin binding throw out of an `unawaited()` earning hook mid-game.
  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    if (_levelListenerAttached) {
      PlayerLevelService.instance.currentLevel.removeListener(_onLevelChanged);
    }
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final currencyServiceProvider =
    Provider<CurrencyService>((_) => const CurrencyService());

final currencyProvider =
    StateNotifierProvider<CurrencyNotifier, CurrencyState>((ref) {
  return CurrencyNotifier(
    ref.read(currencyServiceProvider),
    () => ref.read(firestoreProfileServiceProvider),
  );
});
