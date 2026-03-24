import '../models/card_model.dart';
import 'pickup_chain_rules.dart';

/// Max hand size for showing the Last Cards button without Joker / pick-up cards.
const int lastCardsMaxHandSize = 4;

/// Hand-only chain check (no [validatePlay] / discard top). Used as a fallback
/// when the hand contains Jokers (mixed plays go through `declare_joker` online).
///
/// Explores single-card orderings; mid-turn flow mirrors [validatePlay] without
/// discard matching on the first card.
bool canHandClearInOneTurnHandOnly(List<CardModel> hand) {
  if (hand.isEmpty) return true;
  final cards = List<CardModel>.from(hand);
  return _dfsChain(cards, null);
}

bool _dfsChain(List<CardModel> remaining, CardModel? lastPlayed) {
  if (remaining.isEmpty) {
    if (lastPlayed == null) return true;
    return lastPlayed.effectiveRank != Rank.queen;
  }

  for (var i = 0; i < remaining.length; i++) {
    final next = remaining[i];
    final rest = List<CardModel>.from(remaining)..removeAt(i);
    if (lastPlayed == null) {
      if (_dfsChain(rest, next)) return true;
    } else if (_validChainStep(lastPlayed, next)) {
      if (_dfsChain(rest, next)) return true;
    }
  }
  return false;
}

/// Step validity mirroring [validatePlay] mid-turn flow (no discard).
bool _validChainStep(CardModel prev, CardModel next) {
  if (next.effectiveRank == Rank.queen) return true;

  if (prev.effectiveRank == Rank.queen) {
    return next.effectiveSuit == prev.effectiveSuit ||
        next.effectiveRank == Rank.queen ||
        next.isJoker;
  }

  if (prev.isJoker || next.isJoker) return true;

  if (isPenaltyChain(prev, next)) return true;

  if (prev.effectiveRank == next.effectiveRank) return true;

  final sameSuit = next.effectiveSuit == prev.effectiveSuit;
  final rankDiff =
      (next.effectiveRank.numericValue - prev.effectiveRank.numericValue).abs();
  final isTwoAndAce = (prev.effectiveRank == Rank.two &&
          next.effectiveRank == Rank.ace) ||
      (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);
  final isAceAndKing = (prev.effectiveRank == Rank.king &&
          next.effectiveRank == Rank.ace) ||
      (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.king);
  final isConsecutiveSameSuit =
      sameSuit && (rankDiff == 1 || isTwoAndAce || isAceAndKing);
  return isConsecutiveSameSuit;
}

/// Whether Last Cards can be acted on (AI / helpers). UI always shows the
/// button when not your turn; there is no hand-size visibility gate.
bool shouldShowLastCardsButton({
  required bool isBustMode,
  required bool isLocalTurn,
  required bool alreadyDeclared,
  bool skipMustBeBeforeYourTurn = false,
}) {
  if (isBustMode) return false;
  if (!skipMustBeBeforeYourTurn && isLocalTurn) return false;
  if (alreadyDeclared) return false;
  return true;
}
