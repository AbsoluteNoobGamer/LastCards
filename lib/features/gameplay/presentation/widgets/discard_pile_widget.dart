import 'package:flutter/material.dart';

import '../../domain/entities/card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import 'card_back_widget.dart';
import 'card_widget.dart';

/// The central discard pile widget.
///
/// Shows the [topCard] prominently with subtle stacked card layers behind it
/// that scale with [discardPileCount]. Animates in new cards via [AnimatedSwitcher].
class DiscardPileWidget extends StatefulWidget {
  const DiscardPileWidget({
    super.key,
    this.topCard,
    this.secondCard,
    this.cardWidth = AppDimensions.cardWidthDiscardTop,
    this.discardPileCount = 0,
  });

  final CardModel? topCard;
  final CardModel? secondCard;
  final double cardWidth;

  /// Number of cards currently in the discard pile. Used to compute stack depth.
  final int discardPileCount;

  @override
  State<DiscardPileWidget> createState() => _DiscardPileWidgetState();
}

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

class _DiscardPileWidgetState extends State<DiscardPileWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(widget.cardWidth);
    final targetOffset = _isHovering ? const Offset(0, -10) : Offset.zero;

    // How many subtle card-back layers to show behind the top card
    final layers = _stackLayers(widget.discardPileCount);
    const layerOffset = 2.5; // px per layer

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: SizedBox(
        width: widget.cardWidth + 16,
        height: height + 16,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Zone label (visible when pile is empty)
            if (widget.topCard == null)
              _EmptyPileLabel(width: widget.cardWidth, height: height),

            // Dynamic stacked card-back layers (furthest first)
            if (widget.topCard != null)
              for (int i = layers; i >= 1; i--)
                Positioned(
                  top: 8 + i * layerOffset,
                  left: 8 + i * layerOffset,
                  child: Opacity(
                    opacity: (1 - i * 0.15).clamp(0.2, 0.8),
                    child: CardBackWidget(width: widget.cardWidth),
                  ),
                ),

            // Top card — hover lift + animated switcher for smooth transitions
            if (widget.topCard != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                    targetOffset.dx, targetOffset.dy, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOut,
                    )),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Hero(
                    key: ValueKey(widget.topCard!.id),
                    tag: 'card-${widget.topCard!.id}',
                    child: _ClippedCardWithRing(
                      cardWidth: widget.cardWidth,
                      isHovering: _isHovering,
                      child: CardWidget(
                        card: widget.topCard!,
                        width: widget.cardWidth,
                        faceUp: true,
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

/// Wraps a card with a drop-shadow + gold ring border that is fully clipped to
/// the card's rounded corners — eliminating any rectangular box artefact.
class _ClippedCardWithRing extends StatelessWidget {
  const _ClippedCardWithRing({
    required this.cardWidth,
    required this.isHovering,
    required this.child,
  });

  final double cardWidth;
  final bool isHovering;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      AppDimensions.radiusCard * (cardWidth / AppDimensions.cardWidthMedium),
    );

    return DecoratedBox(
      // Outer shadow paints around the clip without creating a background box
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          if (isHovering)
            BoxShadow(
              color: AppColors.goldPrimary.withValues(alpha: 0.5),
              blurRadius: 25,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            child,
            // Gold ring drawn INSIDE the clipped area — stays rounded, no rectangle
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color:
                          isHovering ? AppColors.goldPrimary : AppColors.goldDark,
                      width: 3,
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

class _EmptyPileLabel extends StatelessWidget {
  const _EmptyPileLabel({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(
            AppDimensions.radiusCard * (width / AppDimensions.cardWidthMedium)),
        color: AppColors.feltMid.withValues(alpha: 0.4),
      ),
      child: Center(
        child: Text(
          'DISCARD',
          style: AppTypography.labelSmall.copyWith(
            letterSpacing: 2,
            color: AppColors.goldDark,
          ),
        ),
      ),
    );
  }
}
