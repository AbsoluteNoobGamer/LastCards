import 'package:flutter/material.dart';

import '../../core/models/card_model.dart';
import '../../core/theme/app_dimensions.dart';
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

    final totalWidth = cardWidth +
        (cards.length - 1) * (cardWidth - AppDimensions.handCardOverlap);

    return SizedBox(
      height: AppDimensions.cardHeight(cardWidth) + 14, // room for lift
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              for (int i = 0; i < cards.length; i++)
                Positioned(
                  left: i * (cardWidth - AppDimensions.handCardOverlap),
                  bottom: 0,
                  child: CardWidget(
                    card: cards[i],
                    width: cardWidth,
                    faceUp: true,
                    isSelected: selectedCardIds.contains(cards[i].id),
                    onTap: enabled
                        ? () => onCardTap?.call(cards[i].id)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
