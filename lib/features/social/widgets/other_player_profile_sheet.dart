import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/friends_provider.dart';
import '../../../core/services/friends_service.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/firestore_profile_service.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_theme_data.dart';
import '../../../core/utils/public_player_stats.dart';
import '../../../core/utils/ranked_stats_reader.dart';
import '../../../core/utils/ranked_tier_utils.dart';
import '../../leaderboard/data/leaderboard_collections.dart';

/// Bottom sheet: opponent public profile, stats, and friend actions.
class OtherPlayerProfileSheet extends ConsumerStatefulWidget {
  const OtherPlayerProfileSheet({
    super.key,
    required this.firebaseUid,
    required this.fallbackDisplayName,
  });

  final String firebaseUid;
  final String fallbackDisplayName;

  @override
  ConsumerState<OtherPlayerProfileSheet> createState() =>
      _OtherPlayerProfileSheetState();
}

class _OtherPlayerProfileSheetState
    extends ConsumerState<OtherPlayerProfileSheet> {
  late Future<
      ({
        FirestoreUserProfile? profile,
        RankedStatsSnapshot? ranked,
        Map<LeaderboardMode, PublicModeStats> modes,
        FriendRelation relation,
      })> _load;

  @override
  void initState() {
    super.initState();
    _load = _buildLoadFuture();
  }

  Future<
      ({
        FirestoreUserProfile? profile,
        RankedStatsSnapshot? ranked,
        Map<LeaderboardMode, PublicModeStats> modes,
        FriendRelation relation,
      })> _buildLoadFuture() {
    final service = ref.read(firestoreProfileServiceProvider);
    final friends = ref.read(friendsServiceProvider);
    final uid = widget.firebaseUid;
    return Future.wait([
      service.getProfileForUid(uid),
      fetchRankedStatsForUid(uid),
      fetchPublicModeStatsForUid(uid),
      friends.relationTo(uid),
    ]).then(
      (results) => (
        profile: results[0] as FirestoreUserProfile?,
        ranked: results[1] as RankedStatsSnapshot?,
        modes: results[2] as Map<LeaderboardMode, PublicModeStats>,
        relation: results[3] as FriendRelation,
      ),
    );
  }

  void _refresh() {
    setState(() {
      _load = _buildLoadFuture();
    });
  }

  Future<void> _onFriendAction(FriendRelation relation) async {
    final friends = ref.read(friendsServiceProvider);
    final uid = widget.firebaseUid;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (relation) {
        case FriendRelation.none:
        case FriendRelation.notSignedIn:
          await friends.sendFriendRequest(uid);
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Friend request sent')),
            );
          }
          break;
        case FriendRelation.outgoingRequest:
          await friends.cancelOutgoingFriendRequest(uid);
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Request cancelled')),
            );
          }
          break;
        case FriendRelation.incomingRequest:
          return;
        case FriendRelation.friends:
          await friends.removeFriend(uid);
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Removed from friends')),
            );
          }
          break;
        case FriendRelation.self:
          break;
      }
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not update friends: $e')),
        );
      }
    }
  }

  Future<void> _acceptIncoming() async {
    final friends = ref.read(friendsServiceProvider);
    try {
      await friends.acceptFriendRequest(widget.firebaseUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are now friends')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept: $e')),
        );
      }
    }
  }

  Future<void> _declineIncoming() async {
    final friends = ref.read(friendsServiceProvider);
    try {
      await friends.declineFriendRequest(widget.firebaseUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decline: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final me = FirebaseAuth.instance.currentUser?.uid;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: theme.backgroundDeep,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.35)),
        ),
        child: FutureBuilder<
            ({
              FirestoreUserProfile? profile,
              RankedStatsSnapshot? ranked,
              Map<LeaderboardMode, PublicModeStats> modes,
              FriendRelation relation,
            })>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snap.data!;
            final name = data.profile?.displayName.trim().isNotEmpty == true
                ? data.profile!.displayName
                : widget.fallbackDisplayName;
            final avatarUrl = data.profile?.avatarUrl;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: theme.surfacePanel,
                        backgroundImage:
                            avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Icon(Icons.person_rounded,
                                size: 40, color: theme.accentPrimary)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: theme.textPrimary,
                              ),
                            ),
                            if (me != null && me != widget.firebaseUid)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _FriendButton(
                                  relation: data.relation,
                                  onPressed: () =>
                                      _onFriendAction(data.relation),
                                  onAcceptIncoming: _acceptIncoming,
                                  onDeclineIncoming: _declineIncoming,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data.ranked != null) ...[
                    const SizedBox(height: 20),
                    _RankedBlock(stats: data.ranked!, theme: theme),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'STATS BY MODE',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.surfacePanel,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusButton),
                      border: Border.all(
                        color: theme.accentPrimary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: LeaderboardMode.values.map((mode) {
                        final s = data.modes[mode] ??
                            (wins: 0, losses: 0, gamesPlayed: 0);
                        final gp = s.gamesPlayed;
                        final pct = gp > 0 ? (100.0 * s.wins / gp) : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(mode.icon, size: 18, color: theme.accentPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mode.label,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: theme.accentPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${s.gamesPlayed} games · ${s.wins}W / ${s.losses}L · ${pct.toStringAsFixed(1)}%',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: theme.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FriendButton extends StatelessWidget {
  const _FriendButton({
    required this.relation,
    required this.onPressed,
    required this.onAcceptIncoming,
    required this.onDeclineIncoming,
  });

  final FriendRelation relation;
  final VoidCallback onPressed;
  final VoidCallback onAcceptIncoming;
  final VoidCallback onDeclineIncoming;

  @override
  Widget build(BuildContext context) {
    switch (relation) {
      case FriendRelation.notSignedIn:
        return OutlinedButton(
          onPressed: null,
          child: const Text('Sign in to add friends'),
        );
      case FriendRelation.self:
        return const SizedBox.shrink();
      case FriendRelation.friends:
        return OutlinedButton(
          onPressed: onPressed,
          child: const Text('Remove friend'),
        );
      case FriendRelation.incomingRequest:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onAcceptIncoming,
                child: const Text('Accept'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onDeclineIncoming,
                child: const Text('Decline'),
              ),
            ),
          ],
        );
      case FriendRelation.outgoingRequest:
        return OutlinedButton(
          onPressed: onPressed,
          child: const Text('Cancel request'),
        );
      case FriendRelation.none:
        return ElevatedButton(
          onPressed: onPressed,
          child: const Text('Add friend'),
        );
    }
  }
}

class _RankedBlock extends StatelessWidget {
  const _RankedBlock({
    required this.stats,
    required this.theme,
  });

  final RankedStatsSnapshot stats;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tier = rankTierForMmr(stats.rating);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RANKED',
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(tier.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${stats.rating} MMR · ${tier.label}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: theme.accentPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${stats.wins}W / ${stats.losses}L',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: theme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
