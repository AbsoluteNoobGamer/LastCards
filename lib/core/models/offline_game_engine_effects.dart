part of 'offline_game_engine.dart';

// ── Effect application ─────────────────────────────────────────────────────────

/// Removes [cards] from the player's hand, updates the discard pile, and
/// applies any special-card effects.
GameState applyPlay({
  required GameState state,
  required String playerId,
  required List<CardModel> cards,
  Suit? declaredSuit, // for Ace plays
}) {
  var gs = _removeCardsFromHand(state, playerId, cards);

  gs = gs.copyWith(
    discardSecondCard: gs.discardTopCard,
    discardTopCard: cards.last,
    suitLock: null,
    queenSuitLock: null,
  );

  // A declaredSuit is only honored if the Ace was played as a Wild Card
  // (i.e., it's the very first card of the turn and the first card of this play).
  final isWildAcePlay =
      state.actionsThisTurn == 0 && cards.first.effectiveRank == Rank.ace;

  for (final card in cards) {
    final useDeclaredSuit = isWildAcePlay && card.id == cards.first.id;
    gs = _applySpecialEffect(gs, card,
        declaredSuit: useDeclaredSuit ? declaredSuit : null);
  }

  // Sequence Penalty Override: If the final card of the play is not a penalty
  // generating card (like a 2 or Black Jack), any accumulated penalty is canceled.
  // This rewards players for continuing a numerical sequence out of a penalty.
  final lastCard = cards.last;
  final isPenaltyCard = lastCard.effectiveRank == Rank.two ||
      (lastCard.effectiveRank == Rank.jack && lastCard.isBlackJack);

  if (!isPenaltyCard) {
    gs = gs.copyWith(activePenaltyCount: 0);
  }

  // Count this as a valid action for the current player, and record the last
  // card played this turn for same-turn sequential adjacency enforcement.
  gs = gs.copyWith(
    actionsThisTurn: gs.actionsThisTurn + 1,
    lastPlayedThisTurn: lastCard,
  );

  return gs;
}

/// Commits a Joker play into state before UI resolution.
///
/// This ensures the Joker is consumed from hand and the turn action is recorded
/// in the same play pipeline as any other card.
GameState beginJokerPlay({
  required GameState state,
  required String playerId,
  required CardModel jokerCard,
}) {
  final played =
      applyPlay(state: state, playerId: playerId, cards: [jokerCard]);
  return played.copyWith(pendingJokerResolution: true);
}

/// Finalizes a previously committed Joker play after the user picks a represented card.
GameState resolveJokerPlay({
  required GameState state,
  required CardModel resolvedJokerCard,
}) {
  return state.copyWith(
    discardTopCard: resolvedJokerCard,
    lastPlayedThisTurn: resolvedJokerCard,
    pendingJokerResolution: false,
  );
}

GameState _applySpecialEffect(
  GameState gs,
  CardModel card, {
  Suit? declaredSuit,
}) {
  switch (card.effectiveRank) {
    case Rank.two:
      return gs.copyWith(activePenaltyCount: gs.activePenaltyCount + 2);

    case Rank.jack:
      if (card.isBlackJack) {
        return gs.copyWith(activePenaltyCount: gs.activePenaltyCount + 5);
      } else {
        return gs.copyWith(activePenaltyCount: 0); // Red Jack cancels
      }

    case Rank.king:
      final newDir = gs.direction == PlayDirection.clockwise
          ? PlayDirection.counterClockwise
          : PlayDirection.clockwise;
      return gs.copyWith(direction: newDir);

    case Rank.queen:
      return gs.copyWith(queenSuitLock: card.effectiveSuit);

    case Rank.ace:
      if (declaredSuit != null) {
        return gs.copyWith(suitLock: declaredSuit);
      }
      return gs;

    case Rank.eight:
      return gs.copyWith(activeSkipCount: gs.activeSkipCount + 1);

    case Rank.joker:
    default:
      return gs;
  }
}

GameState _removeCardsFromHand(
  GameState state,
  String playerId,
  List<CardModel> cards,
) {
  final ids = cards.map((c) => c.id).toSet();
  return state.copyWith(
    players: state.players.map((p) {
      if (p.id != playerId) return p;
      final newHand = p.hand.where((c) => !ids.contains(c.id)).toList();
      return p.copyWith(hand: newHand, cardCount: newHand.length);
    }).toList(),
  );
}

// ── Draw card ─────────────────────────────────────────────────────────────────

/// Draws [count] cards for [playerId] using [cardFactory] and clears any
/// active penalty.
GameState applyDraw({
  required GameState state,
  required String playerId,
  required int count,
  required List<CardModel> Function(int n) cardFactory,
}) {
  final drawn = cardFactory(count);
  return state.copyWith(
    players: state.players.map((p) {
      if (p.id != playerId) return p;
      final newHand = [...p.hand, ...drawn];
      return p.copyWith(hand: newHand, cardCount: newHand.length);
    }).toList(),
    drawPileCount: math.max(0, state.drawPileCount - count),
    activePenaltyCount: 0,
  );
}
