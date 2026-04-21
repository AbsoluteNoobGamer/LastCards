import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart'
    show needsUndeclaredLastCardsDraw;

CardModel c(Rank rank, Suit suit) =>
    CardModel(id: '${rank.name}_${suit.name}', rank: rank, suit: suit);

GameState stateForP1(List<CardModel> hand, {required CardModel discardTop}) {
  return GameState(
    sessionId: 't',
    phase: GamePhase.playing,
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 10,
    players: [
      PlayerModel(
        id: 'p1',
        displayName: 'P1',
        tablePosition: TablePosition.bottom,
        hand: hand,
        cardCount: hand.length,
      ),
      PlayerModel(
        id: 'p2',
        displayName: 'P2',
        tablePosition: TablePosition.top,
        hand: const [],
        cardCount: 0,
      ),
    ],
  );
}

void main() {
  group('canHandClearInOneTurnHandOnly', () {
    test('Joker in hand can chain with adjacent card', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.joker, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('single non-Queen is fine', () {
      expect(canHandClearInOneTurnHandOnly([c(Rank.five, Suit.hearts)]), isTrue);
    });

    test('single Queen fails', () {
      expect(canHandClearInOneTurnHandOnly([c(Rank.queen, Suit.spades)]), isFalse);
    });

    test('sequence + value chain', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('gap with no joker fails', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
    });

    test('Queen covered then play', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.five, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('two Queens ending on Queen fails', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.queen, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
    });

    test('unrelated pairs fail', () {
      expect(
        canHandClearInOneTurnHandOnly([
          c(Rank.three, Suit.hearts),
          c(Rank.seven, Suit.diamonds),
        ]),
        isFalse,
      );
    });

    test('penalty chain 2–2–J', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.two, Suit.clubs),
        c(Rank.jack, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });
  });

  group('canClearHandInOneTurn (engine)', () {
    test(
        '2p King repeat turn: K♥ then 4♥ clears on 6♥ or 9♥ pile though hand-only is false',
        () {
      final hand = [
        c(Rank.king, Suit.hearts),
        c(Rank.four, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final onSix = stateForP1(hand, discardTop: c(Rank.six, Suit.hearts));
      expect(canClearHandInOneTurn(state: onSix, playerId: 'p1'), isTrue);

      final onNine = stateForP1(hand, discardTop: c(Rank.nine, Suit.hearts));
      expect(canClearHandInOneTurn(state: onNine, playerId: 'p1'), isTrue);
    });

    test(
        '2p Eight skip repeat turn: 8♥ then 4♥ clears on 6♥ or 9♥ pile though hand-only is false',
        () {
      final hand = [
        c(Rank.eight, Suit.hearts),
        c(Rank.four, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final onSix = stateForP1(hand, discardTop: c(Rank.six, Suit.hearts));
      expect(canClearHandInOneTurn(state: onSix, playerId: 'p1'), isTrue);

      final onNine = stateForP1(hand, discardTop: c(Rank.nine, Suit.hearts));
      expect(canClearHandInOneTurn(state: onNine, playerId: 'p1'), isTrue);
    });

    test(
        '3 players: multiple actions in one turn (e.g. pair then 6♠) even when '
        'nextPlayerId would be another seat',
        () {
      final hand = [
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.spades),
        c(Rank.six, Suit.spades),
      ];
      final state = GameState(
        sessionId: 't',
        phase: GamePhase.playing,
        currentPlayerId: 'p1',
        direction: PlayDirection.clockwise,
        discardTopCard: c(Rank.five, Suit.hearts),
        drawPileCount: 10,
        players: [
          PlayerModel(
            id: 'p1',
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: hand,
            cardCount: hand.length,
          ),
          PlayerModel(
            id: 'p2',
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p3',
            displayName: 'P3',
            tablePosition: TablePosition.left,
            hand: const [],
            cardCount: 0,
          ),
        ],
      );
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test(
        '5 players: four 8s in one play + 5♥ clears via skip wrap (hand-only false)',
        () {
      final hand = [
        c(Rank.eight, Suit.hearts),
        c(Rank.eight, Suit.diamonds),
        c(Rank.eight, Suit.clubs),
        c(Rank.eight, Suit.spades),
        c(Rank.five, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final state = GameState(
        sessionId: 't',
        phase: GamePhase.playing,
        currentPlayerId: 'p1',
        direction: PlayDirection.clockwise,
        discardTopCard: c(Rank.eight, Suit.hearts),
        drawPileCount: 10,
        players: [
          PlayerModel(
            id: 'p1',
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: hand,
            cardCount: hand.length,
          ),
          PlayerModel(
            id: 'p2',
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p3',
            displayName: 'P3',
            tablePosition: TablePosition.left,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p4',
            displayName: 'P4',
            tablePosition: TablePosition.right,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p5',
            displayName: 'P5',
            tablePosition: TablePosition.bottomLeft,
            hand: const [],
            cardCount: 0,
          ),
        ],
      );
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test('sequence then value chain: hand-only path still succeeds vs bad discard', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      final mismatchTop = c(Rank.king, Suit.spades);
      final state = stateForP1(hand, discardTop: mismatchTop);
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test(
        'Joker + failing hand-only chain: engine not clearable; human bluff uses Joker exemption at call site',
        () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.four, Suit.diamonds),
        c(Rank.six, Suit.clubs),
        c(Rank.eight, Suit.spades),
        c(Rank.joker, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
      final state = stateForP1(hand, discardTop: c(Rank.king, Suit.clubs));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
      final hasJoker = hand.any((c) => c.isJoker);
      final bluff = !hasJoker &&
          !canClearHandInOneTurn(state: state, playerId: 'p1');
      expect(bluff, isFalse);
    });

    test('non-Joker chain [2♥,3♥,4♥,4♠] clearable regardless of discard top', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.four, Suit.spades),
      ];
      final state = stateForP1(hand, discardTop: c(Rank.ace, Suit.diamonds));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test('non-Joker hand with broken run returns false', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.four, Suit.spades),
      ];
      final state = stateForP1(hand, discardTop: c(Rank.two, Suit.hearts));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
    });
  });

  group('shouldShowLastCardsButton', () {
    test('respects bust and declared (no hand-size gate)', () {
      expect(
        shouldShowLastCardsButton(
          isBustMode: true,
          alreadyDeclared: false,
        ),
        isFalse,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          alreadyDeclared: false,
        ),
        isTrue,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          alreadyDeclared: true,
        ),
        isFalse,
      );
    });
  });

  group('applyOpeningSeatLastCardsSeedIfNeeded', () {
    test('seeds opener when hand was clearable at deal (offline/online parity)', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      expect(
        state.playerById('p1')!.lastCardsHandWasClearableAtTurnStart,
        isTrue,
      );

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isTrue);
      expect(r.isBluff, isFalse);
      expect(r.state.lastCardsDeclaredBy, contains('p1'));
    });

    test('no-op when opener already declared', () {
      final hand = [c(Rank.five, Suit.hearts)];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      state = state.copyWith(lastCardsDeclaredBy: {'p1'});

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isFalse);
    });

    test('no-op in bust mode', () {
      final hand = [c(Rank.five, Suit.hearts)];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: true);

      final r = applyOpeningSeatLastCardsSeedIfNeeded(
        state: state,
        isBustMode: true,
      );
      expect(r.applied, isFalse);
    });

    test('empty hand would not trigger undeclared draw after seed', () {
      var state = stateForP1(
        [
          c(Rank.five, Suit.hearts),
        ],
        discardTop: c(Rank.five, Suit.hearts),
      );
      state = initializeFirstTurnClearability(state, isBustMode: false);
      final seeded = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(seeded.applied, isTrue);
      final empty = seeded.state.copyWith(
        players: seeded.state.players
            .map((p) {
              if (p.id != 'p1') return p;
              return p.copyWith(hand: [], cardCount: 0);
            })
            .toList(),
      );
      expect(
        needsUndeclaredLastCardsDraw(state: empty, playerId: 'p1'),
        isFalse,
      );
    });
  });
}
