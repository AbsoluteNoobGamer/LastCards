import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import 'card_back_widget.dart';

/// Maps a card count to the number of visible stack layers behind the top card.
/// 0 cards → 0 layers, 1–10 → 1, 11–20 → 2, 21–30 → 3, 31–40 → 4, 40+ → 5.
int _stackLayers(int count) {
  if (count <= 0) return 0;
  if (count <= 10) return 1;
  if (count <= 20) return 2;
  if (count <= 30) return 3;
  if (count <= 40) return 4;
  return 5;
}

/// Draw pile widget — stacked card-back effect with a count badge.
/// Tappable by the local player when it's their turn and they can't play.
/// The number of visible stack layers scales dynamically with [cardCount].
///
/// [reshuffleNotifier] — when this notifier fires (its value is toggled),
/// the widget plays a short shuffle animation to signal a reshuffle event.
class DrawPileWidget extends StatefulWidget {
  const DrawPileWidget({
    super.key,
    required this.cardCount,
    this.onTap,
    this.cardWidth = AppDimensions.cardWidthDrawPile,
    this.enabled = true,
    this.reshuffleNotifier,
  });

  final int cardCount;
  final VoidCallback? onTap;
  final double cardWidth;
  final bool enabled;

  /// Optional notifier whose value is toggled whenever a reshuffle occurs.
  /// Toggling (not just setting) lets repeated reshuffles each trigger the
  /// animation even if the value cycles back to the same bool.
  final ValueNotifier<bool>? reshuffleNotifier;

  @override
  State<DrawPileWidget> createState() => _DrawPileWidgetState();
}

