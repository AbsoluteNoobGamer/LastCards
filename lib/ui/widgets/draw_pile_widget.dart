import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_back_widget.dart';

/// Draw pile widget — stacked card-back effect with a count badge.
/// Tappable by the local player when it's their turn and they can't play.
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
          transform: Matrix4.identity()..scale(targetScale, targetScale),
          transformAlignment: Alignment.center,
          width: widget.cardWidth +
              AppDimensions.pileStackLayers * AppDimensions.pileStackOffset * 2,
          height: height +
              AppDimensions.pileStackLayers * AppDimensions.pileStackOffset * 2,
          child: Stack(
            children: [
              // Stacked card backs (decorative depth)
              for (int i = AppDimensions.pileStackLayers; i > 0; i--)
                Positioned(
                  left: i * AppDimensions.pileStackOffset,
                  top: i * AppDimensions.pileStackOffset,
                  child: Opacity(
                    opacity: 1 - (i * 0.15),
                    child: CardBackWidget(width: widget.cardWidth),
                  ),
                ),

              // Top card back (interactive)
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
