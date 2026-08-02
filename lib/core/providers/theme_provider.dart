import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme_data.dart';
import '../theme/app_themes.dart';
import '../services/theme_service.dart';
import '../services/analytics_service.dart';
import '../services/player_level_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class ThemeState {
  const ThemeState({
    required this.activeIndex,
    required this.theme,
    this.trialThemeId,
    this.trialGamesRemaining,
    this.trialedThemeIds = const {},
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

  bool get isTrialActive => trialThemeId != null;

  ThemeState copyWith({
    int? activeIndex,
    AppThemeData? theme,
    String? trialThemeId,
    int? trialGamesRemaining,
    Set<String>? trialedThemeIds,
    bool clearTrial = false,
  }) {
    return ThemeState(
      activeIndex: activeIndex ?? this.activeIndex,
      theme: theme ?? this.theme,
      trialThemeId: clearTrial ? null : (trialThemeId ?? this.trialThemeId),
      trialGamesRemaining:
          clearTrial ? null : (trialGamesRemaining ?? this.trialGamesRemaining),
      trialedThemeIds: trialedThemeIds ?? this.trialedThemeIds,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier(this._service)
      : super(ThemeState(
          activeIndex: ThemeService.defaultThemeIndex,
          theme: kAppThemes[ThemeService.defaultThemeIndex],
        ));

  final ThemeService _service;

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

    if (kAppThemes[idx].minUnlockLevel > level && !isTrialingThisTheme) {
      idx = ThemeService.defaultThemeIndex;
      state = ThemeState(
        activeIndex: idx,
        theme: kAppThemes[idx],
        trialedThemeIds: trialedIds,
      );
      return;
    }

    state = ThemeState(
      activeIndex: idx,
      theme: kAppThemes[idx],
      trialThemeId: isTrialingThisTheme ? trial.themeId : null,
      trialGamesRemaining: isTrialingThisTheme ? trial.gamesRemaining : null,
      trialedThemeIds: trialedIds,
    );
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
    );
    AnalyticsService.instance.logThemeChanged(themeId: theme.id);
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
}

// ── Providers ─────────────────────────────────────────────────────────────────

final themeServiceProvider =
    Provider<ThemeService>((_) => const ThemeService());

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier(ref.read(themeServiceProvider));
});
