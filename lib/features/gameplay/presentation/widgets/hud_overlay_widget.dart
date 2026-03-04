import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/card.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/theme_provider.dart';

/// Floating HUD overlay displayed over the table.
///
/// Shows:
/// - Active suit icon (from Ace/Joker declaration or Queen lock)
/// - Draw penalty counter badge
/// - Connection status dot
class HudOverlayWidget extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
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
          _SuitIndicator(suit: activeSuit!, isQueenLock: false, theme: theme),
          const SizedBox(width: AppDimensions.sm),
        ],

        // Queen suit lock (accent ring)
        if (queenSuitLock != null) ...[
          _SuitIndicator(suit: queenSuitLock!, isQueenLock: true, theme: theme),
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
    const badgeColor = Color(0xFFE53935); // always red for danger signal
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: badgeColor.withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward_rounded,
                size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              '+$count',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
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
  const _SuitIndicator({
    required this.suit,
    required this.isQueenLock,
    required this.theme,
  });
  final Suit suit;
  final bool isQueenLock;
  final dynamic theme; // AppThemeData

  @override
  Widget build(BuildContext context) {
    final suitColor = suit.isRed
        ? (theme.suitRed as Color)
        : (theme.suitBlack as Color);
    final bgColor = suit.isRed
        ? const Color(0xFFE53935).withValues(alpha: 0.15)
        : (theme.surfacePanel as Color);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: isQueenLock
              ? (theme.accentPrimary as Color)
              : (theme.accentDark as Color),
          width: isQueenLock ? 2 : 1,
        ),
        boxShadow: isQueenLock
            ? [
                BoxShadow(
                  color: (theme.accentPrimary as Color).withValues(alpha: 0.4),
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
