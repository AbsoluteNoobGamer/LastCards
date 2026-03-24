import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart';

CardModel c(Rank rank, Suit suit) =>
    CardModel(id: '${rank.name}_${suit.name}', rank: rank, suit: suit);

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
    test('sequence then value chain is clearable with valid discard', () {
      final top = c(Rank.two, Suit.hearts);
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      final state = GameState(
        sessionId: 't',
        phase: GamePhase.playing,
        currentPlayerId: 'p1',
        direction: PlayDirection.clockwise,
        discardTopCard: top,
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
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });
  });

  group('shouldShowLastCardsButton', () {
    test('respects bust, turn, declared (no hand-size gate)', () {
      expect(
        shouldShowLastCardsButton(
          isBustMode: true,
          isLocalTurn: false,
          alreadyDeclared: false,
        ),
        isFalse,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          isLocalTurn: true,
          alreadyDeclared: false,
        ),
        isFalse,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          isLocalTurn: false,
          alreadyDeclared: true,
        ),
        isFalse,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          isLocalTurn: false,
          alreadyDeclared: false,
        ),
        isTrue,
      );
    });
  });
}