class _DrawPileWidgetState extends State<DrawPileWidget>
    with SingleTickerProviderStateMixin {
  bool _isHovering = false;
  bool _isPressed = false;

  late final AnimationController _shuffleCtrl;
  late final Animation<double> _shuffleAnim;

  @override
  void initState() {
    super.initState();

    // 900 ms shuffle animation controller
    _shuffleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Oscillating fan effect:
    // 0–25 %  → scale down to 0.88
    // 25–75 % → 4 rapid oscillations left/right (±10 px translated via sin)
    // 75–100% → scale back to 1.0
    // We expose a single 0→1 animation and compute derived values in build().
    _shuffleAnim = CurvedAnimation(
      parent: _shuffleCtrl,
      curve: Curves.linear,
    );

    widget.reshuffleNotifier?.addListener(_onReshuffle);
  }

  @override
  void didUpdateWidget(DrawPileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reshuffleNotifier != widget.reshuffleNotifier) {
      oldWidget.reshuffleNotifier?.removeListener(_onReshuffle);
      widget.reshuffleNotifier?.addListener(_onReshuffle);
    }
  }

  @override
  void dispose() {
    widget.reshuffleNotifier?.removeListener(_onReshuffle);
    _shuffleCtrl.dispose();
    super.dispose();
  }

  void _onReshuffle() {
    if (!mounted) return;
    _shuffleCtrl.forward(from: 0);
  }

  /// Static ring — combined with [AnimatedOpacity] only when drawable toggles.
  Widget _drawableRingDecoration() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppColors.goldPrimary.withValues(alpha: 0.55),
            width: 2,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Returns the animated x-offset of the top card (oscillation phase).
  double _computeOffsetX(double t) {
    // Only oscillate during 25–75 % of the animation.
    if (t < 0.25 || t > 0.75) return 0.0;
    final normalised = (t - 0.25) / 0.50; // 0→1 within the oscillation window
    return math.sin(normalised * math.pi * 6) * 10.0; // 3 full swings × 10 px
  }

  /// Returns the animated scale of the whole pile during the animation.
  double _computeScale(double t) {
    if (t < 0.25) {
      // scale down: 1.0 → 0.88
      return 1.0 - t / 0.25 * 0.12;
    } else if (t < 0.75) {
      return 0.88;
    } else {
      // scale back: 0.88 → 1.0
      return 0.88 + (t - 0.75) / 0.25 * 0.12;
    }
  }

  /// Gold overlay opacity — visible during the oscillation window only.
  double _computeGlowOpacity(double t) {
    if (t < 0.20 || t > 0.80) return 0.0;
    // Ramp up: 20–30 %, full: 30–70 %, ramp down: 70–80 %
    if (t < 0.30) return (t - 0.20) / 0.10;
    if (t > 0.70) return (0.80 - t) / 0.10;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final double targetScale = (_isPressed || _isHovering) ? 0.95 : 1.0;
    final height = AppDimensions.cardHeight(widget.cardWidth);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final drawable =
        widget.enabled && widget.onTap != null && widget.cardCount > 0;

    // Dynamic layer count based on actual card count
    final layers = _stackLayers(widget.cardCount);
    const layerOffset = AppDimensions.pileStackOffset;

    // Size the container to accommodate the maximum possible layers cleanly
    final extraPadding = layers * layerOffset * 2;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.enabled ? () => widget.onTap?.call() : null,
          onTapDown:
              widget.enabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp:
              widget.enabled ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: () => setState(() => _isPressed = false),
          splashColor: AppColors.goldPrimary.withValues(alpha: 0.35),
          highlightColor: AppColors.goldLight.withValues(alpha: 0.12),
          // Reshuffle: scale/offset/glow opacity; [BoxShadow] on badge is static.
          // Hover: [AnimatedScale]. Shuffle-only [AnimatedBuilder] — no per-frame
          // second ticker (avoids _debugRelayoutBoundaryAlreadyMarkedNeedsLayout).
          child: AnimatedScale(
            scale: targetScale,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _shuffleAnim,
              builder: (context, child) {
                final t = _shuffleAnim.value;
                final shuffleScale = _computeScale(t);
                final offsetX = _computeOffsetX(t);
                final glowOpacity = _computeGlowOpacity(t) * 0.45;

                return SizedBox(
                  width: widget.cardWidth + extraPadding,
                  height: height + extraPadding,
                  child: Transform.scale(
                    scale: shuffleScale,
                    child: Stack(
                      children: [
                        // Subtle gold frame when draw is available — opacity toggles
                        // only when [drawable] changes (no per-frame ticker).
                        Positioned.fill(
                          child: reduceMotion
                              ? Opacity(
                                  opacity: drawable ? 1 : 0,
                                  child: _drawableRingDecoration(),
                                )
                              : AnimatedOpacity(
                                  opacity: drawable ? 1 : 0,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  child: _drawableRingDecoration(),
                                ),
                        ),
                        // Dynamic stacked card backs (furthest layer first)
                        for (int i = layers; i > 0; i--)
                          Positioned(
                            left: i * layerOffset,
                            top: i * layerOffset,
                            child: Opacity(
                              opacity: (1 - i * 0.15).clamp(0.2, 1.0),
                              child: CardBackWidget(width: widget.cardWidth),
                            ),
                          ),

                        // Top card back (interactive) — animated during reshuffle
                        Transform.translate(
                          offset: Offset(offsetX, 0),
                          child: Hero(
                            tag: 'draw-pile-top',
                            flightShuttleBuilder: (flightContext,
                                animation,
                                flightDirection,
                                fromHeroContext,
                                toHeroContext) {
                              final bounce = TweenSequence([
                                TweenSequenceItem(
                                    tween: Tween(begin: 1.0, end: 0.85).chain(
                                        CurveTween(curve: Curves.easeOut)),
                                    weight: 30),
                                TweenSequenceItem(
                                    tween: Tween(begin: 0.85, end: 1.0).chain(
                                        CurveTween(curve: Curves.easeIn)),
                                    weight: 70),
                              ]).animate(animation);

                              return ScaleTransition(
                                scale: bounce,
                                child: toHeroContext.widget,
                              );
                            },
                            child: AnimatedOpacity(
                              opacity: widget.enabled ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 200),
                              child: CardBackWidget(width: widget.cardWidth),
                            ),
                          ),
                        ),

                        // Gold glow overlay — only visible during the reshuffle
                        if (glowOpacity > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: glowOpacity,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.goldPrimary,
                                      width: 3,
                                    ),
                                    gradient: RadialGradient(
                                      colors: [
                                        AppColors.goldLight
                                            .withValues(alpha: 0.35),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Card count badge
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _CountBadge(count: widget.cardCount),
                        ),

                        // "DRAW" label
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceDark
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: drawable
                                      ? AppColors.goldLight
                                      : AppColors.goldDark,
                                  width: drawable ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                'DRAW',
                                style: AppTypography.labelSmall.copyWith(
                                  letterSpacing: 2,
                                  color: AppColors.goldLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
        minWidth: 32,
        minHeight: 32,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfacePanel,
        border: Border.all(color: AppColors.goldPrimary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '$count',
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.goldLight,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
