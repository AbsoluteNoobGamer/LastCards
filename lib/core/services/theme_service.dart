import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_themes.dart';

/// Persists the active theme index to [SharedPreferences].
class ThemeService {
  static const _key = 'activeThemeIndex';

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
}
