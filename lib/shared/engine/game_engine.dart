import 'dart:math' as math;

import '../models/card_model.dart';
import '../models/game_state_model.dart';
import '../models/player_model.dart';
import '../rules/card_rules.dart';
import '../rules/pickup_chain_rules.dart';
import '../rules/last_cards_rules.dart' show canHandClearInOneTurnHandOnly;
import '../rules/win_condition_rules.dart' show needsUndeclaredLastCardsDraw;
import 'shuffle_utils.dart';

export '../models/card_model.dart';
export '../models/game_state_model.dart';
export '../models/player_model.dart';
export '../rules/card_rules.dart' show JokerPlayContext, jokerPlayContextFromCardsPlayed;

/// In a **2-player** game, a played [Rank.king] reverses direction onto the same
/// seat. The next card is validated like a **new lead** against the discard top
/// (the King), not as numerical-flow continuation off the King.
///
/// Uses [CardModel.effectiveRank], so a **Joker declared as King** matches a
/// natural King here — same as the 2-player King skip in [nextPlayerId]. A **same-turn
/// stack of multiple Kings** leaves [GameState.lastPlayedThisTurn] as the last
/// King; direction may reverse multiple times, but the follow-up still uses this
/// reset when the final played card is a King.
bool twoPlayerKingResetsNumericalFlow(GameState state) {
  return state.players.length == 2 &&
      state.lastPlayedThisTurn?.effectiveRank == Rank.king;
}

