import 'package:shared_preferences/shared_preferences.dart';

/// Persists the active theme index to [SharedPreferences].
class ThemeService {
  static const _key = 'activeThemeIndex';

  const ThemeService();

  Future<int> loadThemeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0; // default: Classic Felt
  }

  Future<void> saveThemeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, index);
  }
}
