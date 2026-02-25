import 'package:flutter/material.dart';

import '../../domain/entities/card.dart';
import '../../../../core/theme/app_dimensions.dart';
import 'card_widget.dart';

/// Displays the local player's hand as a fanned, horizontally scrollable row.
///
/// Cards overlap by [AppDimensions.handCardOverlap]. Selected card ids
/// are passed in [selectedCardIds]; tap a card to toggle selection via [onCardTap].
class PlayerHandWidget extends StatelessWidget {
  const PlayerHandWidget({
    super.key,
    required this.cards,
    this.selectedCardIds = const {},
    this.onCardTap,
    this.cardWidth = AppDimensions.cardWidthMedium,
    this.enabled = true,
  });

  final List<CardModel> cards;
  final Set<String> selectedCardIds;
  final ValueChanged<String>? onCardTap;
  final double cardWidth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final isCompact = maxWidth < AppDimensions.breakpointMobile;
        final targetWidth =
            (maxWidth * (isCompact ? 0.14 : 0.11)).clamp(44.0, cardWidth);
        final overlap = (targetWidth * 0.38).clamp(12.0, 28.0);
        final spread = (targetWidth - overlap).clamp(8.0, targetWidth);
        final totalWidth = targetWidth + (cards.length - 1) * spread;

        return SizedBox(
          height: AppDimensions.cardHeight(targetWidth) + 14, // room for lift
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  for (int i = 0; i < cards.length; i++)
                    Positioned(
                      left: i * spread,
                      bottom: 0,
                      child: Hero(
                        tag: 'card-${cards[i].id}',
                        flightShuttleBuilder: (flightContext, animation,
                            flightDirection, fromHeroContext, toHeroContext) {
                          final bounce = TweenSequence([
                            TweenSequenceItem(
                                tween: Tween(begin: 1.0, end: 1.1)
                                    .chain(CurveTween(curve: Curves.easeOut)),
                                weight: 50),
                            TweenSequenceItem(
                                tween: Tween(begin: 1.1, end: 1.0)
                                    .chain(CurveTween(curve: Curves.easeIn)),
                                weight: 50),
                          ]).animate(animation);

                          return ScaleTransition(
                            scale: bounce,
                            child: toHeroContext.widget,
                          );
                        },
                        child: CardWidget(
                          card: cards[i],
                          width: targetWidth,
                          faceUp: true,
                          isSelected: selectedCardIds.contains(cards[i].id),
                          onTap: enabled
                              ? () => onCardTap?.call(cards[i].id)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
