import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/core/theme/app_typography.dart';
import '../models/bust_player_view_model.dart';

class BustPlayerSlot extends ConsumerWidget {
  const BustPlayerSlot({super.key, required this.player});

  final BustPlayerViewModel player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    final Color borderColor;
    final double borderWidth;
    final Color bgColor;
    final List<BoxShadow> shadows;

    if (player.isEliminated) {
      borderColor = theme.textSecondary.withValues(alpha: 0.35);
      borderWidth = 1.5;
      bgColor = player.color.withValues(alpha: 0.2);
      shadows = const [];
    } else if (player.isActive) {
      borderColor = theme.accentPrimary;
      borderWidth = 3.0;
      bgColor = theme.accentPrimary.withValues(alpha: 0.22);
      shadows = [
        BoxShadow(
          color: theme.accentPrimary.withValues(alpha: 0.55),
          blurRadius: 14,
          spreadRadius: 2,
        ),
      ];
    } else {
      borderColor = theme.textSecondary.withValues(alpha: 0.35);
      borderWidth = 1.5;
      bgColor = player.color.withValues(alpha: 0.2);
      shadows = const [];
    }

    Widget slot = SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: shadows,
                ),
                child: Center(
                  child: Icon(
                    Icons.person,
                    color: player.color,
                    size: 28,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accentDark,
                    border: Border.all(
                      color: theme.surfacePanel,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    player.isEliminated ? 'X' : '${player.cardCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.xs),
          SizedBox(
            width: 80,
            child: Text(
              player.displayName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTypography.labelSmall.copyWith(
                color: player.isActive ? player.color : theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (player.isEliminated) {
      slot = Opacity(opacity: 0.40, child: slot);
    }

    return slot;
  }
}
