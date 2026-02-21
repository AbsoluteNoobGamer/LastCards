import 'dart:math' as math;

import 'card_model.dart';
import 'game_state.dart';
import 'player_model.dart';

// ── Play validation ────────────────────────────────────────────────────────────

/// Returns `null` if the play is legal, or an error string explaining why not.
///
/// Multi-card rules:
///   • Same-rank stacking: all cards share the same rank.
///   • Numerical sequence: all cards same suit, strictly consecutive
///     ascending OR descending by numericValue.
///
/// Same-turn sequential rule:
///   • If a card has already been played this turn (actionsThisTurn > 0),
///     a single-card follow-up must be rank-adjacent (±1) to the last played
///     card AND share the same suit (Numerical Flow continuation).
///
/// The leading card (lowest for ascending, highest for descending) must satisfy
/// the normal suit/rank match against the discard top.
String? validatePlay({
  required List<CardModel> cards,
  required CardModel discardTop,
  required GameState state,
}) {
  if (cards.isEmpty) return 'No cards selected.';

  // All jokers → wild, always legal.
  if (cards.every((c) => c.isJoker)) return null;

  // ── Penalty Override Rule ──────────────────────────────────────────────
  if (state.activePenaltyCount > 0) {
    // When a penalty is active, only specific cards may be played:
    // 1. A 2 — stacks the penalty further (+2).
    // 2. A Black Jack (♠/♣) — stacks onto an active 2-chain (+5). Per guidelines:
    //    "Black Jack may be stacked onto an active 2-chain."
    // 3. A Red Jack (♥/♦) — cancels the entire penalty (resets to 0).
    final allTwos = cards.every((c) => c.effectiveRank == Rank.two);
    final allBlackJacks = cards.every((c) => c.isBlackJack);
    final allRedJacks = cards.every((c) => c.effectiveRank == Rank.jack && !c.isBlackJack);

    if (!allTwos && !allBlackJacks && !allRedJacks) {
      return 'Active penalty! You must play a 2 or Black Jack to stack, or a Red Jack to cancel.';
    }

    if (allRedJacks) {
      // Red Jack cancels — always valid regardless of top card.
      return null;
    }

    if (allBlackJacks) {
      // Black Jack stacks onto 2-chain — always valid regardless of top card.
      return null;
    }

    if (allTwos) {
      // Any 2 is valid during an active penalty — it stacks regardless of the
      // top card's suit or rank (the penalty chain supersedes normal matching).
      return null;
    }
  }

  final ranks = cards.map((c) => c.effectiveRank).toSet();

  if (ranks.length > 1) {
    // ── Numerical sequence (same suit, consecutive) ──────────────────
    final suits = cards.map((c) => c.effectiveSuit).toSet();
    if (suits.length != 1) {
      return 'Multi-card plays must share the same rank, or form a same-suit sequence.';
    }

    final sorted = [...cards]
      ..sort((a, b) => a.effectiveRank.numericValue
          .compareTo(b.effectiveRank.numericValue));

    bool isConsecutive = true;
    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].effectiveRank.numericValue -
          sorted[i - 1].effectiveRank.numericValue;
      if (diff != 1) {
        isConsecutive = false;
        break;
      }
    }
    if (!isConsecutive) {
      return 'Sequence must be consecutive cards of the same suit.';
    }

    // Leading card (lowest value) validates against the discard.
    return _validateSingle(sorted.first, discardTop, state);
  }

  // ── Same-turn sequential adjacency (Numerical Flow Rule) ──────────────
  // If the player has already played a card this turn, a single follow-up card
  // must be rank-adjacent (±1) to the last card played this turn AND share the
  // same suit. Special cards (Ace, Joker) bypass this via early returns above.
  // Exception: when queenSuitLock is active (covering a Queen) or when an
  // active penalty is in play, this rule does not apply — those states have
  // their own distinct validation rules that already ran above.
  if (state.actionsThisTurn > 0 &&
      state.lastPlayedThisTurn != null &&
      state.queenSuitLock == null &&
      state.activePenaltyCount == 0) {
    final prev = state.lastPlayedThisTurn!;
    final next = cards.first;
    // Only enforce adjacency for non-special cards continuing a same-suit flow.
    final isSpecialOverride = next.effectiveRank == Rank.ace ||
        next.effectiveRank == Rank.queen ||
        next.isJoker;
    if (!isSpecialOverride) {
      final sameSuit = next.effectiveSuit == prev.effectiveSuit;
      final rankDiff = (next.effectiveRank.numericValue -
              prev.effectiveRank.numericValue)
          .abs();
      // Valid follow-ups after a card has been played this turn:
      //   1. Same-suit, adjacent rank (±1): continuing the numerical sequence.
      //   2. Same-rank, any suit (value chain): e.g. sequence ends at 5♠ → 5♥.
      final isConsecutiveSameSuit = sameSuit && rankDiff == 1;
      final isValueChain = next.effectiveRank == prev.effectiveRank;
      if (!isConsecutiveSameSuit && !isValueChain) {
        return 'After playing ${prev.shortLabel}, the next card must be '
            'the ${prev.effectiveSuit.displayName} ranked one above or below '
            '(${prev.effectiveRank.displayLabel}), or match its value.';
      }
    }
  }

  // All cards same rank — validate the first against the discard.
  return _validateSingle(cards.first, discardTop, state);
}

