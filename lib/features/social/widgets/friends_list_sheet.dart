import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/navigation/app_page_routes.dart';
import '../../../core/providers/friends_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/firestore_profile_service.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../lobby/presentation/screens/lobby_screen.dart';
import 'other_player_profile_sheet.dart';

/// Start-menu sheet: lists accepted friends, remove, and shortcut to lobby for in-app invites.
class FriendsListSheet extends ConsumerWidget {
  const FriendsListSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final friendsAsync = ref.watch(friendUidListProvider);
    final profileService = ref.watch(firestoreProfileServiceProvider);
    final friendsService = ref.watch(friendsServiceProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Friends',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'To send an in-app room invite, open the online lobby with a room '
              'code, then tap FRIENDS there.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(
                  AppPageRoutes.fadeSlide((_) => const LobbyScreen()),
                );
              },
              icon:
                  Icon(Icons.meeting_room_rounded, color: theme.accentPrimary),
              label: Text(
                'Open online lobby',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: theme.accentPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            friendsAsync.when(
              data: (uids) {
                if (uids.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No friends yet. Tap another player’s avatar during an '
                      'online game to send a friend request.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: theme.textSecondary,
                      ),
                    ),
                  );
                }
                return SizedBox(
                  height: 280,
                  child: ListView.separated(
                    itemCount: uids.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final uid = uids[i];
                      return FutureBuilder<FirestoreUserProfile?>(
                        future: profileService.getProfileForUid(uid),
                        builder: (context, snap) {
                          final name =
                              snap.data?.displayName.trim().isNotEmpty == true
                                  ? snap.data!.displayName
                                  : uid.substring(0, uid.length.clamp(0, 8));
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color:
                                    theme.accentPrimary.withValues(alpha: 0.35),
                              ),
                            ),
                            onTap: () {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (ctx) => OtherPlayerProfileSheet(
                                  firebaseUid: uid,
                                  fallbackDisplayName: name,
                                ),
                              );
                            },
                            leading: CircleAvatar(
                              backgroundColor: theme.surfacePanel,
                              backgroundImage: snap.data?.avatarUrl != null
                                  ? NetworkImage(snap.data!.avatarUrl!)
                                  : null,
                              child: snap.data?.avatarUrl == null
                                  ? Icon(Icons.person_rounded,
                                      color: theme.accentPrimary)
                                  : null,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: theme.accentPrimary,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove friend',
                              icon: Icon(
                                Icons.person_remove_outlined,
                                color: theme.textSecondary,
                              ),
                              onPressed: () async {
                                final remove = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remove friend?'),
                                    content: Text(
                                      '$name will be removed from your friends list.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (remove != true || !context.mounted) return;
                                try {
                                  await friendsService.removeFriend(uid);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('$name removed'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Could not remove: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Could not load friends: $e',
                style: TextStyle(color: theme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
