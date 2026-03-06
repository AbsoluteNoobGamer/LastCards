import 'dart:async';
import 'dart:math' as math;

import '../models/card_model.dart';
import '../models/game_state_model.dart';
import '../rules/card_rules.dart';
import '../rules/pickup_chain_rules.dart';
import '../../services/audio_service.dart';
import '../../services/game_sound.dart';

export '../models/card_model.dart';
export '../models/game_state_model.dart';
export '../rules/card_rules.dart' show JokerPlayContext, jokerPlayContextFromCardsPlayed;

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
    if (state.actionsThisTurn == 0) {
      // When a penalty is active, the FIRST card played in the turn must address it.
      if (!isFirstCardValidUnderPenalty(cards.first)) {
        return 'Active penalty! Your first card must be a 2 or Black Jack to stack, or a Red Jack to cancel.';
      }
    }

    // Whether it's the first play or mid-turn, if the play consists ONLY of valid
    // penalty-addressing cards, it bypasses standard normal suit/rank matching
    // against the discard pile and numerical flow rules entirely.
    if (areAllCardsPenaltyAddressing(cards)) {
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

    var sorted = [...cards]..sort((a, b) =>
        a.effectiveRank.numericValue.compareTo(b.effectiveRank.numericValue));

    bool isConsecutive = true;
    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].effectiveRank.numericValue -
          sorted[i - 1].effectiveRank.numericValue;
      if (diff != 1) {
        isConsecutive = false;
        break;
      }
    }

    // Try treating Ace as low (value 1) if high-Ace consecutive check failed.
    if (!isConsecutive && cards.any((c) => c.effectiveRank == Rank.ace)) {
      sorted = [...cards]..sort((a, b) {
          final aVal =
              a.effectiveRank == Rank.ace ? 1 : a.effectiveRank.numericValue;
          final bVal =
              b.effectiveRank == Rank.ace ? 1 : b.effectiveRank.numericValue;
          return aVal.compareTo(bVal);
        });

      isConsecutive = true;
      for (int i = 1; i < sorted.length; i++) {
        final aVal = sorted[i - 1].effectiveRank == Rank.ace
            ? 1
            : sorted[i - 1].effectiveRank.numericValue;
        final bVal = sorted[i].effectiveRank == Rank.ace
            ? 1
            : sorted[i].effectiveRank.numericValue;
        if (bVal - aVal != 1) {
          isConsecutive = false;
          break;
        }
      }
    }

    if (!isConsecutive) {
      return 'Sequence must be consecutive cards of the same suit.';
    }

    // Scenario 2 (Multi-card play involving Ace):
    // If the sequence starts with an Ace, it must match the pre-turn centre suit
    // in order to be a valid *sequence containing an Ace*.
    if (state.actionsThisTurn == 0 && sorted.first.effectiveRank == Rank.ace) {
      if (sorted.first.effectiveSuit != state.preTurnCentreSuit) {
        return 'Invalid sequence: The Ace (${sorted.first.shortLabel}) must match the centre card (${state.preTurnCentreSuit?.displayName}) to start a sequence.';
      }
    }

    // Leading card (lowest value) validates against the discard.
    return _validateSingle(sorted.first, discardTop, state);
  }

  // ── Same-turn sequential adjacency (Numerical Flow Rule) ──────────────
  // If the player has already played a card this turn, a single follow-up card
  // must be rank-adjacent (±1) to the last card played this turn AND share the
  // same suit. Special cards (Joker, Queen) bypass this via early returns above.
  // Exception: when queenSuitLock is active (covering a Queen), this rule does
  // not apply — that state has its own distinct validation rules.
  if (state.actionsThisTurn > 0 &&
      state.lastPlayedThisTurn != null &&
      state.queenSuitLock == null) {
    final prev = state.lastPlayedThisTurn!;
    final next = cards.first;
    // Only enforce adjacency for non-special cards continuing a same-suit flow.
    // Aces are no longer special overrides mid-turn; they must exactly follow numerical flow.
    final isSpecialOverride = next.effectiveRank == Rank.queen || next.isJoker;

    // Penalty chaining bypass:
    // If the previous card was a penalty card (2 or Jack) and the next card is
    // also a penalty-capable card (2 or Jack), they can chain directly
    // regardless of suite/rank adjacencies to build or reset penalties.
    if (!isSpecialOverride && !isPenaltyChain(prev, next)) {
      final sameSuit = next.effectiveSuit == prev.effectiveSuit;
      final rankDiff =
          (next.effectiveRank.numericValue - prev.effectiveRank.numericValue)
              .abs();

      final isTwoAndAce = (prev.effectiveRank == Rank.two &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);

      // Scenario 2 (Sequential Ace play):
      // If the player played an Ace as their first card this turn, and is now trying
      // to continue the sequence, the Ace *must* have matched the pre-turn centre suit.
      if (prev.effectiveRank == Rank.ace && state.cardsPlayedThisTurn == 1) {
        if (prev.effectiveSuit != state.preTurnCentreSuit) {
          return 'Invalid sequence: The Ace (${prev.shortLabel}) must match the original centre card (${state.preTurnCentreSuit?.displayName}) to continue a sequence.';
        }
      }

      print(
          'DEBUG FLOW: prev=${prev.shortLabel} next=${next.shortLabel} sameSuit=$sameSuit rankDiff=$rankDiff isTwoAndAce=$isTwoAndAce');

      // Valid follow-ups after a card has been played this turn:
      //   1. Same-suit, adjacent rank (±1 or Ace-2): continuing the numerical sequence.
      //   2. Same-rank, any suit (value chain): e.g. sequence ends at 5♠ → 5♥.
      final isConsecutiveSameSuit = sameSuit && (rankDiff == 1 || isTwoAndAce);
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

/// Returns a list of exactly which standard cards a Joker can legally represent
/// given the current [state] and [discardTop].
///
/// Joker specific role capabilities (per user rules):
/// 1. Same rank as discard, different suit.
/// 2. Adjacent rank (±1 or Ace=1 for 2) as discard, same suit.
/// 3. If discard is a penalty card and penalty active, can also stack 2s (if 2 chain)
///    or Red Jacks/Black Jacks depending on standard penalty rules.
List<CardModel> getValidJokerOptions({
  required GameState state,
  required CardModel discardTop,
  JokerPlayContext? context,
  CardModel? contextTopCard,
}) {
  final List<CardModel> validOptions = [];
  final playContext =
      context ?? jokerPlayContextFromCardsPlayed(state.actionsThisTurn);
  final anchorCard = contextTopCard ??
      (playContext == JokerPlayContext.midTurnContinuance &&
              state.lastPlayedThisTurn != null
          ? state.lastPlayedThisTurn!
          : discardTop);
  final targetRank = anchorCard.effectiveRank;
  final targetSuit = anchorCard.effectiveSuit;
  final activeSequenceSuit =
      playContext == JokerPlayContext.midTurnContinuance ? targetSuit : null;

  for (final suit in Suit.values) {
    for (final rank in Rank.values) {
      if (rank == Rank.joker) continue; // Joker can't mimic a Joker
      if (rank == targetRank && suit == targetSuit) {
        continue; // Cannot be exact dupe
      }

      bool isValidMatch = false;

      // Check sequence continuation explicitly
      bool isSequenceContinuation = false;
      if (activeSequenceSuit != null && suit == activeSequenceSuit) {
        if (targetRank == Rank.ace) {
          isSequenceContinuation = rank == Rank.two;
        } else if (rank == Rank.ace) {
          isSequenceContinuation = targetRank == Rank.two;
        } else {
          final diff = (rank.numericValue - targetRank.numericValue).abs();
          isSequenceContinuation = diff == 1;
        }
      }

      // 3. Penalty Rules
      if (state.activePenaltyCount > 0) {
        // During an active penalty, standard adjacent/rank matching doesn't apply.
        // A player MUST address the penalty. Valid cards are 2s, Black Jacks, and Red Jacks.
        // So a Joker can mimic ANY 2, ANY Black Jack, or ANY Red Jack (except the exact dupe).
        // Sequence continuations of the active sequence are also allowed.
        final isTwo = rank == Rank.two;
        final isBlackJack =
            rank == Rank.jack && (suit == Suit.clubs || suit == Suit.spades);
        final isRedJack =
            rank == Rank.jack && (suit == Suit.hearts || suit == Suit.diamonds);

        isValidMatch =
            isTwo || isBlackJack || isRedJack || isSequenceContinuation;
      } else {
        if (playContext == JokerPlayContext.turnStarter) {
          // 1. TURN-START (first play after opponent ends):
          // Joker can mimic any card of the same suit OR any card of the same rank.
          if (suit == targetSuit || rank == targetRank) {
            isValidMatch = true;
          }
        } else {
          // 2. MID-TURN CONTINUANCE:
          // Joker can mimic adjacent rank of same suit OR same rank.
          final isSameValueOtherSuit = rank == targetRank && suit != targetSuit;
          if (isSameValueOtherSuit || isSequenceContinuation) {
            isValidMatch = true;
          }
        }
      }

      if (isValidMatch) {
        validOptions.add(CardModel(
          id: 'joker_opt_${suit.name}_${rank.name}',
          suit: suit,
          rank: rank,
        ));
      }
    }
  }

  return validOptions;
}

/// Returns `null` if [card] can legally be played on top of [discard].
String? _validateSingle(CardModel card, CardModel discard, GameState state) {
  if (card.isJoker) return null;

  // Red Jack acts as a wildcard specifically when cancelling penalties.
  // If there's an active penalty, a Red Jack is always valid.
  if (state.activePenaltyCount > 0 &&
      card.effectiveRank == Rank.jack &&
      !card.isBlackJack) {
    return null;
  }

  // Wildcard Ace: only valid if it's the very first card played this turn.
  if (state.actionsThisTurn == 0 && card.effectiveRank == Rank.ace) {
    return null;
  }

  // Penalty substitution: Any penalty card (2 or Jack) can be played on top
  // of any other penalty card (2 or Jack) to build or reset a penalty chain.
  final discardIsPenalty =
      discard.effectiveRank == Rank.two || discard.effectiveRank == Rank.jack;
  final cardIsPenalty =
      card.effectiveRank == Rank.two || card.effectiveRank == Rank.jack;
  if (discardIsPenalty && cardIsPenalty) {
    return null;
  }

  // Queen suit-lock: must play the locked suit OR another Queen.
  if (state.queenSuitLock != null) {
    if (card.effectiveSuit == state.queenSuitLock) return null;
    if (card.effectiveRank == Rank.queen) {
      return null; // Q->Q chaining is explicitly allowed
    }
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
  if (state.pendingJokerResolution) {
    return 'Resolve Joker selection first.';
  }
  if (state.queenSuitLock != null && state.lastPlayedThisTurn != null) {
    return 'Cover Queen or draw a card first!';
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

  if (cards.isNotEmpty) {
    unawaited(AudioService.instance.playSound(GameSound.cardPlace));
    for (final card in cards) {
      final specialSound = _specialSoundFor(card);
      if (specialSound != null) {
        unawaited(AudioService.instance.playSound(specialSound));
      }
    }
  }

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
  if (shouldClearPenaltyAfterPlay(lastCard)) {
    gs = gs.copyWith(activePenaltyCount: 0);
  }

  // Count this as a valid action for the current player, and record the last
  // card played this turn for same-turn sequential adjacency enforcement.
  gs = gs.copyWith(
    actionsThisTurn: gs.actionsThisTurn + 1,
    cardsPlayedThisTurn: gs.cardsPlayedThisTurn + cards.length,
    lastPlayedThisTurn: lastCard,
  );

  return gs;
}

/// Applies the opening face-up discard card effect at game start.
///
/// This is used once during initialization before any player action.
GameState applyInitialFaceUpEffect({
  required GameState state,
}) {
  final top = state.discardTopCard;
  if (top == null) return state;

  switch (top.effectiveRank) {
    case Rank.two:
      return state.copyWith(activePenaltyCount: state.activePenaltyCount + 2);
    case Rank.jack:
      if (top.isBlackJack) {
        return state.copyWith(activePenaltyCount: state.activePenaltyCount + 5);
      }
      return state.copyWith(activePenaltyCount: 0);
    case Rank.king:
      return state.copyWith(
        direction: state.direction == PlayDirection.clockwise
            ? PlayDirection.counterClockwise
            : PlayDirection.clockwise,
      );
    case Rank.queen:
      return state.copyWith(queenSuitLock: top.effectiveSuit);
    case Rank.ace:
      // At startup there is no declaration interaction, so lock to Ace suit.
      return state.copyWith(suitLock: top.effectiveSuit);
    case Rank.eight:
      return state.copyWith(activeSkipCount: state.activeSkipCount + 1);
    case Rank.joker:
      // Startup joker must be resolved so opening plays are not blocked.
      // Randomize to any non-joker rank and any suit (including specials).
      final rng = math.Random();
      final nonJokerRanks = Rank.values
          .where((rank) => rank != Rank.joker)
          .toList(growable: false);
      final randomRank = nonJokerRanks[rng.nextInt(nonJokerRanks.length)];
      final randomSuit =
          Suit.values[rng.nextInt(Suit.values.length)];
      final resolvedTop = top.copyWith(
        jokerDeclaredRank: randomRank,
        jokerDeclaredSuit: randomSuit,
      );
      return applyInitialFaceUpEffect(state: state.copyWith(
        discardTopCard: resolvedTop,
        preTurnCentreSuit: resolvedTop.effectiveSuit,
      ));
    default:
      return state;
  }
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
  if (drawn.isNotEmpty) {
    unawaited(AudioService.instance.playSound(GameSound.cardDraw));
    if (state.activePenaltyCount > 0) {
      unawaited(AudioService.instance.playSound(GameSound.penaltyDraw));
    }
  }
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

GameSound? _specialSoundFor(CardModel card) {
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

// ── Turn advancement ──────────────────────────────────────────────────────────

/// Returns the next player's ID, honouring direction and optional skip.
String nextPlayerId({
  required GameState state,
}) {
  final players = state.players;
  final currentIndex = players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) return state.currentPlayerId;

  // In a 2-player game, playing a King (Reverse) acts as a Skip.
  // The player gets another turn immediately.
  final lastCard = state.lastPlayedThisTurn;
  final isKingPlayed = lastCard != null && lastCard.effectiveRank == Rank.king;
  if (players.length == 2 && isKingPlayed) {
    return state.currentPlayerId;
  }

  // Effect order: when both skip and reverse are present, skip resolves first.
  // Since reverse has already updated `state.direction`, use the pre-reverse
  // direction for this immediate advance, then keep the reversed direction for
  // subsequent turns.
  final hasSkip = state.activeSkipCount > 0;
  final kingPlayedThisTurn =
      state.lastPlayedThisTurn?.effectiveRank == Rank.king;
  final directionForAdvance = (hasSkip && kingPlayedThisTurn)
      ? (state.direction == PlayDirection.clockwise
          ? PlayDirection.counterClockwise
          : PlayDirection.clockwise)
      : state.direction;

  final step = directionForAdvance == PlayDirection.clockwise ? 1 : -1;
  int next = currentIndex;
  final advances = 1 + state.activeSkipCount;

  for (int i = 0; i < advances; i++) {
    next = (next + step) % players.length;
    if (next < 0) next += players.length;
  }

  return players[next].id;
}
