import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/navigation/app_page_routes.dart';
import '../../../core/providers/friends_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/display_name_registry_service.dart';
import '../../../core/services/firestore_profile_service.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../lobby/presentation/screens/lobby_screen.dart';
import 'other_player_profile_sheet.dart';

/// Start-menu sheet: lists accepted friends, remove, and shortcut to lobby for in-app invites.
class FriendsListSheet extends ConsumerStatefulWidget {
  const FriendsListSheet({super.key});

  @override
  ConsumerState<FriendsListSheet> createState() => _FriendsListSheetState();
}

class _FriendsListSheetState extends ConsumerState<FriendsListSheet> {
  final _searchController = TextEditingController();
  final _registryService = DisplayNameRegistryService();
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _findPlayer() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      setState(() => _searchError = 'Sign in to search for players.');
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    final uid = await _registryService.findUidByDisplayName(query);

    if (!mounted) return;
    setState(() => _searching = false);

    if (uid == null) {
      setState(() => _searchError = 'No player found with that name.');
      return;
    }
    if (uid == me) {
      setState(() => _searchError = "That's you!");
      return;
    }

    setState(() => _searchError = null);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OtherPlayerProfileSheet(
        firebaseUid: uid,
        fallbackDisplayName: query,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _findPlayer(),
                    style: GoogleFonts.inter(color: theme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Find a player by username',
                      hintStyle: GoogleFonts.inter(color: theme.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: theme.accentPrimary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _searching ? null : _findPlayer,
                  style: IconButton.styleFrom(backgroundColor: theme.accentPrimary),
                  icon: _searching
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.backgroundDeep,
                          ),
                        )
                      : Icon(Icons.search_rounded, color: theme.backgroundDeep),
                ),
              ],
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 6),
              Text(
                _searchError!,
                style: GoogleFonts.inter(fontSize: 12, color: theme.textSecondary),
              ),
            ],
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
                      'No friends yet. Search for a player above, or tap '
                      'another player’s avatar during an online game.',
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
