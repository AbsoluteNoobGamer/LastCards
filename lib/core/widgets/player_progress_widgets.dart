import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/player_level_service.dart';
import '../theme/app_theme_data.dart';

/// Compact level badge (toolbar / profile row).
class PlayerLevelChip extends StatelessWidget {
  const PlayerLevelChip({
    super.key,
    required this.accentColor,
    this.backgroundColor,
  });

  final Color accentColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PlayerLevelService.instance.currentLevel,
      builder: (context, level, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: backgroundColor ?? accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accentColor, width: 1),
          ),
          child: Text(
            'Lv $level',
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

/// XP bar + labels using [AppThemeData] (start screen, themed surfaces).
class PlayerXpProgressBarThemed extends StatelessWidget {
  const PlayerXpProgressBarThemed({
    super.key,
    required this.theme,
  });

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return PlayerXpProgressBar(
      accentColor: theme.accentPrimary,
      surfaceColor: theme.surfaceDark.withValues(alpha: 0.85),
      textSecondary: theme.textSecondary,
    );
  }
}

/// XP bar + labels using explicit colors (profile screen with [AppColors]).
class PlayerXpProgressBar extends StatelessWidget {
  const PlayerXpProgressBar({
    super.key,
    required this.accentColor,
    required this.surfaceColor,
    required this.textSecondary,
  });

  final Color accentColor;
  final Color surfaceColor;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PlayerLevelService.instance.currentXP,
        PlayerLevelService.instance.currentLevel,
      ]),
      builder: (context, _) {
        final xp = PlayerLevelService.instance.currentXP.value;
        final p = PlayerLevelService.progressForTotalXp(xp);
        final label = p.nextBandStartXp == null
            ? 'Level ${p.level} · Max level · $xp XP'
            : 'Level ${p.level} · $xp / ${p.nextBandStartXp} XP';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.progressFraction,
                minHeight: 8,
                backgroundColor: surfaceColor,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          ],
        );
      },
    );
  }
}
