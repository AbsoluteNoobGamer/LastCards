import '../models/card_model.dart';

/// Context for Joker play validation (turn start vs mid-turn continuance).
enum JokerPlayContext {
  turnStarter,
  midTurnContinuance,
}

/// Returns the Joker play context based on how many cards have been played this turn.
JokerPlayContext jokerPlayContextFromCardsPlayed(int cardsPlayedThisTurn) {
  return cardsPlayedThisTurn == 0
      ? JokerPlayContext.turnStarter
      : JokerPlayContext.midTurnContinuance;
}

/// Penalty values for pick-up cards (2 → +2, Black Jack → +5, Red Jack → 0).
const int penaltyTwo = 2;
const int penaltyBlackJack = 5;
const int penaltyRedJack = 0; // cancels

/// Returns true if the card is a penalty-generating card (2 or Black Jack).
bool isPenaltyGeneratingCard(CardModel card) {
  return card.effectiveRank == Rank.two ||
      (card.effectiveRank == Rank.jack && card.isBlackJack);
}
