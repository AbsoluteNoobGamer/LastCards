part of 'offline_game_engine.dart';

// Opponent suit inference (offline AI): drawing while a suit is required implies
// the player likely lacked that suit when they drew.
final Map<String, Map<String, Set<Suit>>> _suitInferenceBySession = {};

/// Records that [drawingPlayerId] drew from the pile while the active suit
/// was required — used by [aiTakeTurn] and offline UI draws.
void recordDrawSuitInference({
  required GameState state,
  required String drawingPlayerId,
}) {
  final top = state.discardTopCard;
  if (top == null) return;
  final activeSuit = state.suitLock ?? top.effectiveSuit;
  final sessionMap =
      _suitInferenceBySession.putIfAbsent(state.sessionId, () => {});
  sessionMap.putIfAbsent(drawingPlayerId, () => <Suit>{}).add(activeSuit);
}

/// Clears inference entries when [playerId] proves they hold a suit by playing it.
void clearSuitInferenceOnPlay({
  required String sessionId,
  required String playerId,
  required List<CardModel> cards,
}) {
  final sessionMap = _suitInferenceBySession[sessionId];
  if (sessionMap == null) return;
  final set = sessionMap[playerId];
  if (set == null) return;
  for (final c in cards) {
    if (c.isJoker) continue;
    set.remove(c.effectiveSuit);
  }
}

/// Clears draw-based suit inference (for tests; avoids cross-test session bleed).
void resetSuitInferenceForTests() {
  _suitInferenceBySession.clear();
}

/// Removes inference data for [sessionId] when an offline session ends.
void clearSuitInference(String sessionId) {
  _suitInferenceBySession.remove(sessionId);
}

// ── AI opponent (Player 2) ────────────────────────────────────────────────────

class _AiPlayChoice {
  final List<CardModel> cards;
  final Suit? declaredSuit;
  final int score;

  const _AiPlayChoice({
    required this.cards,
    required this.declaredSuit,
    required this.score,
  });
}

GameState _maybeAiDeclareLastCards({
  required GameState state,
  required String aiPlayerId,
}) {
  if (state.lastCardsDeclaredBy.contains(aiPlayerId)) return state;
  if (!shouldShowLastCardsButton(
    isBustMode: false,
    alreadyDeclared: false,
  )) {
    return state;
  }
  if (!canClearHandInOneTurn(state: state, playerId: aiPlayerId)) {
    return state;
  }
  return state.copyWith(
    lastCardsDeclaredBy: {...state.lastCardsDeclaredBy, aiPlayerId},
  );
}

bool aiHasPlayableTurn({
  required GameState state,
  required String aiPlayerId,
}) {
  final ai = state.players.firstWhere((p) => p.id == aiPlayerId);
  final choices =
      _generateAiChoices(state: state, ai: ai, aiPlayerId: aiPlayerId);
  return choices.isNotEmpty;
}

