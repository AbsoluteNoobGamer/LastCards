import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/card.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/providers/theme_provider.dart';

/// Floating HUD overlay displayed over the table.
///
/// Shows:
/// - Active suit badge (from Ace/Joker declaration) — premium theme-aware badge
/// - Queen suit lock indicator
/// - Draw penalty counter badge
class HudOverlayWidget extends ConsumerWidget {
  const HudOverlayWidget({
    super.key,
    this.activeSuit,
    this.queenSuitLock,
    this.penaltyCount = 0,
    this.penaltyTargetPosition,
  });

  /// Active suit declared by Ace or Joker (null = no override).
  final Suit? activeSuit;

  /// Queen suit lock (null = no lock).
  final Suit? queenSuitLock;

  /// Number of accumulated penalty cards facing the next player.
  final int penaltyCount;

  /// Table position of the player who will receive the penalty pickup.
  /// Drives the arrow direction on the penalty badge.
  final TablePosition? penaltyTargetPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Penalty counter — arrow points toward the player who picks up
        if (penaltyCount > 0) ...[
          _PenaltyBadge(
            count: penaltyCount,
            targetPosition: penaltyTargetPosition,
          ),
          const SizedBox(width: AppDimensions.sm),
        ],

        // Active suit badge (Ace/Joker declaration) — premium badge with pop-in
        if (activeSuit != null) ...[
          _AnimatedSuitBadge(suit: activeSuit!, theme: theme),
          const SizedBox(width: AppDimensions.sm),
        ],

        // Queen suit lock (distinct accent ring indicator)
        if (queenSuitLock != null) ...[
          _QueenLockIndicator(suit: queenSuitLock!, theme: theme),
          const SizedBox(width: AppDimensions.sm),
        ],

        const SizedBox(width: AppDimensions.sm),
      ],
    );
  }
}

// ── Penalty badge ─────────────────────────────────────────────────────────────

/// Rotation (radians, clockwise from 12 o'clock) toward the seat that will
/// receive the penalty. A single upward arrow is then rotated to the angle,
/// producing natural diagonal directions for corner seats.
///
///   top   →  0        (12 o'clock, straight up)
///   right → +π/4      ( 1:30 position, upper-right)
///   left  → −π/4      (10:30 position, upper-left)
///   bottom→  π        ( 6 o'clock, straight down — local player picks up)
double _rotationForTarget(TablePosition? position) {
  switch (position) {
    case TablePosition.top:
      return 0;
    case TablePosition.right:
      return math.pi / 4;
    case TablePosition.left:
      return -math.pi / 4;
    case TablePosition.bottom:
    case null:
      return math.pi;
  }
}

class _PenaltyBadge extends StatelessWidget {
  const _PenaltyBadge({required this.count, this.targetPosition});

  final int count;

  /// Where the penalty-receiving player sits — determines arrow direction.
  final TablePosition? targetPosition;

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
            Transform.rotate(
              angle: _rotationForTarget(targetPosition),
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
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

// ── Suit colour helper ────────────────────────────────────────────────────────

/// Returns the fixed suit colour used across ALL themes.
/// Hearts/Diamonds are always red; Clubs/Spades are always white.
Color _suitSymbolColor(Suit suit) {
  return suit.isRed ? const Color(0xFFE53935) : Colors.white;
}

// ── Premium suit badge (Ace / Joker declaration) ──────────────────────────────

/// Animated badge that pops in when an Ace or Joker declares a suit.
/// Colors are driven entirely by [theme] — zero hardcoded theme values.
class _AnimatedSuitBadge extends StatefulWidget {
  const _AnimatedSuitBadge({required this.suit, required this.theme});

  final Suit suit;
  final AppThemeData theme;

  @override
  State<_AnimatedSuitBadge> createState() => _AnimatedSuitBadgeState();
}

class _AnimatedSuitBadgeState extends State<_AnimatedSuitBadge> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Defer one frame so the animated transition fires on first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suitColor = _suitSymbolColor(widget.suit);
    final primaryColor = widget.theme.accentPrimary;
    final bgColor = widget.theme.surfacePanel;

    final badge = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: primaryColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.suit.symbol,
          style: TextStyle(
            fontSize: 26,
            color: suitColor,
            shadows: [
              Shadow(
                color: suitColor.withValues(alpha: 0.8),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );

    return AnimatedScale(
      scale: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge,
            const SizedBox(height: 4),
            Text(
              'ACTIVE SUIT',
              style: TextStyle(
                fontSize: 9,
                color: primaryColor.withValues(alpha: 0.7),
                letterSpacing: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Queen lock indicator ──────────────────────────────────────────────────────

/// Smaller indicator for Queen suit-lock — distinct from the Ace badge.
/// Uses [theme.accentPrimary] for border and glow.
class _QueenLockIndicator extends StatelessWidget {
  const _QueenLockIndicator({required this.suit, required this.theme});

  final Suit suit;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final suitColor = _suitSymbolColor(suit);
    final primaryColor = theme.accentPrimary;
    final bgColor = theme.surfacePanel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: primaryColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: Text(
              suit.symbol,
              style: AppTypography.cardRank(
                color: suitColor,
                fontSize: 20,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'QUEEN LOCK',
          style: TextStyle(
            fontSize: 8,
            color: primaryColor.withValues(alpha: 0.7),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
