import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/profile_service.dart';

// ── State model ───────────────────────────────────────────────────────────────

class ProfileState {
  final String name;
  final String? avatarPath;

  const ProfileState({
    required this.name,
    this.avatarPath,
  });

  ProfileState copyWith({String? name, String? avatarPath, bool clearAvatar = false}) {
    return ProfileState(
      name: name ?? this.name,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier(this._service)
      : super(const ProfileState(name: ProfileDefaults.name));

  final ProfileService _service;

  /// Loads the saved profile from SharedPreferences and updates state.
  Future<void> loadFromPrefs() async {
    final profile = await _service.loadProfile();
    state = ProfileState(name: profile.name, avatarPath: profile.avatarPath);
  }

  /// Saves the given name and avatar path to SharedPreferences and updates state.
  Future<void> updateProfile({
    required String name,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    await _service.saveProfile(
      name: name,
      avatarPath: clearAvatar ? null : avatarPath,
    );
    state = state.copyWith(
      name: name,
      avatarPath: clearAvatar ? null : avatarPath,
      clearAvatar: clearAvatar,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final profileServiceProvider = Provider<ProfileService>((_) => const ProfileService());

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(ref.read(profileServiceProvider));
});