({
  GameState state,
  List<CardModel> playedCards,
  GameState preTurnAdvanceState,
  int queenCoverDrawCount,
  Suit? aceDeclaredSuit,
}) aiTakeTurn({
  required GameState state,
  required String aiPlayerId,
  required List<CardModel> Function(int n) cardFactory,
  AiPersonality? personality,
  AiDifficulty? difficulty,
}) {
  var s = _maybeAiDeclareLastCards(state: state, aiPlayerId: aiPlayerId);
  final ai = s.players.firstWhere((p) => p.id == aiPlayerId);
  final List<CardModel> playedCards = [];
  final discardTop = s.discardTopCard!;

  // Win awareness: if only one card remains and it's playable, take the win now.
  if (ai.hand.length == 1 &&
      validatePlay(
              cards: [ai.hand.first], discardTop: discardTop, state: s) ==
          null) {
    final oneCardChoice = _buildSingleCardChoice(
      state: s,
      ai: ai,
      aiPlayerId: aiPlayerId,
      card: ai.hand.first,
    );
    final result = _executeChoice(
      state: s,
      aiPlayerId: aiPlayerId,
      choice: oneCardChoice,
      playedCards: playedCards,
    );
    final aceDecl = oneCardChoice.cards.first.effectiveRank == Rank.ace
        ? oneCardChoice.declaredSuit
        : null;
    return _finalizeAiTurn(
        state: result, playedCards: playedCards, aceDeclaredSuit: aceDecl);
  }

  final choices = _generateAiChoices(
    state: s,
    ai: ai,
    aiPlayerId: aiPlayerId,
    personality: personality,
    difficulty: difficulty,
  );

  if (choices.isEmpty) {
    final drawCount =
        s.activePenaltyCount > 0 ? s.activePenaltyCount : 1;
    // Easy AI doesn't build suit inference from draws (less strategic awareness).
    if (difficulty != AiDifficulty.easy) {
      recordDrawSuitInference(state: s, drawingPlayerId: aiPlayerId);
    }
    final afterDraw = applyDraw(
      state: s,
      playerId: aiPlayerId,
      count: drawCount,
      cardFactory: cardFactory,
    );
    return _finalizeAiTurn(state: afterDraw, playedCards: const []);
  }

  choices.sort((a, b) => b.score.compareTo(a.score));
  final best = choices.first;
  final aceDecl = best.cards.isNotEmpty &&
          best.cards.first.effectiveRank == Rank.ace
      ? best.declaredSuit
      : null;
  var afterPlay = _executeChoice(
    state: s,
    aiPlayerId: aiPlayerId,
    choice: best,
    playedCards: playedCards,
  );

  // Ace follow-up: keep momentum by immediately continuing with declared suit.
  if (best.cards.length == 1 &&
      best.cards.first.effectiveRank == Rank.ace &&
      best.declaredSuit != null) {
    final followUp = _findImmediateSuitFollowUp(
      state: afterPlay,
      aiPlayerId: aiPlayerId,
      suit: best.declaredSuit!,
    );
    if (followUp != null) {
      afterPlay = applyPlay(
        state: afterPlay,
        playerId: aiPlayerId,
        cards: [followUp],
      );
      playedCards.add(followUp);
    }
  }

  // Joker follow-up: if the AI declared a card it can continue from, do it now.
  if (best.cards.length == 1 && best.cards.first.isJoker) {
    final followUp = _findAnyImmediateFollowUp(
      state: afterPlay,
      aiPlayerId: aiPlayerId,
    );
    if (followUp != null) {
      afterPlay = applyPlay(
        state: afterPlay,
        playerId: aiPlayerId,
        cards: [followUp],
      );
      playedCards.add(followUp);
    }
  }

  // Queen cover: AI must immediately cover before ending turn.
  int queenCoverDrawCount = 0;
  int coverAttempts = 0;
  while (afterPlay.queenSuitLock != null && coverAttempts < 5) {
    coverAttempts++;
    final cover =
        _findAnyImmediateFollowUp(state: afterPlay, aiPlayerId: aiPlayerId);
    if (cover != null) {
      afterPlay = applyPlay(
        state: afterPlay,
        playerId: aiPlayerId,
        cards: [cover],
      );
      playedCards.add(cover);
      continue;
    }
    queenCoverDrawCount = 1;
    if (difficulty != AiDifficulty.easy) {
      recordDrawSuitInference(state: afterPlay, drawingPlayerId: aiPlayerId);
    }
    afterPlay = applyDraw(
      state: afterPlay,
      playerId: aiPlayerId,
      count: 1,
      cardFactory: cardFactory,
    ).copyWith(queenSuitLock: null);
    break;
  }

  return _finalizeAiTurn(
    state: afterPlay,
    playedCards: playedCards,
    queenCoverDrawCount: queenCoverDrawCount,
    aceDeclaredSuit: aceDecl,
  );
}

({
  GameState state,
  List<CardModel> playedCards,
  GameState preTurnAdvanceState,
  int queenCoverDrawCount,
  Suit? aceDeclaredSuit,
}) _finalizeAiTurn({
  required GameState state,
  required List<CardModel> playedCards,
  int queenCoverDrawCount = 0,
  Suit? aceDeclaredSuit,
}) {
  return (
    state: advanceTurn(state),
    playedCards: playedCards,
    preTurnAdvanceState: state,
    queenCoverDrawCount: queenCoverDrawCount,
    aceDeclaredSuit: aceDeclaredSuit,
  );
}

GameState _executeChoice({
  required GameState state,
  required String aiPlayerId,
  required _AiPlayChoice choice,
  required List<CardModel> playedCards,
}) {
  clearSuitInferenceOnPlay(
    sessionId: state.sessionId,
    playerId: aiPlayerId,
    cards: choice.cards,
  );
  final after = applyPlay(
    state: state,
    playerId: aiPlayerId,
    cards: choice.cards,
    declaredSuit: choice.declaredSuit,
  );
  playedCards.addAll(choice.cards);
  return after;
}

