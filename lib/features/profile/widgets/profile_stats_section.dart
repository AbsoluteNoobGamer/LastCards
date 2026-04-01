import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/utils/ranked_stats_reader.dart';
import '../../../core/utils/ranked_tier_utils.dart';
import '../../../core/widgets/player_progress_widgets.dart';
import '../../leaderboard/data/leaderboard_collections.dart';
import '../../leaderboard/data/local_leaderboard_store.dart';

typedef _ModeStatsTuple = ({int wins, int losses, int gamesPlayed});

/// Read-only local XP + optional ranked stats (when signed in).
///
/// [showXpProgress] — set false when embedding above an existing XP bar (e.g. account sheet).
class ProfileStatsSection extends StatefulWidget {
  const ProfileStatsSection({
    super.key,
    this.showXpProgress = true,
    this.statsHeaderTopSpacing = 28,
  });

  final bool showXpProgress;

  /// Space above the "STATS" label (use a smaller value when stacked under other content).
  final double statsHeaderTopSpacing;

  @override
  State<ProfileStatsSection> createState() => _ProfileStatsSectionState();
}

class _ProfileStatsSectionState extends State<ProfileStatsSection> {
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

    const firestoreCollections = {
      'leaderboard_online',
      'leaderboard_tournament_online',
      'leaderboard_bust_online',
      'ranked_stats',
    };

    final results = <LeaderboardMode, _ModeStatsTuple>{
      for (final m in LeaderboardMode.values) m: zero,
    };

    for (final mode in LeaderboardMode.values) {
      final collection = collectionForMode(mode);

      if (firestoreCollections.contains(collection)) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection(collection)
              .doc(uid)
              .get();
          if (doc.exists) {
            final d = doc.data() ?? {};
            int toInt(Object? v) => v is num ? v.toInt() : 0;
            results[mode] = (
              wins: toInt(d['wins']),
              losses: toInt(d['losses']),
              gamesPlayed: toInt(d['gamesPlayed']),
            );
          }
        } catch (_) {}
      } else {
        final entry = await LocalLeaderboardStore.instance
            .loadEntryForUser(collection, uid);
        if (entry != null) {
          results[mode] = (
            wins: entry.wins,
            losses: entry.losses,
            gamesPlayed: entry.gamesPlayed,
          );
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: headerTop),
            const Text(
              'STATS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfacePanel,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusButton),
                border: Border.all(
                  color: AppColors.goldDark.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showXp)
                    PlayerXpProgressBar(
                      accentColor: AppColors.goldPrimary,
                      surfaceColor: AppColors.surfaceDark,
                      textSecondary: AppColors.textSecondary,
                    ),
                  if (ranked != null) ...[
                    if (showXp) ...[                    
                      const SizedBox(height: 16),
                      Divider(
                        color: AppColors.goldDark.withValues(alpha: 0.3),
                        height: 1,
                      ),
                    ],
                    SizedBox(height: showXp ? 12 : 0),
                    _RankedStatsBlock(stats: ranked),
                  ],
                  SizedBox(height: (showXp || ranked != null) ? 16 : 0),
                  if (showXp || ranked != null)
                    Divider(
                      color: AppColors.goldDark.withValues(alpha: 0.3),
                      height: 1,
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'BY MODE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...LeaderboardMode.values.asMap().entries.map(
                    (e) {
                      final mode = e.value;
                      final isLast = e.key == LeaderboardMode.values.length - 1;
                      final s = modeMap[mode] ??
                          (wins: 0, losses: 0, gamesPlayed: 0);
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                        child: _ModeStatsRow(mode: mode, stats: s),
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
  const _RankedStatsBlock({required this.stats});

  final RankedStatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final tier = rankTierForMmr(stats.rating);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RANKED',
          style: TextStyle(
            color: AppColors.textSecondary,
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
                  color: AppColors.goldPrimary,
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
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ModeStatsRow extends StatelessWidget {
  const _ModeStatsRow({
    required this.mode,
    required this.stats,
  });

  final LeaderboardMode mode;
  final _ModeStatsTuple stats;

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
          color: AppColors.goldPrimary,
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
                  color: AppColors.goldPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${stats.gamesPlayed} games · ${stats.wins}W / ${stats.losses}L · $pctLabel',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
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
