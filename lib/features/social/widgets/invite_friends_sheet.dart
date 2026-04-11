import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/friends_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/firestore_profile_service.dart';
import '../../../core/providers/user_profile_provider.dart';

/// Picks a friend to receive an in-app room invite (Firestore notification).
class InviteFriendsSheet extends ConsumerWidget {
  const InviteFriendsSheet({
    super.key,
    required this.roomCode,
    required this.onInvited,
  });

  final String roomCode;
  final VoidCallback onInvited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final friendsAsync = ref.watch(friendUidListProvider);
    final profileService = ref.watch(firestoreProfileServiceProvider);
    final friendsService = ref.watch(friendsServiceProvider);
    final fromName = ref.watch(displayNameForGameProvider);

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
              'Invite a friend',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'They will see a join prompt in the app — no room code to copy.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
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
                          final name = snap.data?.displayName.trim().isNotEmpty ==
                                  true
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
                                color: theme.accentPrimary
                                    .withValues(alpha: 0.35),
                              ),
                            ),
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
                            trailing: Icon(
                              Icons.send_rounded,
                              color: theme.accentPrimary,
                            ),
                            onTap: () async {
                              try {
                                await friendsService.sendGameInvite(
                                  toUid: uid,
                                  roomCode: roomCode,
                                  fromDisplayName: fromName,
                                );
                                onInvited();
                                if (context.mounted) Navigator.of(context).pop();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Invite sent to $name'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Could not send invite: $e'),
                                    ),
                                  );
                                }
                              }
                            },
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
