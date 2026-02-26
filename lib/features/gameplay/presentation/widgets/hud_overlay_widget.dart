import 'package:flutter/material.dart';

import '../../domain/entities/card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';

/// Floating HUD overlay displayed over the table.
///
/// Shows:
/// - Active suit icon (from Ace/Joker declaration or Queen lock)
/// - Draw penalty counter badge
/// - Connection status dot
class HudOverlayWidget extends StatelessWidget {
  const HudOverlayWidget({
    super.key,
    this.activeSuit,
    this.queenSuitLock,
    this.penaltyCount = 0,
  });

  /// Active suit declared by Ace or Joker (null = no override).
  final Suit? activeSuit;

  /// Queen suit lock (null = no lock).
  final Suit? queenSuitLock;

  /// Number of accumulated penalty cards facing the next player.
  final int penaltyCount;


  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Penalty counter
        if (penaltyCount > 0) ...[
          _PenaltyBadge(count: penaltyCount),
          const SizedBox(width: AppDimensions.sm),
        ],

        // Active suit icon
        if (activeSuit != null) ...[
          _SuitIndicator(suit: activeSuit!, isQueenLock: false),
          const SizedBox(width: AppDimensions.sm),
        ],

        // Queen suit lock (gold ring)
        if (queenSuitLock != null) ...[
          _SuitIndicator(suit: queenSuitLock!, isQueenLock: true),
          const SizedBox(width: AppDimensions.sm),
        ],

        const SizedBox(width: AppDimensions.sm),
      ],
    );
  }
}

// ── Penalty badge ─────────────────────────────────────────────────────────────

class _PenaltyBadge extends StatelessWidget {
  const _PenaltyBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.redAccent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.redAccent.withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward_rounded,
                size: 12, color: AppColors.textPrimary),
            const SizedBox(width: 3),
            Text(
              '+$count',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suit indicator ────────────────────────────────────────────────────────────

class _SuitIndicator extends StatelessWidget {
  const _SuitIndicator({required this.suit, required this.isQueenLock});
  final Suit suit;
  final bool isQueenLock;

  @override
  Widget build(BuildContext context) {
    final suitColor = suit.isRed ? AppColors.suitRed : AppColors.suitBlack;
    final bgColor = suit.isRed
        ? AppColors.redAccent.withValues(alpha: 0.15)
        : AppColors.surfacePanel;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: isQueenLock ? AppColors.goldPrimary : AppColors.goldDark,
          width: isQueenLock ? 2 : 1,
        ),
        boxShadow: isQueenLock
            ? [
                BoxShadow(
                  color: AppColors.goldPrimary.withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          suit.symbol,
          style: AppTypography.cardRank(
            color: suitColor,
            fontSize: isQueenLock ? 20 : 18,
          ),
        ),
      ),
    );
  }
}
