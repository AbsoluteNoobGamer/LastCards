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

  // No [GameState] here: this DFS only chains cards within one hypothetical turn.
  // After any penalty card, the next card in that turn is always "chain live"
  // for purposes of this hand-only simulation — gate with
  // [GameState.isPenaltyChainActive] when validating against real game state.
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

/// Whether a player may declare Last Cards given whose turn it is.
/// You must declare when it is **not** your turn (before play returns to you).
bool mayDeclareLastCards({
  required String currentPlayerId,
  required String playerId,
}) =>
    currentPlayerId != playerId;

/// Whether the Last Cards **control** is shown (not bust, not already declared).
/// Turn-order for actually declaring is enforced by [mayDeclareLastCards] and
/// the server session.
bool shouldShowLastCardsButton({
  required bool isBustMode,
  required bool alreadyDeclared,
}) {
  if (isBustMode) return false;
  if (alreadyDeclared) return false;
  return true;
}
