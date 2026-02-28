import 'package:shared_preferences/shared_preferences.dart';

/// Keys used to persist profile data in SharedPreferences.
abstract final class _Keys {
  static const String name = 'profile_name';
  static const String avatarPath = 'profile_avatar_path';
}

/// Default values for a new local player profile.
abstract final class ProfileDefaults {
  static const String name = 'Noob 1';
}

/// Service layer for loading and saving the local player profile.
///
/// All data is persisted using SharedPreferences with string keys.
/// This class is stateless — consumers should use [ProfileProvider] for
/// reactive state management.
class ProfileService {
  const ProfileService();

  /// On first launch (no saved name), writes [ProfileDefaults.name] and a null
  /// avatar path so subsequent launches always have a value to load.
  ///
  /// Does nothing if a profile already exists.
  Future<void> initDefaultIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_Keys.name)) {
      await prefs.setString(_Keys.name, ProfileDefaults.name);
      // Avatar path is intentionally not written — absence means default icon.
    }
  }

  /// Loads the saved profile from SharedPreferences.
  ///
  /// Returns the saved name (defaulting to [ProfileDefaults.name] as a safety
  /// fallback) and the avatar file path (null if no custom avatar is set).
  Future<({String name, String? avatarPath})> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_Keys.name) ?? ProfileDefaults.name;
    final avatarPath = prefs.getString(_Keys.avatarPath);
    return (name: name, avatarPath: avatarPath);
  }

  /// Persists the given [name] and [avatarPath] to SharedPreferences.
  ///
  /// [avatarPath] may be null to clear a previously saved avatar.
  Future<void> saveProfile({
    required String name,
    String? avatarPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.name, name);
    if (avatarPath != null) {
      await prefs.setString(_Keys.avatarPath, avatarPath);
    } else {
      await prefs.remove(_Keys.avatarPath);
    }
  }
}
