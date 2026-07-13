import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/friends_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/navigation/app_page_routes.dart';
import '../../../core/services/friends_service.dart';
import '../../lobby/presentation/screens/lobby_screen.dart';

/// Top banner when the user has pending in-app room invites from friends.
class PendingGameInvitesBanner extends ConsumerStatefulWidget {
  const PendingGameInvitesBanner({super.key});

  @override
  ConsumerState<PendingGameInvitesBanner> createState() =>
      _PendingGameInvitesBannerState();
}

class _PendingGameInvitesBannerState
    extends ConsumerState<PendingGameInvitesBanner> {
  // Ticks the countdown text below without waiting on a Firestore snapshot,
  // which only arrives when the invite list itself changes.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _dismiss(
    WidgetRef ref,
    String inviteDocId,
  ) async {
    await ref.read(friendsServiceProvider).deleteGameInvite(inviteDocId);
  }

  /// This invite notification's own countdown — not the room's lifetime — so
  /// the invitee knows the banner itself is about to disappear and doesn't
  /// mistake that for the room being gone.
  String _expiryLabel(DateTime? createdAt) {
    if (createdAt == null) return 'Room invite';
    final remaining =
        FriendsService.gameInviteMaxAge - DateTime.now().difference(createdAt);
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    return 'Room invite · expires in ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final invitesAsync = ref.watch(pendingGameInvitesProvider);

    return invitesAsync.when(
      data: (invites) {
        if (invites.isEmpty) return const SizedBox.shrink();
        final e = invites.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Material(
            color: theme.surfacePanel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoutes.fadeSlide(
                            (_) => LobbyScreen(
                              initialRoomCodeToJoin: e.roomCode,
                              pendingGameInviteDocIdToDismiss: e.id,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.mail_rounded,
                              color: theme.accentPrimary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _expiryLabel(e.createdAt),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: theme.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    '${e.fromDisplayName} · tap to join ${e.roomCode}',
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
                            Icon(
                              Icons.chevron_right_rounded,
                              color: theme.accentPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Dismiss invite',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _dismiss(ref, e.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                          child: Icon(
                            Icons.close_rounded,
                            color: theme.textSecondary.withValues(alpha: 0.85),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
