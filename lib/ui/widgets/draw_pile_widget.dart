import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_back_widget.dart';

/// Draw pile widget — stacked card-back effect with a count badge.
/// Tappable by the local player when it's their turn and they can't play.
class DrawPileWidget extends StatelessWidget {
  const DrawPileWidget({
    super.key,
    required this.cardCount,
    this.onTap,
    this.cardWidth = AppDimensions.cardWidthLarge,
    this.enabled = true,
  });

  final int cardCount;
  final VoidCallback? onTap;
  final double cardWidth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(cardWidth);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: cardWidth + AppDimensions.pileStackLayers * AppDimensions.pileStackOffset * 2,
        height: height + AppDimensions.pileStackLayers * AppDimensions.pileStackOffset * 2,
        child: Stack(
          children: [
            // Stacked card backs (decorative depth)
            for (int i = AppDimensions.pileStackLayers; i > 0; i--)
              Positioned(
                left: i * AppDimensions.pileStackOffset,
                top: i * AppDimensions.pileStackOffset,
                child: Opacity(
                  opacity: 1 - (i * 0.15),
                  child: CardBackWidget(width: cardWidth),
                ),
              ),

            // Top card back (interactive)
            AnimatedOpacity(
              opacity: enabled ? 1.0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: CardBackWidget(width: cardWidth),
            ),

            // Card count badge
            Positioned(
              bottom: 6,
              right: 6,
              child: _CountBadge(count: cardCount),
            ),

            // "DRAW" label
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'DRAW',
                    style: AppTypography.labelSmall.copyWith(
                      letterSpacing: 2,
                      color: AppColors.goldDark,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: AppDimensions.penaltyBadgeSize,
        minHeight: AppDimensions.penaltyBadgeSize,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfacePanel,
        border: Border.all(color: AppColors.goldDark, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
