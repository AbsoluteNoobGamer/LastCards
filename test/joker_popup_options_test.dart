import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/offline_game_engine.dart';

GameState _baseState({
  required CardModel discardTop,
  int actionsThisTurn = 0,
  int cardsPlayedThisTurn = 0,
  CardModel? lastPlayedThisTurn,
  int activePenaltyCount = 0,
  List<CardModel>? localHand,
  Suit? suitLock,
  Suit? queenSuitLock,
}) {
  return GameState(
    sessionId: 'test_session',
    phase: GamePhase.playing,
    players: [
      PlayerModel(
        id: 'p1',
        displayName: 'You',
        tablePosition: TablePosition.bottom,
        hand: localHand ?? const [],
        cardCount: (localHand ?? const []).length,
      ),
      const PlayerModel(
        id: 'p2',
        displayName: 'AI',
        tablePosition: TablePosition.top,
        cardCount: 5,
      ),
    ],
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 20,
    activePenaltyCount: activePenaltyCount,
    actionsThisTurn: actionsThisTurn,
    cardsPlayedThisTurn: cardsPlayedThisTurn,
    lastPlayedThisTurn: lastPlayedThisTurn,
    suitLock: suitLock,
    queenSuitLock: queenSuitLock,
  );
}

void main() {
  group('Joker popup options by context', () {
    test('Context A: Joker on 5♥ returns 12 hearts + 3 cross-suit 5s = 15', () {
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state = _baseState(discardTop: top, actionsThisTurn: 0);

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final sameSuit = options.where((c) => c.suit == Suit.hearts).toList();
      final sameValueOtherSuits = options
          .where((c) => c.rank == Rank.five && c.suit != Suit.hearts)
          .toList();

      expect(options.length, 15);
      expect(sameSuit.length, 12);
      expect(sameValueOtherSuits.length, 3);
      expect(options.any((c) => c.rank == Rank.five && c.suit == Suit.hearts),
          isFalse);
    });

    test('Context A: Joker on K♠ returns 12 spades + 3 cross-suit kings = 15',
        () {
      const top = CardModel(id: 'ks', rank: Rank.king, suit: Suit.spades);
      final state = _baseState(discardTop: top, actionsThisTurn: 0);

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final sameSuit = options.where((c) => c.suit == Suit.spades).toList();
      final sameValueOtherSuits = options
          .where((c) => c.rank == Rank.king && c.suit != Suit.spades)
          .toList();

      expect(options.length, 15);
      expect(sameSuit.length, 12);
      expect(sameValueOtherSuits.length, 3);
      expect(options.any((c) => c.rank == Rank.king && c.suit == Suit.spades),
          isFalse);
    });

    test(
        'Turn starter after Ace suit change: A♠ + suitLock hearts → 12♥ + 3 aces = 15',
        () {
      const top = CardModel(id: 'as', rank: Rank.ace, suit: Suit.spades);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        suitLock: Suit.hearts,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final hearts = options.where((c) => c.suit == Suit.hearts).toList();
      final crossSuitAces = options
          .where((c) => c.rank == Rank.ace && c.suit != Suit.hearts)
          .toList();

      expect(options.length, 15);
      expect(hearts.length, 12);
      expect(crossSuitAces.length, 3);
      expect(
        crossSuitAces.map((c) => c.suit).toSet(),
        equals({Suit.spades, Suit.diamonds, Suit.clubs}),
      );
      expect(
        options.any((c) => c.suit == Suit.spades && c.rank != Rank.ace),
        isFalse,
      );
    });

    test('Turn starter with no suitLock: still uses discard natural suit', () {
      const top = CardModel(id: 'as', rank: Rank.ace, suit: Suit.spades);
      final state = _baseState(discardTop: top, actionsThisTurn: 0);

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final spades = options.where((c) => c.suit == Suit.spades).toList();
      final otherAces = options
          .where((c) => c.rank == Rank.ace && c.suit != Suit.spades)
          .toList();

      expect(options.length, 15);
      expect(spades.length, 12);
      expect(otherAces.length, 3);
    });

    test(
        'Queen suit lock: only locked suit cards + other Queens (Q♠ on pile, lock ♥)',
        () {
      const top = CardModel(id: 'qs', rank: Rank.queen, suit: Suit.spades);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        queenSuitLock: Suit.hearts,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final hearts = options.where((c) => c.suit == Suit.hearts).toList();
      final queensNotHearts = options
          .where((c) => c.rank == Rank.queen && c.suit != Suit.hearts)
          .toList();

      expect(options.length, 15);
      expect(hearts.length, 13);
      expect(queensNotHearts.length, 2);
      expect(
        queensNotHearts.map((c) => c.shortLabel).toSet(),
        {'Q♦', 'Q♣'},
      );
      expect(options.any((c) => c.suit == Suit.spades && c.rank != Rank.queen),
          isFalse);
    });

    test(
        'Queen suit lock + active penalty: 2s and Jacks bypass lock (mirrors validatePlay)',
        () {
      const top = CardModel(id: '3c', rank: Rank.three, suit: Suit.clubs);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        activePenaltyCount: 4,
        queenSuitLock: Suit.hearts,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.turnStarter,
        contextTopCard: top,
      );

      final labels = options.map((c) => c.shortLabel).toSet();
      // Not locked suit and not Queen — must come from penalty-addressing rule.
      expect(labels, containsAll(['2♠', '2♣', 'J♠', 'J♣', 'J♦']));
    });

    test(
        'Context B: Joker after 5♥ returns 4♥, 6♥, 5♠, 5♦, 5♣ exactly (5 total)',
        () {
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: top,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.midTurnContinuance,
        contextTopCard: top,
      );

      final labels = options.map((c) => c.shortLabel).toSet();
      expect(options.length, 5);
      expect(labels, containsAll({'4♥', '6♥', '5♠', '5♦', '5♣'}));
      expect(labels.length, 5);
    });

    test(
        'Context B edge case: Joker after A♥ returns 2♥, K♥ (Ace wrap) + 3 cross-suit Aces = 5',
        () {
      const top = CardModel(id: 'ah', rank: Rank.ace, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: top,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.midTurnContinuance,
        contextTopCard: top,
      );

      final labels = options.map((c) => c.shortLabel).toSet();
      expect(options.length, 5);
      expect(labels, containsAll({'2♥', 'K♥', 'A♠', 'A♦', 'A♣'}));
    });

    test(
        'Context B edge case: Joker after 2♥ returns sequence, cross-suit 2s, and penalty-on-penalty Jacks = 9',
        () {
      const top = CardModel(id: '2h', rank: Rank.two, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: top,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.midTurnContinuance,
        contextTopCard: top,
      );

      final labels = options.map((c) => c.shortLabel).toSet();
      expect(options.length, 9);
      expect(labels, containsAll({
        'A♥',
        '3♥',
        '2♠',
        '2♦',
        '2♣',
        'J♠',
        'J♣',
        'J♥',
        'J♦',
      }));
    });

    test(
        'Context B with active penalty: Joker after 2♥ returns sequence continuations AND penalty addressing cards',
        () {
      // 2♥ played mid-turn on top of another penalty card, activePenaltyCount = 2
      const top = CardModel(id: '2h', rank: Rank.two, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: top,
        activePenaltyCount: 2,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
        context: JokerPlayContext.midTurnContinuance,
        contextTopCard: top,
      );

      final labels = options.map((c) => c.shortLabel).toSet();
      
      // Should contain sequence continuations for 2♥
      expect(labels, containsAll({'A♥', '3♥'}));
      
      // Should contain penalty addressing cards (all 2s, Black Jacks, Red Jacks)
      // Note: 2♥ is the target, so it's excluded from options.
      expect(labels, containsAll({'2♠', '2♦', '2♣'})); // Other 2s
      expect(labels, containsAll({'J♠', 'J♣'})); // Black Jacks
      expect(labels, containsAll({'J♥', 'J♦'})); // Red Jacks
    });
  });

  group('Joker regression checks', () {
    test('shortLabel uses declared Joker representation not base rank/suit', () {
      const joker = CardModel(
        id: 'j1',
        rank: Rank.joker,
        suit: Suit.spades,
        jokerDeclaredRank: Rank.five,
        jokerDeclaredSuit: Suit.hearts,
      );
      expect(joker.shortLabel, '5♥');
    });

    test(
        'default Joker context uses cardsPlayedThisTurn not actionsThisTurn (draw then Joker)',
        () {
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 0,
      );

      final options = getValidJokerOptions(
        state: state,
        discardTop: top,
      );

      expect(
        options.length,
        15,
        reason:
            'Turn starter (no cards played yet): 12 same suit + 3 cross-rank',
      );
    });

    test('Pickup stack logic unchanged: playing a 2 increases penalty by 2',
        () {
      const top = CardModel(id: '9c', rank: Rank.nine, suit: Suit.clubs);
      const twoHearts = CardModel(id: '2h', rank: Rank.two, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        localHand: const [twoHearts],
      );

      final next = applyPlay(state: state, playerId: 'p1', cards: [twoHearts]);
      expect(next.activePenaltyCount, 2);
    });

    test('Red Jack reset mechanic still clears pickup pile', () {
      const top = CardModel(id: '2s', rank: Rank.two, suit: Suit.spades);
      const redJack = CardModel(id: 'jh', rank: Rank.jack, suit: Suit.hearts);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        activePenaltyCount: 7,
        localHand: const [redJack],
      );

      final next = applyPlay(state: state, playerId: 'p1', cards: [redJack]);
      expect(next.activePenaltyCount, 0);
    });

    test('Joker as turn starter does not auto-end turn', () {
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      const joker = CardModel(id: 'joker', rank: Rank.joker, suit: Suit.spades);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 0,
        localHand: const [joker],
      );

      final assigned = joker.copyWith(
        jokerDeclaredRank: Rank.four,
        jokerDeclaredSuit: Suit.hearts,
      );
      final next = applyPlay(state: state, playerId: 'p1', cards: [assigned]);
      expect(next.currentPlayerId, state.currentPlayerId);
      expect(next.actionsThisTurn, 1);
    });

    test('Joker mid-turn does not auto-end turn', () {
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      const joker = CardModel(id: 'joker', rank: Rank.joker, suit: Suit.spades);
      final state = _baseState(
        discardTop: top,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: top,
        localHand: const [joker],
      );

      final assigned = joker.copyWith(
        jokerDeclaredRank: Rank.six,
        jokerDeclaredSuit: Suit.hearts,
      );
      final next = applyPlay(state: state, playerId: 'p1', cards: [assigned]);
      expect(next.currentPlayerId, state.currentPlayerId);
      expect(next.actionsThisTurn, 2);
    });
  });
}
