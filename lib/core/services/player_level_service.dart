import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks player XP + derived level for local progression.
///
/// XP is persisted via SharedPreferences key `player_total_xp`.
///
/// Level unlocks (Level = threshold index + 1):
///   Level 1:  0 XP      Level 11: 5 600 XP
///   Level 2:  100 XP    Level 12: 6 900 XP
///   Level 3:  300 XP    Level 13: 8 400 XP
///   Level 4:  600 XP    Level 14: 10 100 XP
///   Level 5:  1 000 XP  Level 15: 12 000 XP
///   Level 6:  1 500 XP  Level 16: 14 100 XP
///   Level 7:  2 100 XP  Level 17: 16 400 XP
///   Level 8:  2 800 XP  Level 18: 19 000 XP
///   Level 9:  3 600 XP  Level 19: 21 900 XP
///   Level 10: 4 500 XP  Level 20: 25 000 XP
class PlayerLevelService {
  PlayerLevelService._();

  static final PlayerLevelService instance = PlayerLevelService._();

  static const String _prefsTotalXpKey = 'player_total_xp';
  static const String _prefsCurrentStreakKey = 'player_current_streak';
  static const String _prefsBestStreakKey = 'player_best_streak';

  // Thresholds in ascending order (index + 1 = level).
  static const List<int> _levelThresholds = <int>[
    0,      // Level 1
    100,    // Level 2
    300,    // Level 3
    600,    // Level 4
    1000,   // Level 5
    1500,   // Level 6
    2100,   // Level 7
    2800,   // Level 8
    3600,   // Level 9
    4500,   // Level 10
    5600,   // Level 11
    6900,   // Level 12
    8400,   // Level 13
    10100,  // Level 14
    12000,  // Level 15
    14100,  // Level 16
    16400,  // Level 17
    19000,  // Level 18
    21900,  // Level 19
    25000,  // Level 20
  ];

  bool _initialized = false;
  int _totalXp = 0;

  /// Persisted XP total.
  final ValueNotifier<int> currentXP = ValueNotifier<int>(0);

  /// Derived level (1–20 based on [_levelThresholds]).
  final ValueNotifier<int> currentLevel = ValueNotifier<int>(1);

  /// Current consecutive win streak (resets on any loss).
  final ValueNotifier<int> currentStreak = ValueNotifier<int>(0);

  /// All-time best win streak.
  final ValueNotifier<int> bestStreak = ValueNotifier<int>(0);

  static int levelFromTotalXP(int totalXP) {
    final xp = math.max(0, totalXP);
    var level = 1;
    for (var i = 0; i < _levelThresholds.length; i++) {
      if (xp >= _levelThresholds[i]) level = i + 1;
    }
    return level.clamp(1, _levelThresholds.length);
  }

  /// Maximum achievable level.
  static int get maxLevel => _levelThresholds.length;

  /// XP interval for the current level band: `[bandStartXp, nextBandStartXp)` until max level.
  ///
  /// [progressFraction] is linear progress within that band (1.0 at max level).
  static ({
    double progressFraction,
    int bandStartXp,
    int? nextBandStartXp,
    int level,
  }) progressForTotalXp(int totalXP) {
    final xp = math.max(0, totalXP);
    final level = levelFromTotalXP(xp);
    final bandStart = _levelThresholds[level - 1];
    if (level >= _levelThresholds.length) {
      return (
        progressFraction: 1.0,
        bandStartXp: bandStart,
        nextBandStartXp: null,
        level: level,
      );
    }
    final nextStart = _levelThresholds[level];
    final span = nextStart - bandStart;
    final frac =
        span > 0 ? ((xp - bandStart) / span).clamp(0.0, 1.0) : 1.0;
    return (
      progressFraction: frac,
      bandStartXp: bandStart,
      nextBandStartXp: nextStart,
      level: level,
    );
  }

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _totalXp = prefs.getInt(_prefsTotalXpKey) ?? 0;
    currentXP.value = _totalXp;
    currentLevel.value = levelFromTotalXP(_totalXp);
    currentStreak.value = prefs.getInt(_prefsCurrentStreakKey) ?? 0;
    bestStreak.value = prefs.getInt(_prefsBestStreakKey) ?? 0;
    _initialized = true;
  }

  Future<void> awardXP(int delta) async {
    await init();
    if (delta == 0) return;

    // Disallow negative deltas from crashing progression; clamp at 0.
    final nextXp = math.max(0, _totalXp + delta);
    if (nextXp == _totalXp) return;

    _totalXp = nextXp;
    currentXP.value = _totalXp;

    final nextLevel = levelFromTotalXP(_totalXp);
    if (nextLevel != currentLevel.value) {
      currentLevel.value = nextLevel;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsTotalXpKey, _totalXp);
  }

  Future<void> awardWinXP() async {
    await awardXP(50);
    await _incrementStreak();
  }

  Future<void> awardLossXP() async {
    await awardXP(10);
    await _resetStreak();
  }

  Future<void> awardTournamentWinXP() async {
    await awardXP(100);
    await _incrementStreak();
  }

  Future<void> _incrementStreak() async {
    await init();
    final next = currentStreak.value + 1;
    currentStreak.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsCurrentStreakKey, next);
    if (next > bestStreak.value) {
      bestStreak.value = next;
      await prefs.setInt(_prefsBestStreakKey, next);
    }
  }

  Future<void> _resetStreak() async {
    await init();
    if (currentStreak.value == 0) return;
    currentStreak.value = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsCurrentStreakKey, 0);
  }
}

