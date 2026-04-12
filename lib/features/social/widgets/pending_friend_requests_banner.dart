import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/friends_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/app_theme_data.dart';

/// Top banner when the user has pending friend requests (Firestore-backed).
class PendingFriendRequestsBanner extends ConsumerWidget {
  const PendingFriendRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final async = ref.watch(incomingFriendRequestsProvider);

    return async.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final first = list.first;
        final extra = list.length - 1;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: _FriendRequestBannerCard(
            key: ValueKey(first.fromUid),
            fromUid: first.fromUid,
            extraCount: extra,
            theme: theme,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FriendRequestBannerCard extends ConsumerStatefulWidget {
  const _FriendRequestBannerCard({
    super.key,
    required this.fromUid,
    required this.extraCount,
    required this.theme,
  });

  final String fromUid;
  final int extraCount;
  final AppThemeData theme;

  @override
  ConsumerState<_FriendRequestBannerCard> createState() =>
      _FriendRequestBannerCardState();
}

class _FriendRequestBannerCardState
    extends ConsumerState<_FriendRequestBannerCard> {
  late Future<String> _displayNameFuture;

  @override
  void initState() {
    super.initState();
    _displayNameFuture = ref
        .read(firestoreProfileServiceProvider)
        .getProfileForUid(widget.fromUid)
        .then((p) => p?.displayName ?? 'Player');
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Material(
      color: theme.surfacePanel.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: FutureBuilder<String>(
          future: _displayNameFuture,
          builder: (context, snap) {
            final name = snap.data ?? '…';
            final extra = widget.extraCount > 0
                ? ' · +${widget.extraCount} more'
                : '';
            return Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded,
                    color: theme.accentPrimary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Friend request',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: theme.textSecondary,
                        ),
                      ),
                      Text(
                        '$name$extra',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.accentPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _decline(context),
                  child: Text(
                    'Decline',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _accept(context),
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context) async {
    try {
      await ref.read(friendsServiceProvider).acceptFriendRequest(widget.fromUid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are now friends')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept: $e')),
      );
    }
  }

  Future<void> _decline(BuildContext context) async {
    try {
      await ref.read(friendsServiceProvider).declineFriendRequest(widget.fromUid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request declined')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not decline: $e')),
      );
    }
  }
}
