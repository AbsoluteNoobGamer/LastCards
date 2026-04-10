import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/services/player_level_service.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_theme_data.dart';
import '../../../core/utils/ranked_stats_reader.dart';
import '../../../core/utils/ranked_tier_utils.dart';
import '../../../core/widgets/player_progress_widgets.dart';
import '../../leaderboard/data/leaderboard_collections.dart';
import '../../leaderboard/data/local_leaderboard_store.dart';

typedef _ModeStatsTuple = ({int wins, int losses, int gamesPlayed});

/// Collections written only by the game server in Firestore (read Firestore).
const _firestoreOnlyCollections = {
  'leaderboard_online',
  'leaderboard_tournament_online',
  'leaderboard_bust_online',
  'ranked_stats',
  'ranked_hardcore_stats',
};

/// Client writes to both [LocalLeaderboardStore] and Firestore; prefer local when
/// present (matches leaderboard merge / lag), otherwise read Firestore (new device).
const _clientDualWriteCollections = {
  'leaderboard_single_player',
  'leaderboard_tournament_ai',
  'leaderboard_bust_offline',
};

int _statsToInt(Object? v) => v is num ? v.toInt() : 0;

/// Read-only local XP + optional ranked stats (when signed in).
///
/// [showXpProgress] — set false when embedding above an existing XP bar (e.g. account sheet).
class ProfileStatsSection extends ConsumerStatefulWidget {
  const ProfileStatsSection({
    super.key,
    this.showXpProgress = true,
    this.statsHeaderTopSpacing = 28,
  });

  final bool showXpProgress;

  /// Space above the "STATS" label (use a smaller value when stacked under other content).
  final double statsHeaderTopSpacing;

  @override
  ConsumerState<ProfileStatsSection> createState() =>
      _ProfileStatsSectionState();
}

class _ProfileStatsSectionState extends ConsumerState<ProfileStatsSection> {
  late final Future<
      ({
        RankedStatsSnapshot? ranked,
        Map<LeaderboardMode, _ModeStatsTuple> modes,
      })> _statsFuture = Future.wait([
    fetchRankedStatsForCurrentUser(),
    _fetchAllModeStats(),
  ]).then(
    (results) => (
      ranked: results[0] as RankedStatsSnapshot?,
      modes: results[1] as Map<LeaderboardMode, _ModeStatsTuple>,
    ),
  );

  Future<Map<LeaderboardMode, _ModeStatsTuple>> _fetchAllModeStats() async {
    const zero = (wins: 0, losses: 0, gamesPlayed: 0);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {for (final m in LeaderboardMode.values) m: zero};
    }

    final results = <LeaderboardMode, _ModeStatsTuple>{
      for (final m in LeaderboardMode.values) m: zero,
    };

    for (final mode in LeaderboardMode.values) {
      final collection = collectionForMode(mode);

      if (_firestoreOnlyCollections.contains(collection)) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection(collection)
              .doc(uid)
              .get();
          if (doc.exists) {
            final d = doc.data() ?? {};
            results[mode] = (
              wins: _statsToInt(d['wins']),
              losses: _statsToInt(d['losses']),
              gamesPlayed: _statsToInt(d['gamesPlayed']),
            );
          }
        } catch (_) {}
      } else if (_clientDualWriteCollections.contains(collection)) {
        final local = await LocalLeaderboardStore.instance
            .loadEntryForUser(collection, uid);
        if (local != null) {
          results[mode] = (
            wins: local.wins,
            losses: local.losses,
            gamesPlayed: local.gamesPlayed,
          );
        } else {
          try {
            final doc = await FirebaseFirestore.instance
                .collection(collection)
                .doc(uid)
                .get();
            if (doc.exists) {
              final d = doc.data() ?? {};
              results[mode] = (
                wins: _statsToInt(d['wins']),
                losses: _statsToInt(d['losses']),
                gamesPlayed: _statsToInt(d['gamesPlayed']),
              );
            }
          } catch (_) {}
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return FutureBuilder<
        ({
          RankedStatsSnapshot? ranked,
          Map<LeaderboardMode, _ModeStatsTuple> modes,
        })>(
      future: _statsFuture,
      builder: (context, snap) {
        final ranked = snap.data?.ranked;
        final modeMap = snap.data?.modes ?? {};
        final showXp = widget.showXpProgress;
        final headerTop = widget.statsHeaderTopSpacing;
        final hasXp = showXp;
        final hasRanked = ranked != null;
        final hasUpperBlock = hasXp || hasRanked;
        final dividerColor = theme.accentDark.withValues(alpha: 0.35);
        final borderColor = theme.accentPrimary.withValues(alpha: 0.45);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: headerTop),
            Text(
              'STATS',
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surfacePanel,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusButton),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasXp)
                    PlayerXpProgressBar(
                      accentColor: theme.accentPrimary,
                      surfaceColor:
                          theme.surfaceDark.withValues(alpha: 0.85),
                      textSecondary: theme.textSecondary,
                    ),
                  if (hasXp) ...[
                    const SizedBox(height: 12),
                    _StreakRow(theme: theme),
                  ],
                  if (hasXp && hasRanked) ...[
                    const SizedBox(height: 16),
                    Divider(color: dividerColor, height: 1),
                  ],
                  if (hasRanked)
                    _RankedStatsBlock(
                      stats: ranked,
                      theme: theme,
                    ),
                  if (hasUpperBlock) ...[
                    const SizedBox(height: 16),
                    Divider(color: dividerColor, height: 1),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'BY MODE',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...LeaderboardMode.values.asMap().entries.map(
                    (e) {
                      final mode = e.value;
                      final isLast =
                          e.key == LeaderboardMode.values.length - 1;
                      final s = modeMap[mode] ??
                          (wins: 0, losses: 0, gamesPlayed: 0);
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                        child: _ModeStatsRow(
                          mode: mode,
                          stats: s,
                          theme: theme,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RankedStatsBlock extends StatelessWidget {
  const _RankedStatsBlock({
    required this.stats,
    required this.theme,
  });

  final RankedStatsSnapshot stats;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tier = rankTierForMmr(stats.rating);
    return Column(
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
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PlayerLevelService.instance.currentStreak,
        PlayerLevelService.instance.bestStreak,
      ]),
      builder: (context, _) {
        final current = PlayerLevelService.instance.currentStreak.value;
        final best = PlayerLevelService.instance.bestStreak.value;
        return Row(
          children: [
            _StreakChip(
              label: 'Streak',
              value: current,
              icon: '🔥',
              theme: theme,
            ),
            const SizedBox(width: 10),
            _StreakChip(
              label: 'Best',
              value: best,
              icon: '⭐',
              theme: theme,
            ),
          ],
        );
      },
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.theme,
  });

  final String label;
  final int value;
  final String icon;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.surfaceDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.accentPrimary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    '$value',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: theme.accentPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeStatsRow extends StatelessWidget {
  const _ModeStatsRow({
    required this.mode,
    required this.stats,
    required this.theme,
  });

  final LeaderboardMode mode;
  final _ModeStatsTuple stats;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final gp = stats.gamesPlayed;
    final winRate = gp > 0 ? (100.0 * stats.wins / gp) : 0.0;
    final pctLabel = '${winRate.toStringAsFixed(1)}%';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          mode.icon,
          size: 20,
          color: theme.accentPrimary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode.label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: theme.accentPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${stats.gamesPlayed} games · ${stats.wins}W / ${stats.losses}L · $pctLabel',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
