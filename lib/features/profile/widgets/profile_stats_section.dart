import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/utils/ranked_stats_reader.dart';
import '../../../core/utils/ranked_tier_utils.dart';
import '../../../core/widgets/player_progress_widgets.dart';

/// Read-only local XP + optional ranked stats (when signed in).
class ProfileStatsSection extends StatefulWidget {
  const ProfileStatsSection({super.key});

  @override
  State<ProfileStatsSection> createState() => _ProfileStatsSectionState();
}

class _ProfileStatsSectionState extends State<ProfileStatsSection> {
  late final Future<RankedStatsSnapshot?> _rankedFuture =
      fetchRankedStatsForCurrentUser();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RankedStatsSnapshot?>(
      future: _rankedFuture,
      builder: (context, snap) {
        final ranked = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
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
                  PlayerXpProgressBar(
                    accentColor: AppColors.goldPrimary,
                    surfaceColor: AppColors.surfaceDark,
                    textSecondary: AppColors.textSecondary,
                  ),
                  if (ranked != null) ...[
                    const SizedBox(height: 16),
                    Divider(
                      color: AppColors.goldDark.withValues(alpha: 0.3),
                      height: 1,
                    ),
                    const SizedBox(height: 12),
                    _RankedStatsBlock(stats: ranked),
                  ],
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
