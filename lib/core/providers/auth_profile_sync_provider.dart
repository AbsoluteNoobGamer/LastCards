import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'user_profile_provider.dart';

/// Keeps `users/{uid}` display name / avatar in sync with Firebase Auth when
/// Firestore is empty, so other players see real names in friends lists.
final authProfileSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<User?>>(authStateProvider, (_, next) {
    final user = next.valueOrNull;
    if (user == null) return;
    unawaited(
      ref.read(firestoreProfileServiceProvider).syncAuthToPublicProfileIfNeeded(
            user,
          ),
    );
  }, fireImmediately: true);
});