/// Returns `null` if [card] can legally be played on top of [discard].
String? _validateSingle(CardModel card, CardModel discard, GameState state) {
  if (card.isJoker) return null;
  
  // Red Jack acts as a wildcard specifically when cancelling penalties.
  // If there's an active penalty, a Red Jack is always valid.
  if (state.activePenaltyCount > 0 && card.effectiveRank == Rank.jack && !card.isBlackJack) {
    return null;
  }

  if (card.effectiveRank == Rank.ace) return null;

  // Queen suit-lock: must play the locked suit OR another Queen.
  if (state.queenSuitLock != null) {
    if (card.effectiveSuit == state.queenSuitLock) return null;
    if (card.effectiveRank == Rank.queen) return null; // Q->Q chaining is explicitly allowed
    return 'Queen lock active — play a ${state.queenSuitLock!.displayName} card or another Queen.';
  }

  // Active suit lock (from Ace) or default to discard suit.
  final requiredSuit = state.suitLock ?? discard.effectiveSuit;

  if (card.effectiveSuit == requiredSuit) return null;
  if (card.effectiveRank == discard.effectiveRank) return null;

  return 'Must match ${requiredSuit.displayName} suit or ${discard.effectiveRank.displayLabel} rank.';
}

// ── Turn-end validation ───────────────────────────────────────────────────────

/// Returns `null` if the player may legally end their turn, or an error string
/// explaining why not.
///
/// Rules:
///   • The Queen suit-lock must be resolved (covered) before ending.
///   • The player must have taken at least one action (`actionsThisTurn > 0`).
String? validateEndTurn(GameState state) {
  if (state.queenSuitLock != null) {
    return 'Cover Queen first!';
  }
  if (state.actionsThisTurn == 0) {
    return 'Cannot end turn without playing or drawing.';
  }
  return null;
}

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

  for (final card in cards) {
    gs = _applySpecialEffect(gs, card, declaredSuit: declaredSuit);
  }

  // Count this as a valid action for the current player, and record the last
  // card played this turn for same-turn sequential adjacency enforcement.
  gs = gs.copyWith(
    actionsThisTurn: gs.actionsThisTurn + 1,
    lastPlayedThisTurn: cards.last,
  );

  return gs;
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
      return gs.copyWith(suitLock: declaredSuit ?? card.effectiveSuit);

    case Rank.eight: // skip — handled by caller advancing turn twice
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

// ── Turn advancement ──────────────────────────────────────────────────────────

/// Returns the next player's ID, honouring direction and optional skip.
String nextPlayerId({
  required GameState state,
  bool skipExtra = false,
}) {
  final players = state.players;
  final currentIndex =
      players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) return state.currentPlayerId;

  final step = state.direction == PlayDirection.clockwise ? 1 : -1;
  int next = (currentIndex + step) % players.length;
  if (next < 0) next += players.length;

  if (skipExtra) {
    next = (next + step) % players.length;
    if (next < 0) next += players.length;
  }

  return players[next].id;
}

// ── AI opponent (Player 2) ────────────────────────────────────────────────────

