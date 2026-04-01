import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/card.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/shadow_blur.dart';
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
    this.compact = false,
    this.onPenaltyIncreased,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final gap = compact ? AppDimensions.xs : AppDimensions.sm;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Penalty counter — arrow points toward the player who picks up
        if (penaltyCount > 0) ...[
          _PenaltyBadge(
            count: penaltyCount,
            targetPosition: penaltyTargetPosition,
            compact: compact,
            onPenaltyIncreased: onPenaltyIncreased,
          ),
          SizedBox(width: gap),
        ],

        // Active suit badge (Ace/Joker declaration) — premium badge with pop-in
        if (activeSuit != null) ...[
          _AnimatedSuitBadge(suit: activeSuit!, theme: theme, compact: compact),
          SizedBox(width: gap),
        ],

        // Queen suit lock (distinct accent ring indicator)
        if (queenSuitLock != null) ...[
          _QueenLockIndicator(suit: queenSuitLock!, theme: theme, compact: compact),
          SizedBox(width: gap),
        ],

        SizedBox(width: gap),
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
  });

  final int count;
  final TablePosition? targetPosition;
  final bool compact;
  final VoidCallback? onPenaltyIncreased;

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
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final iconSize = widget.compact ? 10.0 : 12.0;
    final fontSize = widget.compact ? 10.0 : 12.0;
    final radius = widget.compact ? 8.0 : 12.0;

    final child = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(radius),
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
            angle: _rotationForTarget(widget.targetPosition),
            child: Icon(
              Icons.arrow_upward_rounded,
              size: iconSize,
              color: Colors.white,
            ),
          ),
          SizedBox(width: widget.compact ? 2 : 3),
          Text(
            '+${widget.count}',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
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
  const _AnimatedSuitBadge({required this.suit, required this.theme, this.compact = false});

  final Suit suit;
  final AppThemeData theme;
  final bool compact;

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
    final size = widget.compact ? 40.0 : 56.0;
    final fontSize = widget.compact ? 20.0 : 26.0;
    final labelSize = widget.compact ? 8.0 : 9.0;

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
            SizedBox(height: widget.compact ? 2 : 4),
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
        ),
      ),
    );
  }
}

// ── Queen lock indicator ──────────────────────────────────────────────────────

/// Smaller indicator for Queen suit-lock — distinct from the Ace badge.
/// Uses [theme.accentPrimary] for border and glow.
class _QueenLockIndicator extends StatefulWidget {
  const _QueenLockIndicator(
      {required this.suit, required this.theme, this.compact = false});

  final Suit suit;
  final AppThemeData theme;
  final bool compact;

  @override
  State<_QueenLockIndicator> createState() => _QueenLockIndicatorState();
}

class _QueenLockIndicatorState extends State<_QueenLockIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _rotate;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      _glow.repeat(reverse: true);
      _rotate.repeat();
    });
  }

  @override
  void dispose() {
    _glow.dispose();
    _rotate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suitColor = _suitSymbolColor(widget.suit);
    final primaryColor = widget.theme.accentPrimary;
    final bgColor = widget.theme.surfacePanel;
    final size = widget.compact ? 32.0 : 40.0;
    final fontSize = widget.compact ? 16.0 : 20.0;
    final labelSize = widget.compact ? 7.0 : 8.0;
    final disable = MediaQuery.disableAnimationsOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_glow, _rotate]),
          builder: (context, _) {
            final blur = nonNegativeShadowBlur(
              disable
                  ? (widget.compact ? 6.0 : 10.0)
                  : (6.0 + _glow.value.clamp(0.0, 1.0) * 10.0),
            );
            final angle = disable ? 0.0 : _rotate.value * 2 * math.pi;
            return SizedBox(
              width: size + 8,
              height: size + 8,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.rotate(
                    angle: angle,
                    child: Container(
                      width: size + 6,
                      height: size + 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: primaryColor,
                          width: widget.compact ? 1.5 : 2),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.4),
                          blurRadius: blur,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.suit.symbol,
                        style: AppTypography.cardRank(
                          color: suitColor,
                          fontSize: fontSize,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: widget.compact ? 2 : 4),
        Text(
          'QUEEN LOCK',
          style: TextStyle(
            fontSize: labelSize,
            color: primaryColor.withValues(alpha: 0.7),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
