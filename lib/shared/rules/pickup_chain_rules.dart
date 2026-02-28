import '../models/card_model.dart';
import 'card_rules.dart';

/// Returns true if [card] is valid as the first card when a penalty is active.
/// Valid first cards: 2, Black Jack, or Red Jack.
bool isFirstCardValidUnderPenalty(CardModel card) {
  final isTwo = card.effectiveRank == Rank.two;
  final isBlackJack = card.isBlackJack;
  final isRedJack =
      card.effectiveRank == Rank.jack && !card.isBlackJack;
  return isTwo || isBlackJack || isRedJack;
}

/// Returns true if all cards in [cards] are penalty-addressing (all 2s, all Black
/// Jacks, or all Red Jacks). Such plays bypass standard suit/rank matching.
bool areAllCardsPenaltyAddressing(List<CardModel> cards) {
  final allTwos = cards.every((c) => c.effectiveRank == Rank.two);
  final allBlackJacks = cards.every((c) => c.isBlackJack);
  final allRedJacks =
      cards.every((c) => c.effectiveRank == Rank.jack && !c.isBlackJack);
  return allTwos || allBlackJacks || allRedJacks;
}

/// Returns true if the penalty should be cleared after this play.
/// Sequence override: non-penalty card as final card clears accumulated penalty.
bool shouldClearPenaltyAfterPlay(CardModel lastCard) {
  return !isPenaltyGeneratingCard(lastCard);
}

/// Returns true if both cards are penalty-capable (2 or Jack), allowing them to
/// chain regardless of suit/rank adjacency.
bool isPenaltyChain(CardModel prev, CardModel next) {
  final prevIsPenaltyNode =
      prev.effectiveRank == Rank.two || prev.effectiveRank == Rank.jack;
  final nextIsPenaltyNode =
      next.effectiveRank == Rank.two || next.effectiveRank == Rank.jack;
  return prevIsPenaltyNode && nextIsPenaltyNode;
}
