import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_themes.dart';

/// A theme trial in progress: [themeId] is equipped and reverts to
/// [revertThemeId] once [gamesRemaining] completed games run out.
class ThemeTrialState {
  const ThemeTrialState({
    required this.themeId,
    required this.gamesRemaining,
    required this.revertThemeId,
  });

  final String themeId;
  final int gamesRemaining;
  final String revertThemeId;

  ThemeTrialState copyWith({int? gamesRemaining}) => ThemeTrialState(
        themeId: themeId,
        gamesRemaining: gamesRemaining ?? this.gamesRemaining,
        revertThemeId: revertThemeId,
      );
}

/// Persists the active theme index and any in-progress theme trial to
/// [SharedPreferences].
class ThemeService {
  static const _key = 'activeThemeIndex';
  static const _trialThemeIdKey = 'themeTrialThemeId';
  static const _trialGamesRemainingKey = 'themeTrialGamesRemaining';
  static const _trialRevertThemeIdKey = 'themeTrialRevertThemeId';
  static const _trialedThemeIdsKey = 'themeTrialedThemeIds';
  static const _purchasedThemeIdsKey = 'themePurchasedIds';

  const ThemeService();

  /// Default when the player has never picked a theme: Arena Neon.
  static int get defaultThemeIndex {
    final i = kAppThemes.indexWhere((t) => t.id == 'arena_neon');
    return i >= 0 ? i : 0;
  }

  Future<int> loadThemeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? defaultThemeIndex;
  }

  Future<void> saveThemeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, index);
  }

  /// Null when no trial is currently in progress.
  Future<ThemeTrialState?> loadTrialState() async {
    final prefs = await SharedPreferences.getInstance();
    final themeId = prefs.getString(_trialThemeIdKey);
    final revertThemeId = prefs.getString(_trialRevertThemeIdKey);
    final gamesRemaining = prefs.getInt(_trialGamesRemainingKey);
    if (themeId == null || revertThemeId == null || gamesRemaining == null) {
      return null;
    }
    return ThemeTrialState(
      themeId: themeId,
      gamesRemaining: gamesRemaining,
      revertThemeId: revertThemeId,
    );
  }

  /// Pass null to clear the in-progress trial (expired or abandoned).
  Future<void> saveTrialState(ThemeTrialState? trial) async {
    final prefs = await SharedPreferences.getInstance();
    if (trial == null) {
      await prefs.remove(_trialThemeIdKey);
      await prefs.remove(_trialGamesRemainingKey);
      await prefs.remove(_trialRevertThemeIdKey);
      return;
    }
    await prefs.setString(_trialThemeIdKey, trial.themeId);
    await prefs.setInt(_trialGamesRemainingKey, trial.gamesRemaining);
    await prefs.setString(_trialRevertThemeIdKey, trial.revertThemeId);
  }

  /// Theme ids whose one-shot trial has already been started (win or lose,
  /// finished or abandoned — a trial is spent the moment it starts).
  Future<Set<String>> loadTrialedThemeIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_trialedThemeIdsKey) ?? const []).toSet();
  }

  Future<void> markThemeTrialed(String themeId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_trialedThemeIdsKey) ?? const []).toSet()
      ..add(themeId);
    await prefs.setStringList(_trialedThemeIdsKey, ids.toList());
  }

  /// Theme ids permanently unlocked outside the level-gate — via coins or a
  /// real-money cash purchase (both grant the same permanent entitlement).
  Future<Set<String>> loadPurchasedThemeIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_purchasedThemeIdsKey) ?? const []).toSet();
  }

  Future<void> savePurchasedThemeIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_purchasedThemeIdsKey, ids.toList());
  }
}
