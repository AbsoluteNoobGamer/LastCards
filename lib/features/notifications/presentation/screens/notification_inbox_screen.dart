import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/notification_inbox_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../data/notification_inbox_service.dart';

class NotificationInboxScreen extends ConsumerWidget {
  const NotificationInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final uid = ref.watch(authStateProvider).value?.uid;
    final notificationsAsync = ref.watch(notificationInboxProvider);

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundDeep,
        foregroundColor: theme.textPrimary,
        elevation: 0,
        title: const Text('NOTIFICATIONS'),
      ),
      body: uid == null
          ? _EmptyState(theme: theme, message: 'Sign in to see notifications.')
          : notificationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _EmptyState(
                theme: theme,
                message: "Couldn't load notifications. Try again later.",
              ),
              data: (notifications) {
                if (notifications.isEmpty) {
                  return _EmptyState(
                    theme: theme,
                    message: "You're all caught up.",
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _NotificationTile(
                    theme: theme,
                    uid: uid,
                    notification: notifications[index],
                  ),
                );
              },
            ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.theme,
    required this.uid,
    required this.notification,
  });

  final AppThemeData theme;
  final String uid;
  final InboxNotification notification;

  IconData get _icon => switch (notification.type) {
        'turn' => Icons.play_circle_fill_rounded,
        'challenge' => Icons.emoji_events_rounded,
        _ => Icons.campaign_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(notificationInboxServiceProvider);
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => service.delete(uid, notification.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: Material(
        color: notification.read
            ? theme.surfaceDark.withValues(alpha: 0.5)
            : theme.surfacePanel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (!notification.read) service.markRead(uid, notification.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, color: theme.accentPrimary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: notification.read ? FontWeight.w500 : FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(color: theme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (!notification.read)
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.secondaryAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme, required this.message});

  final AppThemeData theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.textSecondary, fontSize: 15),
        ),
      ),
    );
  }
}
