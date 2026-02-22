import 'package:flutter/material.dart';

import '../../core/models/card_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_widget.dart';

/// The central discard pile widget.
///
/// Shows the [topCard] prominently with a shadow of the [secondCard] behind it
/// (for a stacked depth effect). Animates in new cards via [AnimatedSwitcher].
class DiscardPileWidget extends StatefulWidget {
  const DiscardPileWidget({
    super.key,
    this.topCard,
    this.secondCard,
    this.cardWidth = AppDimensions.cardWidthDiscardTop,
  });

  final CardModel? topCard;
  final CardModel? secondCard;
  final double cardWidth;

  @override
  State<DiscardPileWidget> createState() => _DiscardPileWidgetState();
}

class _DiscardPileWidgetState extends State<DiscardPileWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(widget.cardWidth);
    final targetOffset = _isHovering ? const Offset(0, -10) : Offset.zero;

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

            // Second card (behind, barely offset)
            if (widget.secondCard != null)
              Positioned(
                top: 4,
                left: 4,
                child: Opacity(
                  opacity: 0.65,
                  child: CardWidget(
                    card: widget.secondCard!,
                    width: AppDimensions.cardWidthLarge, // Slightly smaller
                    faceUp: true,
                  ),
                ),
              ),

            // Top card — hover lift + animated switcher for smooth transitions
            if (widget.topCard != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(targetOffset.dx, targetOffset.dy, 0),
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
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusCard * (widget.cardWidth / AppDimensions.cardWidthMedium)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                        // Gold glow when hovered
                        if (_isHovering)
                          BoxShadow(
                            color: AppColors.goldPrimary.withValues(alpha: 0.5),
                            blurRadius: 25,
                            spreadRadius: 2,
                          ),
                      ],
                      border: Border.all(
                        color: _isHovering ? AppColors.goldPrimary : AppColors.goldDark,
                        width: 3,
                      ),
                    ),
                    child: Hero(
                      tag: 'card-${widget.topCard!.id}',
                      child: CardWidget(
                        key: ValueKey(widget.topCard!.id),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard * (width / AppDimensions.cardWidthMedium)),
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
