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
class DrawPileWidget extends StatefulWidget {
  const DrawPileWidget({
    super.key,
    required this.cardCount,
    this.onTap,
    this.cardWidth = AppDimensions.cardWidthDrawPile,
    this.enabled = true,
  });

  final int cardCount;
  final VoidCallback? onTap;
  final double cardWidth;
  final bool enabled;

  @override
  State<DrawPileWidget> createState() => _DrawPileWidgetState();
}

class _DrawPileWidgetState extends State<DrawPileWidget> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double targetScale = (_isPressed || _isHovering) ? 0.95 : 1.0;
    final height = AppDimensions.cardHeight(widget.cardWidth);

    // Dynamic layer count based on actual card count
    final layers = _stackLayers(widget.cardCount);
    const layerOffset = AppDimensions.pileStackOffset;

    // Size the container to accommodate the maximum possible layers cleanly
    final extraPadding = layers * layerOffset * 2;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTapDown:
            widget.enabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _isPressed = false);
                widget.onTap?.call();
              }
            : null,
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(targetScale, targetScale, 1.0),
          transformAlignment: Alignment.center,
          width: widget.cardWidth + extraPadding,
          height: height + extraPadding,
          child: Stack(
            children: [
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

              // Top card back (interactive)
              Hero(
                tag: 'draw-pile-top',
                flightShuttleBuilder: (flightContext, animation,
                    flightDirection, fromHeroContext, toHeroContext) {
                  // Add an inverse shrink-then-expand bounce during flight
                  final bounce = TweenSequence([
                    TweenSequenceItem(
                        tween: Tween(begin: 1.0, end: 0.85)
                            .chain(CurveTween(curve: Curves.easeOut)),
                        weight: 30),
                    TweenSequenceItem(
                        tween: Tween(begin: 0.85, end: 1.0)
                            .chain(CurveTween(curve: Curves.easeIn)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.goldDark, width: 1),
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
