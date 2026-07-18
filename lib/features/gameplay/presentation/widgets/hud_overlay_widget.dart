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
/// - Queen suit lock — same badge as active suit
/// - Draw penalty counter badge
///
/// Always occupies a fixed [slotHeight] so suit/penalty badges appearing or
/// clearing never reflow the pile row above.
class HudOverlayWidget extends ConsumerWidget {
  const HudOverlayWidget({
    super.key,
    this.activeSuit,
    this.queenSuitLock,
    this.penaltyCount = 0,
    this.penaltyTargetPosition,
    this.compact = false,
    this.onPenaltyIncreased,
    this.scale = 1.0,
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

  /// When true, uses smaller badges for landscape layout.
  final bool compact;

  /// Fires when [penaltyCount] increases (e.g. screen-edge flash on table).
  final VoidCallback? onPenaltyIncreased;

  /// Tablet/desktop scale multiplier (1.0 on phones).
  final double scale;

  /// Fixed vertical reservation — matches largest badge (suit circle) + pad.
  /// Callers should also size their [SizedBox] to this so the board stage
  /// never grows/shrinks when status badges toggle.
  static double slotHeight({required bool compact, double scale = 1.0}) {
    // Compact: circle only (36). Non-compact: circle + label.
    return ((compact ? 44.0 : 74.0) * scale);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final gap = (compact ? AppDimensions.xs : AppDimensions.sm) * scale;
    final height = slotHeight(compact: compact, scale: scale);
    final hasStatus =
        penaltyCount > 0 || activeSuit != null || queenSuitLock != null;

    // Height is reserved; clip so elastic scale/glow never paints overflow
    // stripes into neighbouring layout regions.
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Center(
          child: hasStatus
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (penaltyCount > 0) ...[
                      _PenaltyBadge(
                        count: penaltyCount,
                        targetPosition: penaltyTargetPosition,
                        compact: compact,
                        onPenaltyIncreased: onPenaltyIncreased,
                        scale: scale,
                      ),
                      SizedBox(width: gap),
                    ],
                    if (activeSuit != null) ...[
                      _AnimatedSuitBadge(
                        suit: activeSuit!,
                        theme: theme,
                        compact: compact,
                        scale: scale,
                      ),
                      SizedBox(width: gap),
                    ],
                    if (queenSuitLock != null) ...[
                      _AnimatedSuitBadge(
                        suit: queenSuitLock!,
                        theme: theme,
                        compact: compact,
                        scale: scale,
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
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
    case TablePosition.farRight:
    case TablePosition.bottomRight:
    case TablePosition.topRight:
      return math.pi / 4;
    case TablePosition.left:
    case TablePosition.farLeft:
    case TablePosition.bottomLeft:
    case TablePosition.topLeft:
      return -math.pi / 4;
    case TablePosition.bottom:
    case null:
      return math.pi;
  }
}

class _PenaltyBadge extends StatefulWidget {
  const _PenaltyBadge({
    required this.count,
    this.targetPosition,
    this.compact = false,
    this.onPenaltyIncreased,
    this.scale = 1.0,
  });

  final int count;
  final TablePosition? targetPosition;
  final bool compact;
  final VoidCallback? onPenaltyIncreased;
  final double scale;

  @override
  State<_PenaltyBadge> createState() => _PenaltyBadgeState();
}

class _PenaltyBadgeState extends State<_PenaltyBadge>
    with SingleTickerProviderStateMixin {
  int _bumpKey = 0;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PenaltyBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) {
      _bumpKey++;
      final cb = widget.onPenaltyIncreased;
      if (cb != null) {
        // Defer: parent [setState] must not run during this build phase.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) cb();
        });
      }
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shakeController.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const badgeColor = Color(0xFFE53935);
    final scale = widget.scale;
    final padding = widget.compact
        ? EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale)
        : EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale);
    final iconSize = (widget.compact ? 10.0 : 12.0) * scale;
    final fontSize = (widget.compact ? 10.0 : 12.0) * scale;
    final radius = (widget.compact ? 8.0 : 12.0) * scale;

    // Danger meter: fill grows with stack depth (caps visually at 8).
    final meterFill = (widget.count / 8.0).clamp(0.2, 1.0);
    final child = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: badgeColor, width: 1.5 * scale),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            badgeColor.withValues(alpha: 0.95),
            badgeColor.withValues(alpha: 0.55 + 0.4 * meterFill),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.45 + 0.25 * meterFill),
            blurRadius: 8 + 6 * meterFill,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: _rotationForTarget(widget.targetPosition),
            child: Icon(
              Icons.arrow_upward_rounded,
              size: iconSize,
              color: Colors.white,
            ),
          ),
          SizedBox(width: (widget.compact ? 2 : 3) * scale),
          Text(
            '+${widget.count}',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(width: (widget.compact ? 4 : 6) * scale),
          // Compact fill bar — reads as escalating danger.
          SizedBox(
            width: (widget.compact ? 28.0 : 36.0) * scale,
            height: (widget.compact ? 4.0 : 5.0) * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2 * scale),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.white.withValues(alpha: 0.2)),
                  FractionallySizedBox(
                    widthFactor: meterFill,
                    alignment: Alignment.centerLeft,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final startScale = _bumpKey > 0 ? 1.22 : 1.0;
    final scaled = TweenAnimationBuilder<double>(
      key: ValueKey('p$_bumpKey-${widget.count}'),
      tween: Tween(begin: startScale, end: 1.0),
      duration: Duration(milliseconds: _bumpKey > 0 ? 420 : 1),
      curve: Curves.elasticOut,
      builder: (context, scale, c) => Transform.scale(scale: scale, child: c),
      child: child,
    );
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, _) {
        final t = _shakeController.value;
        final dx = math.sin(t * math.pi * 8) * 4.5 * (1.0 - t);
        return Transform.translate(offset: Offset(dx, 0), child: scaled);
      },
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
  const _AnimatedSuitBadge({
    required this.suit,
    required this.theme,
    this.compact = false,
    this.scale = 1.0,
  });

  final Suit suit;
  final AppThemeData theme;
  final bool compact;
  final double scale;

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
    // Compact phones: circle only — label+circle was overflowing the HUD slot.
    final size = widget.compact ? 36.0 : 56.0;
    final fontSize = widget.compact ? 18.0 : 26.0;
    final labelSize = 9.0;
    final showLabel = !widget.compact;

    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: primaryColor, width: widget.compact ? 1.5 : 2.0),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.4),
            blurRadius: widget.compact ? 8 : 12,
            spreadRadius: widget.compact ? 1 : 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.suit.symbol,
          style: TextStyle(
            fontSize: fontSize,
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

    final content = showLabel
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              badge,
              const SizedBox(height: 4),
              Text(
                'ACTIVE SUIT',
                style: TextStyle(
                  fontSize: labelSize,
                  color: primaryColor.withValues(alpha: 0.7),
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
        : badge;

    return AnimatedScale(
      scale: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: content,
      ),
    );
  }
}
