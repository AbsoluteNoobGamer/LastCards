import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firestore_profile_service.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';

/// Merged profile: Firestore overrides auth. Used for badge, sheet, display name.
class UserProfile {
  final String displayName;
  final String? avatarUrl;

  const UserProfile({required this.displayName, this.avatarUrl});
}

/// Firestore profile service. Use for updateProfile, uploadAvatar, clearAvatar.
final firestoreProfileServiceProvider =
    Provider<FirestoreProfileService>((_) => FirestoreProfileService());

/// Streams merged profile (Firestore + auth fallbacks). No email.
final userProfileProvider = StreamProvider<UserProfile>((ref) async* {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    yield const UserProfile(displayName: 'Guest');
    return;
  }

  final authDisplayName = user.displayName?.trim().isNotEmpty == true
      ? user.displayName!
      : user.email?.split('@').first;
  final authAvatarUrl = user.photoURL;

  final service = ref.read(firestoreProfileServiceProvider);
  await for (final firestore in service.profileStream(user)) {
    final displayName = firestore != null &&
            firestore.displayName.trim().isNotEmpty
        ? firestore.displayName
        : (authDisplayName ?? 'Guest');
    final avatarUrl = firestore?.avatarUrl ?? authAvatarUrl;
    yield UserProfile(displayName: displayName, avatarUrl: avatarUrl);
  }
});

/// Display name for lobby/game. When signed in: merged Firestore profile.
/// When no auth: profileProvider.name. Defaults to 'Player' when loading.
final displayNameForGameProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return ref.watch(profileProvider).name;
  }
  final profile = ref.watch(userProfileProvider);
  return profile.when(
    data: (p) => p.displayName,
    loading: () => 'Player',
    error: (_, __) => 'Player',
  );
});