List<_AiPlayChoice> _generateAiChoices({
  required GameState state,
  required PlayerModel ai,
  required String aiPlayerId,
  AiPersonality? personality,
  AiDifficulty? difficulty,
}) {
  final discardTop = state.discardTopCard!;
  final choices = <_AiPlayChoice>[];

  // Single-card candidates (including Ace/Joker declarations).
  for (final card in ai.hand) {
    final err =
        validatePlay(cards: [card], discardTop: discardTop, state: state);
    if (err != null) continue;
    final choice = _buildSingleCardChoice(
      state: state,
      ai: ai,
      aiPlayerId: aiPlayerId,
      card: card,
    );
    choices.add(_scoreChoice(
      state: state,
      aiPlayerId: aiPlayerId,
      ai: ai,
      choice: choice,
      personality: personality,
      difficulty: difficulty,
    ));
  }

  // Multi-card same-rank stacks (no jokers).
  final byRank = <Rank, List<CardModel>>{};
  for (final card in ai.hand.where((c) => !c.isJoker)) {
    byRank.putIfAbsent(card.effectiveRank, () => []).add(card);
  }
  byRank.forEach((_, cards) {
    if (cards.length < 2) return;
    if (validatePlay(cards: cards, discardTop: discardTop, state: state) ==
        null) {
      choices.add(
        _scoreChoice(
          state: state,
          aiPlayerId: aiPlayerId,
          ai: ai,
          choice: _AiPlayChoice(cards: cards, declaredSuit: null, score: 0),
          personality: personality,
          difficulty: difficulty,
        ),
      );
    }
  });

  // Multi-card same-suit sequences (no jokers).
  for (final suit in Suit.values) {
    final suitCards = ai.hand
        .where((c) => !c.isJoker && c.effectiveSuit == suit)
        .toList()
      ..sort((a, b) =>
          a.effectiveRank.numericValue.compareTo(b.effectiveRank.numericValue));
    if (suitCards.length < 2) continue;

    for (int i = 0; i < suitCards.length - 1; i++) {
      final run = <CardModel>[suitCards[i]];
      for (int j = i + 1; j < suitCards.length; j++) {
        final prev = run.last.effectiveRank.numericValue;
        final next = suitCards[j].effectiveRank.numericValue;
        if (next == prev + 1) {
          run.add(suitCards[j]);
          if (run.length >= 2 &&
              validatePlay(cards: run, discardTop: discardTop, state: state) ==
                  null) {
            choices.add(
              _scoreChoice(
                state: state,
                aiPlayerId: aiPlayerId,
                ai: ai,
                choice: _AiPlayChoice(
                  cards: List<CardModel>.from(run),
                  declaredSuit: null,
                  score: 0,
                ),
                personality: personality,
                difficulty: difficulty,
              ),
            );
          }
        } else if (next != prev) {
          break;
        }
      }
    }
  }

  return choices;
}

_AiPlayChoice _buildSingleCardChoice({
  required GameState state,
  required PlayerModel ai,
  required String aiPlayerId,
  required CardModel card,
}) {
  if (card.effectiveRank == Rank.ace) {
    final declaredSuit = _chooseBestAceSuit(
      state: state,
      aiPlayerId: aiPlayerId,
      hand: ai.hand,
      excludingCardId: card.id,
    );
    return _AiPlayChoice(
      cards: [card],
      declaredSuit: declaredSuit,
      score: 0,
    );
  }

  if (card.isJoker) {
    final resolved = _resolveJokerStrategically(
      state: state,
      aiHand: ai.hand,
      joker: card,
    );
    return _AiPlayChoice(
      cards: [resolved],
      declaredSuit: resolved.effectiveRank == Rank.ace
          ? resolved.effectiveSuit
          : null,
      score: 0,
    );
  }

  return _AiPlayChoice(cards: [card], declaredSuit: null, score: 0);
}

