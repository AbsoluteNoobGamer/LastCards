import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks player XP + derived level for local progression.
///
/// XP is persisted via SharedPreferences key `player_total_xp`.
///
/// Levels 1–20 use fixed thresholds (see [_levelThresholds]). Levels 21–100 add
/// [_post20XpPerLevel] XP per level after level 20’s threshold (25 000 XP).
///
/// [prestigeAvatarUnlockLevel] is the level at which the prestige avatar frame
/// unlocks (currently 100).
class PlayerLevelService {
  PlayerLevelService._();

  static final PlayerLevelService instance = PlayerLevelService._();

  static const String _prefsTotalXpKey = 'player_total_xp';
  static const String _prefsCurrentStreakKey = 'player_current_streak';
  static const String _prefsBestStreakKey = 'player_best_streak';

  /// XP added per level after the first 20 levels (linear segment).
  static const int _post20XpPerLevel = 5000;

  /// First 20 levels: threshold to *reach* that level (index + 1 = level).
  static const List<int> _levelThresholds = <int>[
    0, // Level 1
    100, // Level 2
    300, // Level 3
    600, // Level 4
    1000, // Level 5
    1500, // Level 6
    2100, // Level 7
    2800, // Level 8
    3600, // Level 9
    4500, // Level 10
    5600, // Level 11
    6900, // Level 12
    8400, // Level 13
    10100, // Level 14
    12000, // Level 15
    14100, // Level 16
    16400, // Level 17
    19000, // Level 18
    21900, // Level 19
    25000, // Level 20
  ];

  /// Maximum achievable level (inclusive).
  static const int maxLevel = 100;

  /// Level at which the animated prestige avatar frame unlocks.
  static const int prestigeAvatarUnlockLevel = 100;

  bool _initialized = false;
  int _totalXp = 0;

  /// Persisted XP total.
  final ValueNotifier<int> currentXP = ValueNotifier<int>(0);

  /// Derived level (1–[maxLevel]).
  final ValueNotifier<int> currentLevel = ValueNotifier<int>(1);

  /// Current consecutive win streak (resets on any loss).
  final ValueNotifier<int> currentStreak = ValueNotifier<int>(0);

  /// All-time best win streak.
  final ValueNotifier<int> bestStreak = ValueNotifier<int>(0);

  /// Minimum total XP required to be considered at least [level] (level ≥ 1).
  static int xpThresholdForLevel(int level) {
    final l = level.clamp(1, maxLevel);
    if (l <= _levelThresholds.length) {
      return _levelThresholds[l - 1];
    }
    final base = _levelThresholds.last;
    return base + (l - _levelThresholds.length) * _post20XpPerLevel;
  }

  static int levelFromTotalXP(int totalXP) {
    final xp = math.max(0, totalXP);
    var level = 1;
    for (var l = 1; l <= maxLevel; l++) {
      if (xp >= xpThresholdForLevel(l)) level = l;
    }
    return level;
  }

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
    final bandStart = xpThresholdForLevel(level);
    if (level >= maxLevel) {
      return (
        progressFraction: 1.0,
        bandStartXp: bandStart,
        nextBandStartXp: null,
        level: level,
      );
    }
    final nextStart = xpThresholdForLevel(level + 1);
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
