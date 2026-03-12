import '../core/models/card_model.dart';

enum GameSound {
  cardDraw,
  cardPlace,
  specialTwo,
  specialBlackJack,
  specialRedJack,
  specialKing,
  specialAce,
  specialQueen,
  specialEight,
  specialJoker,
  penaltyDraw,
  turnStart,
  timerWarning,
  timerExpired,
  playerWin,
  playerLose,
  tournamentQualify,
  tournamentEliminate,
  tournamentWin,
  shuffleDeck,
  bustRoundStart,
  bustRoundEnd,
  skipApplied,
  directionReversed,
  opponentOut,
  endTurnButton,
  cardSelect,
}

/// Returns the [GameSound] for a special card's effect, or `null` for normal cards.
/// Callers play [GameSound.cardPlace] (card_place.wav) for every card; only
/// special cards get an additional sound from this function (all modes).
GameSound? soundForCard(CardModel card) {
  switch (card.effectiveRank) {
    case Rank.two:
      return GameSound.specialTwo;
    case Rank.jack:
      return card.isBlackJack
          ? GameSound.specialBlackJack
          : GameSound.specialRedJack;
    case Rank.king:
      return GameSound.specialKing;
    case Rank.ace:
      return GameSound.specialAce;
    case Rank.queen:
      return GameSound.specialQueen;
    case Rank.eight:
      return GameSound.specialEight;
    case Rank.joker:
      return GameSound.specialJoker;
    default:
      return null;
  }
}
