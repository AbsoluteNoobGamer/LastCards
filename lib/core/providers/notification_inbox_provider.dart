import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/data/notification_inbox_service.dart';
import 'auth_provider.dart';

final notificationInboxServiceProvider =
    Provider<NotificationInboxService>((_) => NotificationInboxService());

/// Streams the signed-in user's notification inbox; empty (not loading
/// forever) when signed out or Firebase isn't initialized (e.g. tests that
/// mock Firebase Auth without a real Firebase Core app — [notificationInboxServiceProvider]
/// touches `FirebaseFirestore.instance`, which throws in that case), since
/// there's nothing to fetch either way.
final notificationInboxProvider =
    StreamProvider.autoDispose<List<InboxNotification>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || Firebase.apps.isEmpty) {
    return Stream.value(const <InboxNotification>[]);
  }
  final service = ref.watch(notificationInboxServiceProvider);
  return service.streamForUser(user.uid);
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationInboxProvider).valueOrNull ?? const [];
  return notifications.where((n) => !n.read).length;
});