/// Shared inputs for Joker declaration (client sheet + server validation).
///
/// [anchor] is the logical top card for [getValidJokerOptions] (`contextTopCard`).
/// [effectivePlayContext] is what the UI should show (turn starter vs mid-turn),
/// including the 2-player King numerical-flow reset.
({
  CardModel anchor,
  JokerPlayContext resolvedContext,
  JokerPlayContext effectivePlayContext,
  Suit? activeSequenceSuit,
}) resolveJokerPlayInputs({
  required GameState state,
  required CardModel discardTop,
}) {
  final resolvedContext =
      jokerPlayContextFromCardsPlayed(state.cardsPlayedThisTurn);
  final effectivePlayContext =
      resolvedContext == JokerPlayContext.midTurnContinuance &&
              twoPlayerKingResetsNumericalFlow(state)
          ? JokerPlayContext.turnStarter
          : resolvedContext;
  final anchor = resolvedContext == JokerPlayContext.midTurnContinuance &&
          state.lastPlayedThisTurn != null &&
          !twoPlayerKingResetsNumericalFlow(state)
      ? state.lastPlayedThisTurn!
      : discardTop;
  final activeSequenceSuit =
      effectivePlayContext == JokerPlayContext.midTurnContinuance
          ? anchor.effectiveSuit
          : null;
  return (
    anchor: anchor,
    resolvedContext: resolvedContext,
    effectivePlayContext: effectivePlayContext,
    activeSequenceSuit: activeSequenceSuit,
  );
}

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
///   • Exception: in a **2-player** game, after a played [Rank.king] (same seat
///     again), the immediate next play matches the discard top with normal
///     suit/rank rules — numerical flow does not step from the King.
///     That “normal match” is **not** the first-card Ace wild: [Rank.ace] must
///     match the King’s suit (or rank) like any other card once the player has
///     already played this turn.
///
/// The leading card (lowest for ascending, highest for descending) must satisfy
/// the normal suit/rank match against the discard top.
String? validatePlay({
  required List<CardModel> cards,
  required CardModel discardTop,
  required GameState state,
}) {
  if (cards.isEmpty) return 'No cards selected.';

  if (state.isHardcore) {
    final p = state.playerById(state.currentPlayerId);
    if (p != null && p.hand.length == cards.length) {
      if (cards.last.isJoker) {
        return 'Hardcore: cannot play a Joker as your last card.';
      }
      if (cards.last.effectiveRank == Rank.ace) {
        return 'Hardcore: cannot win on an Ace.';
      }
    }
  }

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
      final prev = sorted[i - 1];
      final next = sorted[i];
      final diff = next.effectiveRank.numericValue - prev.effectiveRank.numericValue;
      if (diff == 1) continue;
      final isTwoAndAce = (prev.effectiveRank == Rank.two &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);
      final isAceAndKing = (prev.effectiveRank == Rank.king &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.king);
      if (!isTwoAndAce && !isAceAndKing) {
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
        final prev = sorted[i - 1];
        final next = sorted[i];
        final aVal = prev.effectiveRank == Rank.ace
            ? 1
            : prev.effectiveRank.numericValue;
        final bVal =
            next.effectiveRank == Rank.ace ? 1 : next.effectiveRank.numericValue;
        if (bVal - aVal == 1) continue;
        final isTwoAndAce = (prev.effectiveRank == Rank.two &&
                next.effectiveRank == Rank.ace) ||
            (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);
        final isAceAndKing = (prev.effectiveRank == Rank.king &&
                next.effectiveRank == Rank.ace) ||
            (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.king);
        if (!isTwoAndAce && !isAceAndKing) {
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
      state.queenSuitLock == null &&
      !twoPlayerKingResetsNumericalFlow(state)) {
    final prev = state.lastPlayedThisTurn!;
    final next = cards.first;
    // Only enforce adjacency for non-special cards continuing a same-suit flow.
    // Aces are no longer special overrides mid-turn; they must exactly follow numerical flow.
    final isSpecialOverride = next.effectiveRank == Rank.queen || next.isJoker;

    // Penalty chaining bypass (when [GameState.isPenaltyChainActive]):
    // If the previous card was a penalty card (2 or Jack) and the next card is
    // also a penalty-capable card (2 or Jack), they can chain directly
    // regardless of suit/rank adjacencies to build or reset penalties.
    if (!isSpecialOverride &&
        !(state.isPenaltyChainActive && isPenaltyChain(prev, next))) {
      final sameSuit = next.effectiveSuit == prev.effectiveSuit;
      final rankDiff =
          (next.effectiveRank.numericValue - prev.effectiveRank.numericValue)
              .abs();

      final isTwoAndAce = (prev.effectiveRank == Rank.two &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);
      final isAceAndKing = (prev.effectiveRank == Rank.king &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.king);

      // Scenario 2 (Sequential Ace play):
      // If the player played an Ace as their first card this turn, and is now trying
      // to continue the sequence, the Ace *must* have matched the pre-turn centre suit.
      if (prev.effectiveRank == Rank.ace &&
          state.cardsPlayedThisTurn == 1 &&
          next.effectiveRank != Rank.ace) {
        if (prev.effectiveSuit != state.preTurnCentreSuit) {
          return 'Invalid sequence: The Ace (${prev.shortLabel}) must match the original centre card (${state.preTurnCentreSuit?.displayName}) to continue a sequence.';
        }
      }

      // Valid follow-ups after a card has been played this turn:
      //   1. Same-suit, adjacent rank (±1, Ace-2, or Ace-K wrap): continuing the numerical sequence.
      //   2. Same-rank, any suit (value chain): e.g. sequence ends at 5♠ → 5♥.
      final isConsecutiveSameSuit =
          sameSuit && (rankDiff == 1 || isTwoAndAce || isAceAndKing);
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
/// 3. If discard is a penalty card and [GameState.isPenaltyChainActive], can also
///    stack 2s or Red/Black Jacks per penalty-on-penalty rules.
///
/// **2-player King:** When [twoPlayerKingResetsNumericalFlow] is true, Joker
/// options use turn-starter matching (same suit or same rank as anchor), not
/// mid-turn adjacency only.
///
/// The [context] argument must be the **raw** play context (e.g.
/// [resolveJokerPlayInputs] `resolvedContext` or [jokerPlayContextFromCardsPlayed]),
/// not a caller-pre-upgraded [JokerPlayContext.turnStarter]. Passing an already
/// upgraded `turnStarter` would skip the internal 2p-King check and use the wrong
/// anchor derivation when [contextTopCard] is omitted.
List<CardModel> getValidJokerOptions({
  required GameState state,
  required CardModel discardTop,
  JokerPlayContext? context,
  CardModel? contextTopCard,
}) {
  final List<CardModel> validOptions = [];
  final resolvedContext =
      context ?? jokerPlayContextFromCardsPlayed(state.cardsPlayedThisTurn);
  final effectivePlayContext =
      resolvedContext == JokerPlayContext.midTurnContinuance &&
              twoPlayerKingResetsNumericalFlow(state)
          ? JokerPlayContext.turnStarter
          : resolvedContext;
  final anchorCard = contextTopCard ??
      (resolvedContext == JokerPlayContext.midTurnContinuance &&
              state.lastPlayedThisTurn != null &&
              !twoPlayerKingResetsNumericalFlow(state)
          ? state.lastPlayedThisTurn!
          : discardTop);
  final targetRank = anchorCard.effectiveRank;
  final targetSuit =
      (effectivePlayContext == JokerPlayContext.turnStarter &&
              state.suitLock != null)
          ? state.suitLock!
          : anchorCard.effectiveSuit;
  // Exact-dupe exclusion must match [anchorCard] when no Ace suit lock, or the
  // declared suit when locked (same rank + locked suit), not the anchor's suit.
  final duplicateExclusionSuit =
      (effectivePlayContext == JokerPlayContext.turnStarter &&
              state.suitLock != null)
          ? state.suitLock!
          : anchorCard.effectiveSuit;
  final activeSequenceSuit =
      effectivePlayContext == JokerPlayContext.midTurnContinuance
          ? targetSuit
          : null;

  for (final suit in Suit.values) {
    for (final rank in Rank.values) {
      if (rank == Rank.joker) continue; // Joker can't mimic a Joker
      if (rank == targetRank && suit == duplicateExclusionSuit) {
        continue; // Cannot be exact dupe
      }

      bool isValidMatch = false;

      // Check sequence continuation explicitly
      bool isSequenceContinuation = false;
      if (activeSequenceSuit != null && suit == activeSequenceSuit) {
        if (targetRank == Rank.ace) {
          isSequenceContinuation =
              rank == Rank.two || rank == Rank.king;
        } else if (rank == Rank.ace) {
          isSequenceContinuation =
              targetRank == Rank.two || targetRank == Rank.king;
        } else {
          final diff = (rank.numericValue - targetRank.numericValue).abs();
          isSequenceContinuation = diff == 1;
        }
      }

      // 3. Penalty Rules
      final discardIsPenalty =
          discardTop.effectiveRank == Rank.two ||
              discardTop.effectiveRank == Rank.jack;
      final candidateIsPenalty =
          rank == Rank.two || rank == Rank.jack;

      if (state.isPenaltyChainActive &&
          discardIsPenalty &&
          candidateIsPenalty) {
        // Penalty-on-penalty: mirrors _validateSingle where any penalty card
        // can be played on any other penalty card regardless of queen lock.
        isValidMatch = true;
      } else if (state.queenSuitLock != null) {
        // Mirrors _validateSingle: Queen lock replaces suit/rank rules until
        // resolved (penalty-on-penalty stacking is handled before Queen lock).
        // When the pick-up chain is live, [validatePlay] lets plays that are
        // only penalty-addressing cards bypass queen lock — mirror that here.
        if (suit == state.queenSuitLock ||
            rank == Rank.queen ||
            (state.isPenaltyChainActive && candidateIsPenalty)) {
          isValidMatch = true;
        }
      } else if (state.activePenaltyCount > 0) {
        // Use [activePenaltyCount] only here (not [isPenaltyChainActive]): when the
        // draw count is zero but the chain is still live after a Red Jack, the player
        // is not forced into “penalty-only” Joker modes and normal turn-start options apply.
        // While a draw is pending, standard adjacent/rank matching doesn't apply.
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
        if (effectivePlayContext == JokerPlayContext.turnStarter) {
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
  // Valid while a draw is pending or the pick-up chain is still live.
  if (state.isPenaltyChainActive &&
      card.effectiveRank == Rank.jack &&
      !card.isBlackJack) {
    return null;
  }

  // Wildcard Ace: only valid if it's the very first card played this turn.
  if (state.actionsThisTurn == 0 && card.effectiveRank == Rank.ace) {
    return null;
  }

  // Penalty substitution when the chain is live ([isPenaltyChainActive]): any
  // penalty card (2 or Jack) on any other penalty card (2 or Jack) to build or
  // reset the chain, including after a Red Jack zeros the draw count.
  final discardIsPenalty =
      discard.effectiveRank == Rank.two || discard.effectiveRank == Rank.jack;
  final cardIsPenalty =
      card.effectiveRank == Rank.two || card.effectiveRank == Rank.jack;
  if (state.isPenaltyChainActive && discardIsPenalty && cardIsPenalty) {
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

/// Whether the End Turn control should be available in the UI (before any
/// Ace suit sheet). Use [validateEndTurn] when actually committing end-turn.
bool canEndTurnButton(GameState state) {
  if (state.pendingJokerResolution) return false;
  if (state.queenSuitLock != null && state.lastPlayedThisTurn != null) {
    return false;
  }
  if (state.actionsThisTurn == 0) return false;
  return true;
}

/// Returns `null` if the player may legally end their turn, or an error string
/// explaining why not.
///
/// Rules:
///   • The Queen suit-lock must be resolved (covered) before ending.
///   • The player must have taken at least one action (`actionsThisTurn > 0`).
///   • A lone Ace on the pile this turn requires a declared suit ([suitLock])
///     before the turn can end (shared Ace rule — offline and online).
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
  if (state.discardTopCard?.effectiveRank == Rank.ace &&
      state.cardsPlayedThisTurn == 1 &&
      state.suitLock == null) {
    return 'Choose a suit for your Ace before ending your turn.';
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
    discardPileHistory: [
      if (gs.discardTopCard != null) gs.discardTopCard!,
      ...gs.discardPileHistory,
    ].take(5).toList(),
    discardTopCard: cards.last,
    suitLock: null,
    queenSuitLock: null,
  );

  // Ace declaration and special effects (sound is played by the UI layer).
  final isWildAcePlay =
      state.actionsThisTurn == 0 && cards.first.effectiveRank == Rank.ace;

  for (final card in cards) {
    final useDeclaredSuit = isWildAcePlay && card.id == cards.first.id;
    // Natural wild Ace passes [declaredSuit] from the suit picker. Joker-as-Ace
    // encodes the chosen suit on the card ([effectiveSuit]); callers often omit
    // [declaredSuit] — mirror [resolveJokerPlay] by falling back for jokers only.
    final suitForAceEffect = useDeclaredSuit
        ? (declaredSuit ?? (card.isJoker ? card.effectiveSuit : null))
        : null;
    gs = _applySpecialEffect(gs, card, declaredSuit: suitForAceEffect);
  }

  // Sequence Penalty Override: If the final card of the play is not a penalty
  // generating card (like a 2 or Black Jack), any accumulated penalty is canceled.
  // This rewards players for continuing a numerical sequence out of a penalty.
  final lastCard = cards.last;
  if (shouldClearPenaltyAfterPlay(lastCard)) {
    final redJackKeepsChainLive = lastCard.effectiveRank == Rank.jack &&
        !lastCard.isBlackJack;
    gs = gs.copyWith(
      activePenaltyCount: 0,
      // Red Jack zeros the draw count but keeps the pick-up chain live for matching.
      penaltyChainLive: redJackKeepsChainLive ? gs.penaltyChainLive : false,
    );
  }

  // Eight Skip Cancellation: if the last card played is not an Eight, any skip
  // count accumulated by Eights earlier this turn is reset to zero.
  // A valid non-Eight follow-up after Eight(s) cancels the skip effect entirely.
  if (lastCard.effectiveRank != Rank.eight && gs.activeSkipCount > 0) {
    gs = gs.copyWith(activeSkipCount: 0);
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
      return state.copyWith(
        activePenaltyCount: state.activePenaltyCount + 2,
        penaltyChainLive: true,
      );
    case Rank.jack:
      if (top.isBlackJack) {
        return state.copyWith(
          activePenaltyCount: state.activePenaltyCount + 5,
          penaltyChainLive: true,
        );
      }
      return state.copyWith(activePenaltyCount: 0, penaltyChainLive: true);
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
///
/// Because a raw Joker hits the Sequence Penalty Override and Eight Skip
/// Cancellation paths inside [applyPlay] (it is neither a 2/Jack nor an 8),
/// we save and restore [activePenaltyCount], [penaltyChainLive], and
/// [activeSkipCount] so the penalty/skip chain is preserved for
/// [resolveJokerPlay] to act on.
GameState beginJokerPlay({
  required GameState state,
  required String playerId,
  required CardModel jokerCard,
}) {
  final savedPenalty = state.activePenaltyCount;
  final savedChainLive = state.penaltyChainLive;
  final savedSkip = state.activeSkipCount;
  final played =
      applyPlay(state: state, playerId: playerId, cards: [jokerCard]);
  return played.copyWith(
    pendingJokerResolution: true,
    activePenaltyCount: savedPenalty,
    penaltyChainLive: savedChainLive,
    activeSkipCount: savedSkip,
  );
}

/// Finalizes a previously committed Joker play after the user picks a represented card.
///
/// After updating the discard top, applies the special effect of the resolved
/// card (e.g. Joker declared as 2 adds penalty, as King reverses direction,
/// as 8 applies skip, etc.), then runs the same Sequence Penalty Override and
/// Eight Skip Cancellation that [applyPlay] performs so that online (server)
/// and offline (client) paths produce identical state.
GameState resolveJokerPlay({
  required GameState state,
  required CardModel resolvedJokerCard,
}) {
  var resolved = state.copyWith(
    discardTopCard: resolvedJokerCard,
    lastPlayedThisTurn: resolvedJokerCard,
    pendingJokerResolution: false,
  );
  // Apply the special effect of the card the Joker was declared as.
  resolved = _applySpecialEffect(
    resolved,
    resolvedJokerCard,
    declaredSuit: resolvedJokerCard.effectiveSuit,
  );

  // Sequence Penalty Override: mirror applyPlay — if the resolved card is not
  // a penalty-generating card, clear any accumulated penalty.
  if (shouldClearPenaltyAfterPlay(resolvedJokerCard)) {
    final redJackKeepsChainLive = resolvedJokerCard.effectiveRank == Rank.jack &&
        !resolvedJokerCard.isBlackJack;
    resolved = resolved.copyWith(
      activePenaltyCount: 0,
      penaltyChainLive:
          redJackKeepsChainLive ? resolved.penaltyChainLive : false,
    );
  }

  // Eight Skip Cancellation: mirror applyPlay — if the resolved card is not
  // an Eight, clear any accumulated skip count.
  if (resolvedJokerCard.effectiveRank != Rank.eight &&
      resolved.activeSkipCount > 0) {
    resolved = resolved.copyWith(activeSkipCount: 0);
  }

  return resolved;
}

GameState _applySpecialEffect(
  GameState gs,
  CardModel card, {
  Suit? declaredSuit,
}) {
  switch (card.effectiveRank) {
    case Rank.two:
      return gs.copyWith(
        activePenaltyCount: gs.activePenaltyCount + 2,
        penaltyChainLive: true,
      );

    case Rank.jack:
      if (card.isBlackJack) {
        return gs.copyWith(
          activePenaltyCount: gs.activePenaltyCount + 5,
          penaltyChainLive: true,
        );
      } else {
        return gs.copyWith(
          activePenaltyCount: 0,
          penaltyChainLive: true,
        ); // Red Jack cancels draw count; chain stays live for matching
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
/// active draw penalty and the live pick-up chain for matching.
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
    penaltyChainLive: false,
    actionsThisTurn: state.actionsThisTurn + 1,
  );
}

/// Draws [count] cards for a Last Cards bluff penalty without consuming the
/// recipient's voluntary turn action.
///
/// On the server, bluff draws run before [advanceTurn] while [currentPlayerId]
/// is still the outgoing player; [applyDraw]'s [actionsThisTurn] bump is cleared
/// by [advanceTurn]. Offline, penalties run **after** [advanceTurn] for the
/// penalized player — use this instead of [applyDraw] so [actionsThisTurn]
/// stays 0 and draw/play UI remains available.
GameState applyLastCardsBluffPenaltyDraw({
  required GameState state,
  required String playerId,
  required int count,
  required List<CardModel> Function(int n) cardFactory,
}) {
  return applyDraw(
    state: state,
    playerId: playerId,
    count: count,
    cardFactory: cardFactory,
  ).copyWith(actionsThisTurn: 0);
}

/// Draws one card when [playerId] emptied their hand without Last Cards
/// declaration (non-Bust). No-op if not needed.
GameState applyUndeclaredLastCardsDraw({
  required GameState state,
  required String playerId,
  bool isBustMode = false,
  required List<CardModel> Function(int n) cardFactory,
}) {
  if (!needsUndeclaredLastCardsDraw(
    state: state,
    playerId: playerId,
    isBustMode: isBustMode,
  )) {
    return state;
  }
  return applyDraw(
    state: state,
    playerId: playerId,
    count: 1,
    cardFactory: cardFactory,
  );
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

/// Like [nextPlayerId], but never returns [excludePlayerId].
///
/// Used when [excludePlayerId] is being removed mid-session: skip math can
/// otherwise wrap the turn marker back onto that seat while they still appear
/// in the pre-removal [state.players] list.
String nextPlayerIdExcluding({
  required GameState state,
  required String excludePlayerId,
}) {
  final players = state.players;
  final n = players.length;
  if (n == 0) return excludePlayerId;

  final base = nextPlayerId(state: state);
  if (base != excludePlayerId) return base;

  final lastCard = state.lastPlayedThisTurn;
  final isKingPlayed = lastCard != null && lastCard.effectiveRank == Rank.king;
  if (n == 2 && isKingPlayed) {
    return players.firstWhere((p) => p.id != excludePlayerId).id;
  }

  final currentIndex = players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) {
    return players.firstWhere((p) => p.id != excludePlayerId).id;
  }

  final hasSkip = state.activeSkipCount > 0;
  final kingPlayedThisTurn =
      state.lastPlayedThisTurn?.effectiveRank == Rank.king;
  final directionForAdvance = (hasSkip && kingPlayedThisTurn)
      ? (state.direction == PlayDirection.clockwise
          ? PlayDirection.counterClockwise
          : PlayDirection.clockwise)
      : state.direction;

  final step = directionForAdvance == PlayDirection.clockwise ? 1 : -1;
  var idx = currentIndex;
  final advances = 1 + state.activeSkipCount;

  for (int i = 0; i < advances; i++) {
    idx = (idx + step) % n;
    if (idx < 0) idx += n;
  }

  for (var guard = 0; guard < n && players[idx].id == excludePlayerId; guard++) {
    idx = (idx + step) % n;
    if (idx < 0) idx += n;
  }

  return players[idx].id;
}

/// Human-readable name for who goes after [state.currentPlayerId] ends this turn,
/// reflecting Eights (skip), King (reverse), and 2-player King (same again).
///
/// [viewerPlayerId] uses that seat's [PlayerModel.displayName] when it matches.
String nextPlayerAfterTurnLabel({
  required GameState state,
  required String viewerPlayerId,
}) {
  if (state.players.isEmpty) return '';
  final nextId = nextPlayerId(state: state);
  final curId = state.currentPlayerId;
  String label(String id) {
    if (id == viewerPlayerId) {
      return state.playerById(id)?.displayName ?? 'You';
    }
    return state.playerById(id)?.displayName ?? id;
  }
  if (nextId == curId) {
    return '${label(nextId)} again';
  }
  return label(nextId);
}

// ── Shared deck builder ───────────────────────────────────────────────────────

/// Returns a freshly shuffled 54-card deck with stable, human-readable IDs.
///
/// Contains 52 standard cards (all suits × all non-joker ranks) plus two
/// Jokers (`joker_r` hearts, `joker_b` spades). Used by both the offline
/// client and the multiplayer server so card IDs are always in sync.
List<CardModel> buildShuffledDeck({int? seed, math.Random? random}) {
  const ranks = [
    Rank.two, Rank.three, Rank.four, Rank.five, Rank.six, Rank.seven,
    Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen, Rank.king,
    Rank.ace,
  ];
  const suits = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

  final deck = <CardModel>[];
  for (final suit in suits) {
    for (final rank in ranks) {
      deck.add(CardModel(
        id: '${rank.name}_${suit.name}',
        rank: rank,
        suit: suit,
      ));
    }
  }
  deck.add(const CardModel(id: 'joker_r', rank: Rank.joker, suit: Suit.hearts));
  deck.add(const CardModel(id: 'joker_b', rank: Rank.joker, suit: Suit.spades));

  fisherYatesShuffle(deck, seed: seed, random: random);
  return deck;
}

/// The same 54 cards as [buildShuffledDeck] but in deterministic suit/rank
/// order (plus jokers last). Used to reconcile which physical cards must be
/// returned to the draw pile when a leaver's [PlayerModel.hand] is empty but
/// [PlayerModel.cardCount] is not.
List<CardModel> standardFiftyFourDeckInCanonicalOrder() {
  const ranks = [
    Rank.two, Rank.three, Rank.four, Rank.five, Rank.six, Rank.seven,
    Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen, Rank.king,
    Rank.ace,
  ];
  const suits = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

  final deck = <CardModel>[];
  for (final suit in suits) {
    for (final rank in ranks) {
      deck.add(CardModel(
        id: '${rank.name}_${suit.name}',
        rank: rank,
        suit: suit,
      ));
    }
  }
  deck.add(const CardModel(id: 'joker_r', rank: Rank.joker, suit: Suit.hearts));
  deck.add(const CardModel(id: 'joker_b', rank: Rank.joker, suit: Suit.spades));
  return deck;
}

/// Resolves which card objects to shuffle into the server's draw pile when a
/// standard-mode player is removed.
///
/// When [authoritativeDrawPile] is null (e.g. unit tests without a pile),
/// returns [removed.hand] only.
///
/// When non-null, if [removed.hand.length] equals [removed.cardCount], returns
/// a copy of the hand. Otherwise infers the missing cards as those in the full
/// 54-card manifest not present in [authoritativeDrawPile], discard storage,
/// [authoritativeDiscardTop], or any remaining player's hand.
List<CardModel> leaverCardsToReturnToDrawPile({
  required PlayerModel removed,
  required GameState stateWithoutLeaver,
  List<CardModel>? authoritativeDrawPile,
  List<CardModel>? authoritativeDiscardUnderTop,
  CardModel? authoritativeDiscardTop,
}) {
  final n = removed.cardCount;
  if (n <= 0) return [];

  if (authoritativeDrawPile == null) {
    return List<CardModel>.from(removed.hand);
  }

  if (removed.hand.length == n) {
    return List<CardModel>.from(removed.hand);
  }

  final top =
      authoritativeDiscardTop ?? stateWithoutLeaver.discardTopCard;

  final used = <String>{};
  if (top != null) used.add(top.id);
  for (final c in authoritativeDiscardUnderTop ?? const <CardModel>[]) {
    used.add(c.id);
  }
  for (final c in authoritativeDrawPile) {
    used.add(c.id);
  }
  for (final p in stateWithoutLeaver.players) {
    for (final c in p.hand) {
      used.add(c.id);
    }
  }

  final fromHand = List<CardModel>.from(removed.hand);
  for (final c in fromHand) {
    used.add(c.id);
  }

  var need = n - fromHand.length;
  if (need <= 0) {
    return fromHand.length > n ? fromHand.sublist(0, n) : fromHand;
  }

  final all = standardFiftyFourDeckInCanonicalOrder();
  final missing =
      all.where((c) => !used.contains(c.id)).toList(growable: false);
  if (missing.length >= need) {
    fromHand.addAll(missing.take(need));
    return fromHand;
  }
  return [...fromHand, ...missing];
}

/// Returns a 52-card deck (no Jokers) for Bust mode.
/// Same card IDs as standard deck; used by server and client for Bust.
List<CardModel> buildBustDeck({int? seed, math.Random? random}) {
  const ranks = [
    Rank.two, Rank.three, Rank.four, Rank.five, Rank.six, Rank.seven,
    Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen, Rank.king,
    Rank.ace,
  ];
  const suits = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

  final deck = <CardModel>[];
  for (final suit in suits) {
    for (final rank in ranks) {
      deck.add(CardModel(
        id: '${rank.name}_${suit.name}',
        rank: rank,
        suit: suit,
      ));
    }
  }
  fisherYatesShuffle(deck, seed: seed, random: random);
  return deck;
}

/// Bust mode hand size per player count (2–10).
int handSizeForBust(int playerCount) {
  assert(playerCount >= 2 && playerCount <= 10);
  return switch (playerCount) {
    6 => 8,
    7 => 7,
    8 => 6,
    9 => 5,
    10 => 5,
    _ => 10, // 2–5 players
  };
}

// ── Bust placement pile (shared client + server) ─────────────────────────────

/// Face-up discard count at which Bust's placement pile rule runs: all cards
/// under the top are shuffled into the draw pile, leaving a single visible card.
const bustPlacementPileThreshold = 5;

/// Whether the placement pile rule should run for a discard stored as a single
/// list (bottom → top), i.e. [totalDiscardCount] == `discardPile.length`.
bool needsBustPlacementPileReshuffle(int totalDiscardCount) =>
    totalDiscardCount >= bustPlacementPileThreshold;

/// Same as [needsBustPlacementPileReshuffle] when discard is split into
/// [underTopCardCount] (everything under the face-up card) and exactly one
/// face-up top. Caller must only use this when a top card exists.
bool needsBustPlacementPileReshuffleFromUnderTop(int underTopCardCount) =>
    needsBustPlacementPileReshuffle(underTopCardCount + 1);

// ── Last Cards — hand clearability (shared offline + server) ─────────────────

/// Normalizes [state] so [playerId]'s next legal plays are evaluated as at the
/// **start** of their turn (see [advanceTurn] field resets). Used when probing
/// clearability while another seat holds the turn (Last Cards declare timing).
GameState _normalizeStateForLastCardsClearabilityProbe(
  GameState state,
  String playerId,
) {
  if (state.currentPlayerId == playerId) return state;
  return state.copyWith(
    currentPlayerId: playerId,
    actionsThisTurn: 0,
    cardsPlayedThisTurn: 0,
    lastPlayedThisTurn: null,
    activeSkipCount: 0,
    preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
    queenSuitLock: null,
  );
}

/// Mirrors [GameSession._sameSeatFreshTurnAfterSkipOrKing] / offline same-seat
/// turn slices: after Skip or 2p King, the next card is validated like a new
/// lead against [discardTopCard] (not numerical flow off the prior card).
GameState _applySameSeatFreshTurnSlice(GameState state) {
  final lastCard = state.lastPlayedThisTurn;
  final lastWasPenalty = lastCard != null &&
      (lastCard.effectiveRank == Rank.two ||
          lastCard.effectiveRank == Rank.jack);
  return state.copyWith(
    actionsThisTurn: 0,
    cardsPlayedThisTurn: 0,
    lastPlayedThisTurn: null,
    activeSkipCount: 0,
    preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
    queenSuitLock: null,
    penaltyChainLive: lastWasPenalty ? state.penaltyChainLive : false,
  );
}

/// Max hand size for full subset enumeration of legal plays (2^n). Above this,
/// we enumerate singles plus same-rank Eight stacks only — enough for stacked
/// skip math (e.g. four Eights returning the turn in 5-player).
const int _clearabilityMaxSubsetBruteForce = 16;

bool _isWildNaturalAceSingles(
  GameState s,
  List<CardModel> play,
) {
  return play.length == 1 &&
      play.single.effectiveRank == Rank.ace &&
      !play.single.isJoker &&
      s.actionsThisTurn == 0;
}

/// Same-rank multi-card plays depend on order: [applyPlay] leaves [discardTopCard]
/// as the **last** card, which affects the next legal play (e.g. four Eights then
/// a heart on the final Eight).
void _forEachSameRankPlayOrdering(
  List<CardModel> play,
  void Function(List<CardModel> ordered) emit,
) {
  final ranks = play.map((c) => c.effectiveRank).toSet();
  if (play.length <= 1 || ranks.length != 1) {
    emit(play);
    return;
  }
  void permute(List<CardModel> prefix, List<CardModel> rem) {
    if (rem.isEmpty) {
      emit(prefix);
      return;
    }
    for (var i = 0; i < rem.length; i++) {
      final next = List<CardModel>.from(rem)..removeAt(i);
      permute([...prefix, rem[i]], next);
    }
  }

  permute([], play);
}

/// Legal multi-card and non–wild-Ace single plays for clearability DFS.
/// Wild natural Aces are excluded — callers must branch [declaredSuit] per suit.
List<List<CardModel>> _legalPlaysForClearabilityProbe(
  GameState s,
  String playerId,
  CardModel discardTop,
) {
  final hand = s.playerById(playerId)?.hand;
  if (hand == null || hand.isEmpty) return [];

  final n = hand.length;
  final seen = <String>{};
  final out = <List<CardModel>>[];

  void tryAdd(List<CardModel> play) {
    if (_isWildNaturalAceSingles(s, play)) return;

    void pushIfValid(List<CardModel> ordered) {
      if (validatePlay(cards: ordered, discardTop: discardTop, state: s) !=
          null) {
        return;
      }
      final ranks = ordered.map((c) => c.effectiveRank).toSet();
      final key = ranks.length == 1 && ordered.length > 1
          ? ordered.map((c) => c.id).join('>')
          : (ordered.map((c) => c.id).toList()..sort()).join(',');
      if (!seen.add(key)) return;
      out.add(ordered);
    }

    _forEachSameRankPlayOrdering(play, pushIfValid);
  }

  if (n <= _clearabilityMaxSubsetBruteForce) {
    for (var mask = 1; mask < (1 << n); mask++) {
      final play = <CardModel>[];
      for (var i = 0; i < n; i++) {
        if ((mask >> i) & 1 == 1) play.add(hand[i]);
      }
      tryAdd(play);
    }
  } else {
    for (final card in hand) {
      if (_isWildNaturalAceSingles(s, [card])) continue;
      tryAdd([card]);
    }
    final eights = hand.where((c) => c.effectiveRank == Rank.eight).toList();
    final m = eights.length;
    for (var mask = 1; mask < (1 << m); mask++) {
      final play = <CardModel>[];
      for (var i = 0; i < m; i++) {
        if ((mask >> i) & 1 == 1) play.add(eights[i]);
      }
      tryAdd(play);
    }
  }

  return out;
}

bool _canClearHandRespectingDiscard(GameState state, String playerId) {
  final normalized = _normalizeStateForLastCardsClearabilityProbe(
    state,
    playerId,
  );
  if (normalized.discardTopCard == null) return false;

  bool dfs(GameState s) {
    final hand = s.playerById(playerId)?.hand;
    if (hand == null) return false;
    if (hand.isEmpty) return true;

    final top = s.discardTopCard;
    if (top == null) return false;

    /// After a committed play: win, recurse for more plays **this turn**, or
    /// apply a same-seat fresh slice when [nextPlayerId] already wraps to this
    /// seat (2p King/Eight, multi-player skip). [nextPlayerId] ≠ [playerId]
    /// does **not** end the turn — the current player may still play again
    /// until they end the turn; [applyPlay] + [validatePlay] model that.
    bool continueAfterPlay(GameState played) {
      final after = played.playerById(playerId)?.hand;
      if (after == null) return false;
      if (after.isEmpty) return true;
      final nextState = nextPlayerId(state: played) == playerId
          ? _applySameSeatFreshTurnSlice(played)
          : played;
      return dfs(nextState);
    }

    for (final play in _legalPlaysForClearabilityProbe(s, playerId, top)) {
      final played = applyPlay(state: s, playerId: playerId, cards: play);
      if (continueAfterPlay(played)) return true;
    }

    for (final card in List<CardModel>.from(hand)) {
      if (card.effectiveRank != Rank.ace ||
          s.actionsThisTurn != 0 ||
          card.isJoker) {
        continue;
      }
      final aceErr = validatePlay(
        cards: [card],
        discardTop: top,
        state: s,
      );
      if (aceErr != null) continue;
      for (final suit in Suit.values) {
        final played = applyPlay(
          state: s,
          playerId: playerId,
          cards: [card],
          declaredSuit: suit,
        );
        if (continueAfterPlay(played)) return true;
      }
    }
    return false;
  }

  return dfs(normalized);
}

/// Whether [playerId]'s hand can be emptied in one **visit** (single seat
/// continuity), including same-seat continuance when [nextPlayerId] stays on
/// this seat: **2-player King**; **stacked Eights** (skip math can wrap the
/// table so the turn returns immediately, e.g. four Eights in 5-player); and
/// **1v1 Eight skip** (same as King).
///
/// First tries [canHandClearInOneTurnHandOnly] (ordering without facing the
/// pile). If that fails, runs a bounded simulation with [validatePlay] /
/// [applyPlay], including **multiple sequential plays per turn** (numerical
/// flow, value chains, same-rank pairs, etc.) and **multi-card same-rank plays**
/// (stacked Eights accumulate [activeSkipCount] like real play).
///
/// Jokers use the hand-only analyzer only (declaration sites exempt bluff via
/// [PlayerModel.hand] Joker check). [isBustMode] forces `false`. When the
/// opponent's hand is hidden (`cardCount` ≠ `hand.length`), returns `false`.
bool canClearHandInOneTurn({
  required GameState state,
  required String playerId,
  bool isBustMode = false,
}) {
  if (isBustMode) return false;
  final p = state.playerById(playerId);
  if (p == null) return false;
  if (p.hand.isEmpty) return true;
  if (p.hand.length != p.cardCount) return false;
  if (p.hand.any((c) => c.isJoker)) {
    return canHandClearInOneTurnHandOnly(p.hand);
  }
  if (canHandClearInOneTurnHandOnly(p.hand)) return true;
  return _canClearHandRespectingDiscard(state, playerId);
}

/// Sets [PlayerModel.lastCardsHandWasClearableAtTurnStart] for
/// [GameState.currentPlayerId] via [canClearHandInOneTurn], and clears the flag
/// for everyone else.
///
/// Call once after game start when [currentPlayerId] and the discard pile are
/// finalized (including [applyInitialFaceUpEffect] and opening Eight skip).
/// [advanceTurn] sets this flag for subsequent turns; do not replace that path.
GameState initializeFirstTurnClearability(
  GameState state, {
  bool isBustMode = false,
}) {
  final id = state.currentPlayerId;
  final clearable = canClearHandInOneTurn(
    state: state,
    playerId: id,
    isBustMode: isBustMode,
  );
  final players = state.players.map((p) {
    if (p.id != id) {
      return p.copyWith(lastCardsHandWasClearableAtTurnStart: false);
    }
    return p.copyWith(lastCardsHandWasClearableAtTurnStart: clearable);
  }).toList();
  return state.copyWith(players: players);
}

/// Opening [GameState.currentPlayerId] has not yet had a moment when
/// [mayDeclareLastCards] could apply (see `last_cards_rules.dart`). If the deal
/// was already clearable ([PlayerModel.lastCardsHandWasClearableAtTurnStart]),
/// adds that player to [lastCardsDeclaredBy] so a first-turn win is not treated
/// as undeclared Last Cards ([needsUndeclaredLastCardsDraw]).
///
/// Call after [initializeFirstTurnClearability] when the discard pile and
/// opening skip (e.g. Eight) are final — same moment as server `_startGame`.
/// Offline [TableScreen] and [GameSession] must both invoke this for parity.
({GameState state, bool applied, bool isBluff}) applyOpeningSeatLastCardsSeedIfNeeded({
  required GameState state,
  bool isBustMode = false,
}) {
  if (isBustMode) {
    return (state: state, applied: false, isBluff: false);
  }
  final id = state.currentPlayerId;
  if (state.lastCardsDeclaredBy.contains(id)) {
    return (state: state, applied: false, isBluff: false);
  }
  final player = state.playerById(id);
  if (player == null) return (state: state, applied: false, isBluff: false);
  if (!player.lastCardsHandWasClearableAtTurnStart) {
    return (state: state, applied: false, isBluff: false);
  }
  final nextState = state.copyWith(
    lastCardsDeclaredBy: {...state.lastCardsDeclaredBy, id},
  );
  final hasJoker = player.hand.any((c) => c.isJoker);
  final bluff = !hasJoker &&
      !canClearHandInOneTurn(
        state: nextState,
        playerId: id,
        isBustMode: isBustMode,
      );
  return (state: nextState, applied: true, isBluff: bluff);
}

// ── Shared turn advancement ───────────────────────────────────────────────────

/// Advances to the next player and resets all per-turn state fields.
///
/// Supply [nextId] to override the auto-computed next player — useful when
/// callers need to apply tournament or session-specific override logic
/// (e.g. `_resolveTournamentNextPlayerId`) before invoking this function.
///
/// Resets: [currentPlayerId], [actionsThisTurn], [cardsPlayedThisTurn],
/// [lastPlayedThisTurn], [activeSkipCount], [preTurnCentreSuit],
/// [queenSuitLock], and may clear [penaltyChainLive] when the outgoing player
/// did not end on a penalty card.
///
/// Sets [PlayerModel.lastCardsHandWasClearableAtTurnStart] for the incoming
/// player only.
GameState advanceTurn(GameState state, {String? nextId}) {
  final id = nextId ?? nextPlayerId(state: state);
  final outgoing = state.currentPlayerId;
  final nextDeclared = {...state.lastCardsDeclaredBy}..remove(outgoing);
  final lastCard = state.lastPlayedThisTurn;
  final lastWasPenalty = lastCard != null &&
      (lastCard.effectiveRank == Rank.two ||
          lastCard.effectiveRank == Rank.jack);
  final base = state.copyWith(
    currentPlayerId: id,
    actionsThisTurn: 0,
    cardsPlayedThisTurn: 0,
    lastPlayedThisTurn: null,
    activeSkipCount: 0,
    preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
    queenSuitLock: null,
    lastCardsDeclaredBy: nextDeclared,
    penaltyChainLive: lastWasPenalty ? state.penaltyChainLive : false,
  );
  final players = base.players.map((p) {
    if (p.id != id) {
      return p.copyWith(lastCardsHandWasClearableAtTurnStart: false);
    }
    final clearable = canClearHandInOneTurn(
      state: base,
      playerId: id,
    );
    return p.copyWith(lastCardsHandWasClearableAtTurnStart: clearable);
  }).toList();
  return base.copyWith(players: players);
}

/// Standard online: removes [removedPlayerId] after a confirmed leave (socket
/// closed or lobby kick). Returns `null` if that player is absent or fewer than **two**
/// players would remain — callers should end the session instead.
///
/// [handForDrawPile]: copies [PlayerModel.hand] when it matches
/// [PlayerModel.cardCount]. Otherwise, if the server passes
/// [authoritativeDrawPile] (and optional discard args), missing cards are
/// inferred as IDs from the 54-card manifest not currently in play (fixes
/// empty-hand / count desync on the draw pile).
///
/// If the leaver had the turn, play advances via [nextPlayerIdExcluding] so
/// skip math cannot name the removed seat. An unfinished wild Ace (face-up Ace, no [suitLock],
/// exactly one card played this turn) defaults to the Ace's natural suit so the
/// pile stays valid for the next player.
({GameState state, List<CardModel> handForDrawPile})?
removeDisconnectedStandardPlayer({
  required GameState state,
  required String removedPlayerId,
  List<CardModel>? authoritativeDrawPile,
  List<CardModel>? authoritativeDiscardUnderTop,
  CardModel? authoritativeDiscardTop,
}) {
  final removed = state.playerById(removedPlayerId);
  if (removed == null) return null;
  if (state.players.length <= 2) return null;

  final newPlayers =
      state.players.where((p) => p.id != removedPlayerId).toList();
  final lastCards = {...state.lastCardsDeclaredBy}..remove(removedPlayerId);

  var stripped = state.copyWith(
    players: newPlayers,
    lastCardsDeclaredBy: lastCards,
    pendingJokerResolution: state.currentPlayerId == removedPlayerId
        ? false
        : state.pendingJokerResolution,
    activePenaltyCount: state.currentPlayerId == removedPlayerId
        ? 0
        : state.activePenaltyCount,
    penaltyChainLive: state.currentPlayerId == removedPlayerId
        ? false
        : state.penaltyChainLive,
  );

  final handForDrawPile = leaverCardsToReturnToDrawPile(
    removed: removed,
    stateWithoutLeaver: stripped,
    authoritativeDrawPile: authoritativeDrawPile,
    authoritativeDiscardUnderTop: authoritativeDiscardUnderTop,
    authoritativeDiscardTop:
        authoritativeDiscardTop ?? state.discardTopCard,
  );

  final wasCurrent = state.currentPlayerId == removedPlayerId;
  if (!wasCurrent) {
    return (state: stripped, handForDrawPile: handForDrawPile);
  }

  if (stripped.discardTopCard?.effectiveRank == Rank.ace &&
      stripped.suitLock == null &&
      stripped.cardsPlayedThisTurn == 1) {
    stripped =
        stripped.copyWith(suitLock: stripped.discardTopCard!.suit);
  }

  final nextId = nextPlayerIdExcluding(
    state: state,
    excludePlayerId: removedPlayerId,
  );
  final advanced = advanceTurn(stripped, nextId: nextId);
  return (state: advanced, handForDrawPile: handForDrawPile);
}

// ── Shared invalid-play penalty ───────────────────────────────────────────────

/// Resolves a failed play attempt by drawing penalty cards for [playerId].
///
/// When no pick-up stack is pending ([activePenaltyCount] == 0), draws **2**
/// cards (standard bad-play rule). When a stacked 2/Black Jack penalty **is**
/// active, draws that **full** count instead — same cost as voluntarily drawing
/// to pay the stack — so invalid plays cannot replace a large pick-up with a
/// 2-card slap on the wrist.
///
/// If only a Red-Jack-style chain is live (draw count 0, [penaltyChainLive]
/// true), the 2-card draw still applies and [penaltyChainLive] is restored so
/// matching rules stay consistent.
///
/// Does NOT advance the turn — callers should call [advanceTurn] afterwards.
GameState applyInvalidPlayPenalty({
  required GameState state,
  required String playerId,
  required List<CardModel> Function(int n) cardFactory,
}) {
  final stackedPenalty = state.activePenaltyCount;
  final savedChainLive = state.penaltyChainLive;
  final drawCount = stackedPenalty > 0 ? stackedPenalty : 2;
  final after = applyDraw(
    state: state,
    playerId: playerId,
    count: drawCount,
    cardFactory: cardFactory,
  );
  if (stackedPenalty > 0) {
    return after;
  }
  return after.copyWith(penaltyChainLive: savedChainLive);
}
