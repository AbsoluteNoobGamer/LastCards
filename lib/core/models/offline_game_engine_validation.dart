part of 'offline_game_engine.dart';

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
      final firstCard = cards.first;
      final isTwo = firstCard.effectiveRank == Rank.two;
      final isBlackJack = firstCard.isBlackJack;
      final isRedJack =
          firstCard.effectiveRank == Rank.jack && !firstCard.isBlackJack;

      if (!isTwo && !isBlackJack && !isRedJack) {
        return 'Active penalty! Your first card must be a 2 or Black Jack to stack, or a Red Jack to cancel.';
      }
    }

    // Whether it's the first play or mid-turn, if the play consists ONLY of valid
    // penalty-addressing cards, it bypasses standard normal suit/rank matching
    // against the discard pile and numerical flow rules entirely.
    final allTwos = cards.every((c) => c.effectiveRank == Rank.two);
    final allBlackJacks = cards.every((c) => c.isBlackJack);
    final allRedJacks =
        cards.every((c) => c.effectiveRank == Rank.jack && !c.isBlackJack);

    if (allTwos || allBlackJacks || allRedJacks) {
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
    final prevIsPenaltyNode =
        prev.effectiveRank == Rank.two || prev.effectiveRank == Rank.jack;
    final nextIsPenaltyNode =
        next.effectiveRank == Rank.two || next.effectiveRank == Rank.jack;
    final isPenaltyChain = prevIsPenaltyNode && nextIsPenaltyNode;

    if (!isSpecialOverride && !isPenaltyChain) {
      final sameSuit = next.effectiveSuit == prev.effectiveSuit;
      final rankDiff =
          (next.effectiveRank.numericValue - prev.effectiveRank.numericValue)
              .abs();

      final isTwoAndAce = (prev.effectiveRank == Rank.two &&
              next.effectiveRank == Rank.ace) ||
          (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);

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
enum JokerPlayContext {
  turnStarter,
  midTurnContinuance,
}

JokerPlayContext jokerPlayContextFromCardsPlayed(int cardsPlayedThisTurn) {
  return cardsPlayedThisTurn == 0
      ? JokerPlayContext.turnStarter
      : JokerPlayContext.midTurnContinuance;
}

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

  for (final suit in Suit.values) {
    for (final rank in Rank.values) {
      if (rank == Rank.joker) continue; // Joker can't mimic a Joker
      if (rank == targetRank && suit == targetSuit)
        continue; // Cannot be exact dupe

      bool isValidMatch = false;

      // 3. Penalty Rules
      if (state.activePenaltyCount > 0) {
        // During an active penalty, standard adjacent/rank matching doesn't apply.
        // A player MUST address the penalty. Valid cards are 2s, Black Jacks, and Red Jacks.
        // So a Joker can mimic ANY 2, ANY Black Jack, or ANY Red Jack (except the exact dupe).
        final isTwo = rank == Rank.two;
        final isBlackJack =
            rank == Rank.jack && (suit == Suit.clubs || suit == Suit.spades);
        final isRedJack =
            rank == Rank.jack && (suit == Suit.hearts || suit == Suit.diamonds);

        isValidMatch = isTwo || isBlackJack || isRedJack;
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
          if (isSameValueOtherSuit) {
            isValidMatch = true;
          } else if (suit == targetSuit) {
            final bool isAdjacentSameSuit;
            if (targetRank == Rank.ace) {
              // No wrap-around below Ace (so K is not valid when anchoring on Ace).
              isAdjacentSameSuit = rank == Rank.two;
            } else {
              final diff = (rank.numericValue - targetRank.numericValue).abs();
              isAdjacentSameSuit = diff == 1;
            }
            if (isAdjacentSameSuit) {
              isValidMatch = true;
            }
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
    if (card.effectiveRank == Rank.queen)
      return null; // Q->Q chaining is explicitly allowed
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
