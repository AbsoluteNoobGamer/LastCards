import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_dimensions.dart';
import '../theme/app_theme_data.dart';

/// Compact head-to-head summary (profile sheet or post-game).
class HeadToHeadStatsBlock extends StatelessWidget {
  const HeadToHeadStatsBlock({
    super.key,
    required this.yourWins,
    required this.theirWins,
    required this.recentResults,
    required this.theme,
    this.title = 'HEAD TO HEAD',
  });

  final int yourWins;
  final int theirWins;
  final List<String> recentResults;
  final AppThemeData theme;
  final String title;

  @override
  Widget build(BuildContext context) {
    final recent =
        recentResults.map((x) => x == 'win' ? 'W' : 'L').join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(
          color: theme.suitRed.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'You',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$yourWins–$theirWins',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.accentPrimary,
                ),
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Recent: $recent',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