_AiPlayChoice _scoreChoice({
  required GameState state,
  required String aiPlayerId,
  required PlayerModel ai,
  required _AiPlayChoice choice,
  AiPersonality? personality,
  AiDifficulty? difficulty,
}) {
  int score = 0;
  final handSize = ai.hand.length;
  final remainingCount = handSize - choice.cards.length;
  final lead = choice.cards.first;
  final containsBlackJack = choice.cards.any((c) => c.isBlackJack);
  final containsTwo = choice.cards.any((c) => c.effectiveRank == Rank.two);

  // Difficulty-gated helpers: easy AI ignores opponent state entirely.
  final bool ignoreOpponents = difficulty == AiDifficulty.easy;
  final int nextOppCards = ignoreOpponents
      ? 99
      : _nextOpponentCardCount(state: state, aiPlayerId: aiPlayerId);

  // Priority 1: winning now.
  if (remainingCount == 0) {
    score += 1000000 + (choice.cards.length * 1000);
  }

  // Priority 2: if hand has 2 cards, prefer leaving one playable.
  if (handSize == 2 &&
      _leavesOnePlayable(
          state: state, aiPlayerId: aiPlayerId, choice: choice)) {
    score += 700000;
  }

  // Priority 3: play bigger legal groups when safe.
  if (choice.cards.length > 1) {
    score += 200000 + (choice.cards.length * 500);
  }

  // Avoid aggressive penalty pressure when AI is close to winning.
  if (state.activePenaltyCount == 0 && handSize <= 3) {
    if (containsBlackJack) score -= 500000;
    if (containsTwo) score -= 180000;
  }

  // Priority 4: strategic specials.
  switch (lead.effectiveRank) {
    case Rank.jack:
      if (lead.isBlackJack) {
        if (state.activePenaltyCount > 0) score += 120000;
        if (handSize >= 6) score += 110000;
        if (handSize <= 3) score -= 160000;
      } else {
        // Red Jack should mainly be used to cancel active penalty chains.
        score += state.activePenaltyCount > 0 ? 150000 : -160000;
      }
      break;
    case Rank.two:
      if (state.activePenaltyCount > 0) score += 120000;
      if (handSize <= 3) score -= 90000;
      break;
    case Rank.queen:
      final suit = lead.effectiveSuit;
      final int inSuit = ai.hand
          .where((c) => c.id != lead.id && c.effectiveSuit == suit)
          .length;
      score += 60000 + (inSuit * 4000);
      break;
    case Rank.eight:
      // Easy AI never targets opponents; hard AI gets a bigger targeting window.
      score += nextOppCards <= 2
          ? 90000
          : (nextOppCards <= 4 && difficulty == AiDifficulty.hard ? 40000 : -20000);
      break;
    case Rank.king:
      score += nextOppCards <= 2
          ? 90000
          : (nextOppCards <= 4 && difficulty == AiDifficulty.hard ? 35000 : 10000);
      break;
    case Rank.ace:
      final suit = choice.declaredSuit;
      final int continuation = suit == null
          ? 0
          : ai.hand
              .where((c) =>
                  c.id != lead.id && !c.isJoker && c.effectiveSuit == suit)
              .length;
      // Easy AI doesn't use inference pressure; medium/hard do.
      final oppPressure = (suit == null || ignoreOpponents)
          ? 0
          : _opponentAceSuitPressure(
              state: state, aiPlayerId: aiPlayerId, suit: suit);
      score += 75000 + (continuation * 6000) + oppPressure;
      break;
    case Rank.joker:
      score += 65000;
      break;
    default:
      break;
  }

  // Priority 5: regular cards reduce hand weight by shedding higher ranks.
  score += lead.effectiveRank.numericValue * 100;

  // Hard AI: bonus for hunting the leader (lowest-card opponent overall).
  if (difficulty == AiDifficulty.hard) {
    final minOppCards = state.players
        .where((p) => p.id != aiPlayerId)
        .map((p) => p.cardCount)
        .fold(99, (a, b) => a < b ? a : b);
    if (minOppCards <= 2) {
      // Apply extra pressure when an opponent is about to win.
      if (containsBlackJack) score += 40000;
      if (containsTwo) score += 35000;
      if (lead.effectiveRank == Rank.eight) score += 30000;
      if (lead.effectiveRank == Rank.king) score += 25000;
    }
  }

  // Personality modifier — subtle nudge, never overrides critical plays.
  if (personality != null) {
    switch (personality) {
      case AiPersonality.aggressive:
        // Prefers Black Jack and 2 when penalties are active; likes kings.
        if (containsBlackJack && state.activePenaltyCount > 0) score += 35000;
        if (containsTwo && state.activePenaltyCount > 0) score += 30000;
        if (lead.effectiveRank == Rank.king) score += 20000;
        break;
      case AiPersonality.safe:
        // Avoids specials unless forced; favours shedding high regular cards.
        if (_isSpecial(lead) && state.activePenaltyCount == 0) score -= 20000;
        score += lead.effectiveRank.numericValue * 50;
        break;
      case AiPersonality.tricky:
        // Loves skips, kings, queens, and jokers.
        if (lead.effectiveRank == Rank.eight) score += 45000;
        if (lead.effectiveRank == Rank.king) score += 35000;
        if (lead.effectiveRank == Rank.queen) score += 25000;
        if (lead.isJoker) score += 30000;
        break;
    }
  }

  return _AiPlayChoice(
    cards: choice.cards,
    declaredSuit: choice.declaredSuit,
    score: score,
  );
}

