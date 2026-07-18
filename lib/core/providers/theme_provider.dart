import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme_data.dart';
import '../theme/app_themes.dart';
import '../services/theme_service.dart';
import '../services/analytics_service.dart';
import '../services/player_level_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class ThemeState {
  const ThemeState({required this.activeIndex, required this.theme});

  final int activeIndex;
  final AppThemeData theme;

  ThemeState copyWith({int? activeIndex, AppThemeData? theme}) {
    return ThemeState(
      activeIndex: activeIndex ?? this.activeIndex,
      theme: theme ?? this.theme,
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

  /// Loads the persisted theme index on app start.
  ///
  /// Falls back to the default theme if the persisted selection is a theme
  /// the player is no longer (or not yet) high enough level to have.
  Future<void> loadFromPrefs() async {
    var idx = (await _service.loadThemeIndex())
        .clamp(0, kAppThemes.length - 1);
    final level = PlayerLevelService.instance.currentLevel.value;
    if (kAppThemes[idx].minUnlockLevel > level) {
      idx = ThemeService.defaultThemeIndex;
    }
    state = ThemeState(activeIndex: idx, theme: kAppThemes[idx]);
  }

  /// Changes the active theme and persists the selection.
  Future<void> setTheme(int index) async {
    final idx = index.clamp(0, kAppThemes.length - 1);
    state = ThemeState(activeIndex: idx, theme: kAppThemes[idx]);
    await _service.saveThemeIndex(idx);
    AnalyticsService.instance.logThemeChanged(themeId: kAppThemes[idx].id);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final themeServiceProvider =
    Provider<ThemeService>((_) => const ThemeService());

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier(ref.read(themeServiceProvider));
});
