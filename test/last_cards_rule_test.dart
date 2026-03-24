import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart';

CardModel c(Rank rank, Suit suit) =>
    CardModel(id: '${rank.name}_${suit.name}', rank: rank, suit: suit);

void main() {
  group('canHandClearInOneTurn', () {
    test('Joker in hand short-circuits to true', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.joker, Suit.spades),
      ];
      expect(canHandClearInOneTurn(hand), isTrue);
    });

    test('single non-Queen is fine', () {
      expect(canHandClearInOneTurn([c(Rank.five, Suit.hearts)]), isTrue);
    });

    test('single Queen fails', () {
      expect(canHandClearInOneTurn([c(Rank.queen, Suit.spades)]), isFalse);
    });

    test('sequence + value chain', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurn(hand), isTrue);
    });

    test('gap with no joker fails', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurn(hand), isFalse);
    });

    test('Queen covered then play', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.five, Suit.spades),
      ];
      expect(canHandClearInOneTurn(hand), isTrue);
    });

    test('two Queens ending on Queen fails', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.queen, Suit.hearts),
      ];
      expect(canHandClearInOneTurn(hand), isFalse);
    });

    test('unrelated pairs fail', () {
      expect(
        canHandClearInOneTurn([
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
      expect(canHandClearInOneTurn(hand), isTrue);
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