bool _leavesOnePlayable({
  required GameState state,
  required String aiPlayerId,
  required _AiPlayChoice choice,
}) {
  final after = applyPlay(
    state: state,
    playerId: aiPlayerId,
    cards: choice.cards,
    declaredSuit: choice.declaredSuit,
  );
  final aiAfter = after.players.firstWhere((p) => p.id == aiPlayerId);
  if (aiAfter.hand.length != 1) return false;
  final last = aiAfter.hand.first;
  return validatePlay(
        cards: [last],
        discardTop: after.discardTopCard!,
        state: after,
      ) ==
      null;
}

CardModel? _findImmediateSuitFollowUp({
  required GameState state,
  required String aiPlayerId,
  required Suit suit,
}) {
  final ai = state.players.firstWhere((p) => p.id == aiPlayerId);
  for (final card in ai.hand) {
    if (card.isJoker || card.effectiveSuit != suit) continue;
    if (validatePlay(
            cards: [card], discardTop: state.discardTopCard!, state: state) ==
        null) {
      return card;
    }
  }
  return null;
}

CardModel? _findAnyImmediateFollowUp({
  required GameState state,
  required String aiPlayerId,
}) {
  final ai = state.players.firstWhere((p) => p.id == aiPlayerId);
  for (final card in ai.hand) {
    if (validatePlay(
            cards: [card], discardTop: state.discardTopCard!, state: state) ==
        null) {
      if (!card.isJoker) return card;
      return _resolveJokerStrategically(
          state: state, aiHand: ai.hand, joker: card);
    }
  }
  return null;
}

int _nextOpponentCardCount({
  required GameState state,
  required String aiPlayerId,
}) {
  final players = state.players;
  final aiIndex = players.indexWhere((p) => p.id == aiPlayerId);
  if (aiIndex < 0 || players.length < 2) return 99;
  final step = state.direction == PlayDirection.clockwise ? 1 : -1;
  var idx = aiIndex;
  idx = (idx + step) % players.length;
  if (idx < 0) idx += players.length;
  return players[idx].cardCount;
}

CardModel _resolveJokerStrategically({
  required GameState state,
  required List<CardModel> aiHand,
  required CardModel joker,
}) {
  final options = getValidJokerOptions(
    state: state,
    discardTop: state.discardTopCard!,
  );
  if (options.isEmpty) return joker;

  // If Joker is the second-last card, declare the exact last card to win now.
  final nonJoker = aiHand.where((c) => c.id != joker.id).toList();
  if (nonJoker.length == 1) {
    final last = nonJoker.first;
    final direct = options.where(
        (o) => o.rank == last.effectiveRank && o.suit == last.effectiveSuit);
    if (direct.isNotEmpty) {
      return joker.copyWith(
        jokerDeclaredRank: direct.first.rank,
        jokerDeclaredSuit: direct.first.suit,
      );
    }
  }

  final preferredSuit = _chooseBestAceSuit(
    state: state,
    aiPlayerId: state.currentPlayerId,
    hand: aiHand,
    excludingCardId: joker.id,
  );
  final suitCounts = <Suit, int>{for (final s in Suit.values) s: 0};
  for (final card in nonJoker) {
    if (card.isJoker) continue;
    suitCounts[card.effectiveSuit] = suitCounts[card.effectiveSuit]! + 1;
  }

  List<CardModel> filtered = options.where((opt) {
    final isBlackJack = opt.rank == Rank.jack &&
        (opt.suit == Suit.spades || opt.suit == Suit.clubs);
    // Avoid declaring Black Jack unless it's truly the only route left.
    if (isBlackJack && nonJoker.isNotEmpty) return false;
    return true;
  }).toList();
  if (filtered.isEmpty) filtered = options;

  filtered.sort((a, b) {
    final aSuitBoost = a.suit == preferredSuit ? 1 : 0;
    final bSuitBoost = b.suit == preferredSuit ? 1 : 0;
    if (aSuitBoost != bSuitBoost) return bSuitBoost - aSuitBoost;

    final aCount = suitCounts[a.suit] ?? 0;
    final bCount = suitCounts[b.suit] ?? 0;
    if (aCount != bCount) return bCount - aCount;

    final aFollow = _followUpCountAfterJoker(
      state: state,
      aiHand: aiHand,
      joker: joker,
      declared: a,
    );
    final bFollow = _followUpCountAfterJoker(
      state: state,
      aiHand: aiHand,
      joker: joker,
      declared: b,
    );
    if (aFollow != bFollow) return bFollow - aFollow;

    return b.rank.numericValue.compareTo(a.rank.numericValue);
  });

  final selected = filtered.first;
  return joker.copyWith(
    jokerDeclaredRank: selected.rank,
    jokerDeclaredSuit: selected.suit,
  );
}

