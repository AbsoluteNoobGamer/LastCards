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
class DiscardPileWidget extends StatelessWidget {
  const DiscardPileWidget({
    super.key,
    this.topCard,
    this.secondCard,
    this.cardWidth = AppDimensions.cardWidthLarge,
  });

  final CardModel? topCard;
  final CardModel? secondCard;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(cardWidth);

    return SizedBox(
      width: cardWidth + 8,
      height: height + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Zone label (visible when pile is empty)
          if (topCard == null)
            _EmptyPileLabel(width: cardWidth, height: height),

          // Second card (behind, barely offset)
          if (secondCard != null)
            Positioned(
              top: 4,
              left: 4,
              child: Opacity(
                opacity: 0.65,
                child: CardWidget(
                  card: secondCard!,
                  width: cardWidth,
                  faceUp: true,
                ),
              ),
            ),

          // Top card — animated switcher for smooth transitions
          if (topCard != null)
            AnimatedSwitcher(
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
              child: CardWidget(
                key: ValueKey(topCard!.id),
                card: topCard!,
                width: cardWidth,
                faceUp: true,
              ),
            ),
        ],
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
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