/// Greedy AI: plays the best legal card it has, or draws if none are legal.
///
/// The AI also ends its turn automatically after one play/draw (no "End Turn"
/// concept — only the human player has that control).
({GameState state, String description}) aiTakeTurn({
  required GameState state,
  required String aiPlayerId,
  required List<CardModel> Function(int n) cardFactory,
}) {
  final ai = state.players.firstWhere((p) => p.id == aiPlayerId);
  final aiName = ai.displayName; // "Player 2"

  // ── Pending penalty: try to counter first ─────────────────────────
  if (state.activePenaltyCount > 0) {
    // Find a 2 or a Red Jack to counter the penalty
    CardModel? counterCard;
    for (final card in ai.hand) {
      final isCounter = (card.effectiveRank == Rank.two) || 
                        (card.effectiveRank == Rank.jack && !card.isBlackJack);
      if (isCounter && validatePlay(cards: [card], discardTop: state.discardTopCard!, state: state) == null) {
        counterCard = card;
        break; // Found a counter
      }
    }

    if (counterCard == null) {
      // Cannot counter, MUST draw the penalty cards
      final count = state.activePenaltyCount;
      final newState = applyDraw(
        state: state,
        playerId: aiPlayerId,
        count: count,
        cardFactory: cardFactory,
      );
      final next = nextPlayerId(state: newState);
      return (
        state: newState.copyWith(currentPlayerId: next, actionsThisTurn: 0, lastPlayedThisTurn: null),
        description: '$aiName draws $count (penalty)',
      );
    }
    // If we have a counterCard, fall through and let the normal play logic handle it
  }

  // ── Try to find the best legal card ───────────────────────────────
  CardModel? bestCard;
  for (final card in ai.hand) {
    final err = validatePlay(
      cards: [card],
      discardTop: state.discardTopCard!,
      state: state,
    );
    if (err == null) {
      bestCard = card;
      if (_isSpecial(card)) break; // prefer specials
    }
  }

  if (bestCard != null) {
    Suit? declaredSuit;
    if (bestCard.effectiveRank == Rank.ace) {
      declaredSuit = Suit.spades; // AI always declares spades
    }

    var afterPlay = applyPlay(
      state: state,
      playerId: aiPlayerId,
      cards: [bestCard],
      declaredSuit: declaredSuit,
    );

    final label = declaredSuit != null
        ? '${bestCard.shortLabel} → declares ${declaredSuit.displayName}'
        : bestCard.shortLabel;
    final descriptions = <String>['$aiName plays $label'];

    // ── Queen cover: AI must immediately cover before ending turn ──────
    // Keep trying to cover as long as queenSuitLock is active.
    int coverAttempts = 0;
    while (afterPlay.queenSuitLock != null && coverAttempts < 5) {
      coverAttempts++;
      final currentAi = afterPlay.players.firstWhere((p) => p.id == aiPlayerId);
      CardModel? coverCard;
      for (final card in currentAi.hand) {
        if (validatePlay(
              cards: [card],
              discardTop: afterPlay.discardTopCard!,
              state: afterPlay,
            ) == null) {
          coverCard = card;
          break;
        }
      }

      if (coverCard != null) {
        afterPlay = applyPlay(
          state: afterPlay,
          playerId: aiPlayerId,
          cards: [coverCard],
        );
        descriptions.add('  ↳ covers with ${coverCard.shortLabel}');
      } else {
        // Cannot cover — draw 1 card penalty and abort.
        afterPlay = applyDraw(
          state: afterPlay,
          playerId: aiPlayerId,
          count: 1,
          cardFactory: cardFactory,
        );
        descriptions.add('  ↳ no cover — draws 1 (Queen penalty)');
        // Clear queenSuitLock since the draw resolves the obligation.
        afterPlay = afterPlay.copyWith(queenSuitLock: null);
        break;
      }
    }

    final skipTurn = bestCard.effectiveRank == Rank.eight;
    final next = nextPlayerId(state: afterPlay, skipExtra: skipTurn);
    return (
      state: afterPlay.copyWith(currentPlayerId: next, actionsThisTurn: 0, lastPlayedThisTurn: null),
      description: descriptions.join('\n'),
    );
  }

  // ── No legal card — draw one ───────────────────────────────────────
  final afterDraw = applyDraw(
    state: state,
    playerId: aiPlayerId,
    count: 1,
    cardFactory: cardFactory,
  );
  final next = nextPlayerId(state: afterDraw);
  return (
    state: afterDraw.copyWith(currentPlayerId: next, actionsThisTurn: 0, lastPlayedThisTurn: null),
    description: '$aiName draws a card',
  );
}

bool _isSpecial(CardModel c) {
  const specials = {
    Rank.two, Rank.jack, Rank.queen, Rank.king, Rank.ace, Rank.eight,
  };
  return specials.contains(c.effectiveRank) || c.isJoker;
}
