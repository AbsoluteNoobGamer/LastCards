import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks player XP + derived level for local progression.
///
/// XP is persisted via SharedPreferences key `player_total_xp`.
///
/// Level unlocks use these thresholds (Level = threshold index + 1):
///   Level 1: 0 XP
///   Level 2: 100 XP
///   Level 3: 300 XP
///   Level 4: 600 XP
///   Level 5: 1000 XP
///   Level 6: 1500 XP
///   Level 7: 2100 XP
///   Level 8: 2800 XP
///   Level 9: 3600 XP
///   Level 10: 4500 XP
class PlayerLevelService {
  PlayerLevelService._();

  static final PlayerLevelService instance = PlayerLevelService._();

  static const String _prefsTotalXpKey = 'player_total_xp';

  // Thresholds in ascending order.
  static const List<int> _levelThresholds = <int>[
    0,
    100,
    300,
    600,
    1000,
    1500,
    2100,
    2800,
    3600,
    4500,
  ];

  bool _initialized = false;
  int _totalXp = 0;

  /// Persisted XP total.
  final ValueNotifier<int> currentXP = ValueNotifier<int>(0);

  /// Derived level (1–10 based on [_levelThresholds]).
  final ValueNotifier<int> currentLevel = ValueNotifier<int>(1);

  static int levelFromTotalXP(int totalXP) {
    final xp = math.max(0, totalXP);
    // level = first index where xp < nextThreshold, then clamp to 10.
    var level = 1;
    for (var i = 0; i < _levelThresholds.length; i++) {
      if (xp >= _levelThresholds[i]) level = i + 1;
    }
    return level.clamp(1, _levelThresholds.length);
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

  Future<void> awardWinXP() => awardXP(50);
  Future<void> awardLossXP() => awardXP(10);
  Future<void> awardTournamentWinXP() => awardXP(100);
}