int _followUpCountAfterJoker({
  required GameState state,
  required List<CardModel> aiHand,
  required CardModel joker,
  required CardModel declared,
}) {
  final assigned = joker.copyWith(
    jokerDeclaredRank: declared.rank,
    jokerDeclaredSuit: declared.suit,
  );
  final after = applyPlay(
    state: state,
    playerId: state.currentPlayerId,
    cards: [assigned],
  );
  final remaining = aiHand.where((c) => c.id != joker.id);
  var count = 0;
  for (final card in remaining) {
    if (card.effectiveSuit != declared.suit) continue;
    if (validatePlay(
            cards: [card], discardTop: after.discardTopCard!, state: after) ==
        null) {
      count++;
    }
  }
  return count;
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

/// Higher weight when opponents are short on cards and likely lack [suit].
int _opponentAceSuitPressure({
  required GameState state,
  required String aiPlayerId,
  required Suit suit,
}) {
  var bonus = 0;
  for (final p in state.players) {
    if (p.id == aiPlayerId) continue;
    final missing = _suitInferenceBySession[state.sessionId]?[p.id];
    if (missing == null || missing.isEmpty) continue;
    final urgency = 12 - p.cardCount.clamp(1, 11);
    if (missing.contains(suit)) {
      bonus += 900 * urgency;
    } else {
      bonus -= 180 * urgency;
    }
  }
  return bonus;
}

Suit _chooseBestAceSuit({
  required GameState state,
  required String aiPlayerId,
  required List<CardModel> hand,
  required String excludingCardId,
}) {
  final suitOrder = [Suit.hearts, Suit.diamonds, Suit.clubs, Suit.spades];
  final counts = <Suit, int>{for (final suit in Suit.values) suit: 0};
  final minValue = <Suit, int>{for (final suit in Suit.values) suit: 999};

  for (final card in hand) {
    if (card.id == excludingCardId || card.isJoker) continue;
    final suit = card.effectiveSuit;
    counts[suit] = counts[suit]! + 1;
    if (card.effectiveRank.numericValue < minValue[suit]!) {
      minValue[suit] = card.effectiveRank.numericValue;
    }
  }

  final minOppCards = state.players
      .where((p) => p.id != aiPlayerId)
      .map((p) => p.cardCount)
      .fold<int>(99, (a, b) => a < b ? a : b);
  final oppWeight = minOppCards <= 3 ? 3 : 1;

  return suitOrder.reduce((best, next) {
    final bestScore = counts[best]! * 10000 +
        _opponentAceSuitPressure(
          state: state,
          aiPlayerId: aiPlayerId,
          suit: best,
        ) *
            oppWeight;
    final nextScore = counts[next]! * 10000 +
        _opponentAceSuitPressure(
          state: state,
          aiPlayerId: aiPlayerId,
          suit: next,
        ) *
            oppWeight;
    if (nextScore > bestScore) return next;
    if (nextScore < bestScore) return best;

    final bestCount = counts[best]!;
    final nextCount = counts[next]!;
    if (nextCount > bestCount) return next;
    if (nextCount < bestCount) return best;

    final bestLowest = minValue[best]!;
    final nextLowest = minValue[next]!;
    if (nextLowest < bestLowest) return next;
    return best;
  });
}
