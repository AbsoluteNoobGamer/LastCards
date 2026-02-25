part of 'offline_game_engine.dart';

// ── AI opponent (Player 2) ────────────────────────────────────────────────────

/// Greedy AI: plays the best legal card it has, or draws if none are legal.
///
/// The AI also ends its turn automatically after one play/draw (no "End Turn"
/// concept — only the human player has that control).
({GameState state, List<CardModel> playedCards}) aiTakeTurn({
  required GameState state,
  required String aiPlayerId,
  required List<CardModel> Function(int n) cardFactory,
}) {
  final ai = state.players.firstWhere((p) => p.id == aiPlayerId);
  final List<CardModel> playedCards = [];

  // ── Pending penalty: try to counter first ─────────────────────────
  if (state.activePenaltyCount > 0) {
    // Find a 2 or a Red Jack to counter the penalty
    CardModel? counterCard;
    for (final card in ai.hand) {
      final isCounter = (card.effectiveRank == Rank.two) ||
          (card.effectiveRank == Rank.jack && !card.isBlackJack);
      if (isCounter &&
          validatePlay(
                  cards: [card],
                  discardTop: state.discardTopCard!,
                  state: state) ==
              null) {
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
        state: newState.copyWith(
            currentPlayerId: next,
            actionsThisTurn: 0,
            lastPlayedThisTurn: null,
            activeSkipCount: 0),
        playedCards: [],
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
    if (bestCard!.effectiveRank == Rank.ace) {
      declaredSuit = Suit.spades; // AI always declares spades
    } else if (bestCard!.isJoker) {
      final options =
          getValidJokerOptions(state: state, discardTop: state.discardTopCard!);
      if (options.isNotEmpty) {
        bestCard = bestCard!.copyWith(
          jokerDeclaredRank: options.first.rank,
          jokerDeclaredSuit: options.first.suit,
        );
      }
    }

    var afterPlay = applyPlay(
      state: state,
      playerId: aiPlayerId,
      cards: [bestCard],
      declaredSuit: declaredSuit,
    );



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
            ) ==
            null) {
          coverCard = card;
          break;
        }
      }

      if (coverCard != null) {
        if (coverCard.isJoker) {
          final options = getValidJokerOptions(
              state: afterPlay, discardTop: afterPlay.discardTopCard!);
          if (options.isNotEmpty) {
            coverCard = coverCard.copyWith(
              jokerDeclaredRank: options.first.rank,
              jokerDeclaredSuit: options.first.suit,
            );
          }
        }

        afterPlay = applyPlay(
          state: afterPlay,
          playerId: aiPlayerId,
          cards: [coverCard],
        );
        playedCards.add(coverCard);
      } else {
        // Cannot cover — draw 1 card penalty and abort.
        afterPlay = applyDraw(
          state: afterPlay,
          playerId: aiPlayerId,
          count: 1,
          cardFactory: cardFactory,
        );
        // Clear queenSuitLock since the draw resolves the obligation.
        afterPlay = afterPlay.copyWith(queenSuitLock: null);
        break;
      }
    }

    final next = nextPlayerId(state: afterPlay);
    return (
      state: afterPlay.copyWith(
          currentPlayerId: next,
          actionsThisTurn: 0,
          lastPlayedThisTurn: null,
          activeSkipCount: 0),
      playedCards: playedCards,
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
    state: afterDraw.copyWith(
        currentPlayerId: next,
        actionsThisTurn: 0,
        lastPlayedThisTurn: null,
        activeSkipCount: 0),
    playedCards: [],
  );
}

bool _isSpecial(CardModel c) {
  const specials = {
    Rank.two,
    Rank.jack,
    Rank.queen,
    Rank.king,
    Rank.ace,
    Rank.eight,
  };
  return specials.contains(c.effectiveRank) || c.isJoker;
}
