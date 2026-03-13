import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/services/game_log_formatter.dart';

void main() {
  CardModel c(Rank r, Suit s, [String? id]) =>
      CardModel(id: id ?? '${r.name}_${s.name}', rank: r, suit: s);

  group('GameLogFormatter', () {
    test('single card play', () {
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'You',
        cardActions: [MoveCardAction(card: c(Rank.six, Suit.spades))],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(GameLogFormatter.formatMove(entry), 'played 6♠');
      expect(GameLogFormatter.isSpecialEntry(entry), isFalse);
    });

    test('3 cards play', () {
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'You',
        cardActions: [
          MoveCardAction(card: c(Rank.six, Suit.spades)),
          MoveCardAction(card: c(Rank.six, Suit.hearts)),
          MoveCardAction(card: c(Rank.six, Suit.diamonds)),
        ],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played 6♠ 6♥ 6♦',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isFalse);
    });

    test('6 cards play — all shown, single line', () {
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'You',
        cardActions: [
          MoveCardAction(card: c(Rank.six, Suit.spades)),
          MoveCardAction(card: c(Rank.six, Suit.hearts)),
          MoveCardAction(card: c(Rank.six, Suit.diamonds)),
          MoveCardAction(card: c(Rank.six, Suit.clubs)),
          MoveCardAction(card: c(Rank.five, Suit.hearts)),
          MoveCardAction(card: c(Rank.five, Suit.clubs)),
        ],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played 6♠ 6♥ 6♦ 6♣ 5♥ 5♣',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isFalse);
    });

    test('10 cards play — all shown, wraps to 2 lines', () {
      final cards = [
        c(Rank.two, Suit.spades),
        c(Rank.three, Suit.spades),
        c(Rank.four, Suit.spades),
        c(Rank.five, Suit.spades),
        c(Rank.six, Suit.spades),
        c(Rank.seven, Suit.spades),
        c(Rank.eight, Suit.spades),
        c(Rank.nine, Suit.spades),
        c(Rank.ten, Suit.spades),
        c(Rank.jack, Suit.spades),
      ];
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'You',
        cardActions: cards.map((c) => MoveCardAction(card: c)).toList(),
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played 2♠ 3♠ 4♠ 5♠ 6♠ 7♠ 8♠ 9♠ 10♠ J♠',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isTrue);
    });

    test('12 cards play (penalty dump scenario) — all shown', () {
      final cards = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.six, Suit.hearts),
        c(Rank.seven, Suit.hearts),
        c(Rank.eight, Suit.hearts),
        c(Rank.nine, Suit.hearts),
        c(Rank.ten, Suit.hearts),
        c(Rank.jack, Suit.hearts),
        c(Rank.queen, Suit.hearts),
        c(Rank.king, Suit.hearts),
      ];
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'You',
        cardActions: cards.map((c) => MoveCardAction(card: c)).toList(),
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played 2♥ 3♥ 4♥ 5♥ 6♥ 7♥ 8♥ 9♥ 10♥ J♥ Q♥ K♥',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isTrue);
    });

    test('draw entry', () {
      final entry = MoveLogEntry.draw(
        playerId: 'p1',
        playerName: 'Marcus',
        drawCount: 1,
      );
      expect(GameLogFormatter.formatMove(entry), 'drew 1 card');
    });

    test('penalty draw entry', () {
      final entry = MoveLogEntry.draw(
        playerId: 'p1',
        playerName: 'Marcus',
        drawCount: 5,
      );
      expect(GameLogFormatter.formatMove(entry), 'drew 5 cards');
    });

    test('Joker played as Ace of Spades', () {
      final joker = CardModel(
        id: 'joker1',
        rank: Rank.joker,
        suit: Suit.spades,
        jokerDeclaredSuit: Suit.spades,
        jokerDeclaredRank: Rank.ace,
      );
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'Omar',
        cardActions: [MoveCardAction(card: joker)],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played Joker as A♠',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isTrue);
    });

    test('Joker played as 10 of Hearts', () {
      final joker = CardModel(
        id: 'joker2',
        rank: Rank.joker,
        suit: Suit.clubs,
        jokerDeclaredSuit: Suit.hearts,
        jokerDeclaredRank: Rank.ten,
      );
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'Marcus',
        cardActions: [MoveCardAction(card: joker)],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played Joker as 10♥',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isTrue);
    });

    test('Eight skip — all cards shown', () {
      final entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'Sofia',
        cardActions: [
          MoveCardAction(card: c(Rank.eight, Suit.hearts)),
          MoveCardAction(card: c(Rank.eight, Suit.clubs)),
          MoveCardAction(card: c(Rank.eight, Suit.spades)),
        ],
        skippedPlayerNames: ['Ben Kowalski', 'Omar Al-Rashid', 'Jordan Kim'],
        turnContinues: false,
      );
      expect(
        GameLogFormatter.formatMove(entry),
        'played 8♥ 8♣ 8♠, skipped Ben Kowalski, Omar Al-Rashid & Jordan Kim',
      );
      expect(GameLogFormatter.isSpecialEntry(entry), isTrue);
    });
  });

  group('Visual demo (prints to console)', () {
    test('print formatted outputs for review', () {
      final examples = [
        (
          '1 card',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [MoveCardAction(card: c(Rank.six, Suit.spades))],
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
        (
          '6 cards (same rank + sequence)',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [
              MoveCardAction(card: c(Rank.six, Suit.spades)),
              MoveCardAction(card: c(Rank.six, Suit.hearts)),
              MoveCardAction(card: c(Rank.six, Suit.diamonds)),
              MoveCardAction(card: c(Rank.five, Suit.hearts)),
              MoveCardAction(card: c(Rank.five, Suit.clubs)),
              MoveCardAction(card: c(Rank.five, Suit.spades)),
            ],
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
        (
          '10 cards (full sequence)',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [
              c(Rank.two, Suit.spades),
              c(Rank.three, Suit.spades),
              c(Rank.four, Suit.spades),
              c(Rank.five, Suit.spades),
              c(Rank.six, Suit.spades),
              c(Rank.seven, Suit.spades),
              c(Rank.eight, Suit.spades),
              c(Rank.nine, Suit.spades),
              c(Rank.ten, Suit.spades),
              c(Rank.jack, Suit.spades),
            ].map((c) => MoveCardAction(card: c)).toList(),
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
        (
          '12 cards (post-penalty dump)',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [
              c(Rank.two, Suit.hearts),
              c(Rank.three, Suit.hearts),
              c(Rank.four, Suit.hearts),
              c(Rank.five, Suit.hearts),
              c(Rank.six, Suit.hearts),
              c(Rank.seven, Suit.hearts),
              c(Rank.eight, Suit.hearts),
              c(Rank.nine, Suit.hearts),
              c(Rank.ten, Suit.hearts),
              c(Rank.jack, Suit.hearts),
              c(Rank.queen, Suit.hearts),
              c(Rank.king, Suit.hearts),
            ].map((c) => MoveCardAction(card: c)).toList(),
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
      ];

      // Fix the 3rd and 4th entries - MoveLogEntry.play expects cardActions, not a list from map
      final fixedExamples = <(String, MoveLogEntry)>[
        examples[0],
        examples[1],
        (
          '10 cards (full sequence)',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [
              c(Rank.two, Suit.spades),
              c(Rank.three, Suit.spades),
              c(Rank.four, Suit.spades),
              c(Rank.five, Suit.spades),
              c(Rank.six, Suit.spades),
              c(Rank.seven, Suit.spades),
              c(Rank.eight, Suit.spades),
              c(Rank.nine, Suit.spades),
              c(Rank.ten, Suit.spades),
              c(Rank.jack, Suit.spades),
            ]
                .map((card) => MoveCardAction(card: card))
                .toList(),
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
        (
          '12 cards (post-penalty dump)',
          MoveLogEntry.play(
            playerId: 'p1',
            playerName: 'You',
            cardActions: [
              c(Rank.two, Suit.hearts),
              c(Rank.three, Suit.hearts),
              c(Rank.four, Suit.hearts),
              c(Rank.five, Suit.hearts),
              c(Rank.six, Suit.hearts),
              c(Rank.seven, Suit.hearts),
              c(Rank.eight, Suit.hearts),
              c(Rank.nine, Suit.hearts),
              c(Rank.ten, Suit.hearts),
              c(Rank.jack, Suit.hearts),
              c(Rank.queen, Suit.hearts),
              c(Rank.king, Suit.hearts),
            ]
                .map((card) => MoveCardAction(card: card))
                .toList(),
            skippedPlayerNames: [],
            turnContinues: false,
          ),
        ),
      ];

      for (final (label, entry) in fixedExamples) {
        final formatted = GameLogFormatter.formatMove(entry);
        final isSpecial = GameLogFormatter.isSpecialEntry(entry);
        final display = 'You $formatted';
        // ignore: avoid_print
        print('\n--- $label ---');
        // ignore: avoid_print
        print('  Formatted: "$display"');
        // ignore: avoid_print
        print('  Lines: ${isSpecial ? "2 (wraps)" : "1"}');
        // ignore: avoid_print
        print('  Length: ${display.length} chars');
      }
      // ignore: avoid_print
      print('\n--- Draw example ---');
      // ignore: avoid_print
      print('  Marcus drew 1 card');
      // ignore: avoid_print
      print('\n--- Joker example ---');
      final jokerEntry = MoveLogEntry.play(
        playerId: 'j1',
        playerName: 'Marcus',
        cardActions: [
          MoveCardAction(
            card: CardModel(
              id: 'joker1',
              rank: Rank.joker,
              suit: Suit.spades,
              jokerDeclaredRank: Rank.ace,
              jokerDeclaredSuit: Suit.spades,
            ),
          ),
        ],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      // ignore: avoid_print
      print('  Marcus ${GameLogFormatter.formatMove(jokerEntry)}');
      final joker10Entry = MoveLogEntry.play(
        playerId: 'p1',
        playerName: 'Sofia',
        cardActions: [
          MoveCardAction(
            card: CardModel(
              id: 'joker2',
              rank: Rank.joker,
              suit: Suit.spades,
              jokerDeclaredSuit: Suit.hearts,
              jokerDeclaredRank: Rank.ten,
            ),
          ),
        ],
        skippedPlayerNames: [],
        turnContinues: false,
      );
      // ignore: avoid_print
      print('  Sofia ${GameLogFormatter.formatMove(joker10Entry)}');
      // ignore: avoid_print
      print('\n--- Eight skip example ---');
      final skipEntry = MoveLogEntry.play(
        playerId: 'sf',
        playerName: 'Sofia',
        cardActions: [
          MoveCardAction(card: c(Rank.eight, Suit.hearts)),
          MoveCardAction(card: c(Rank.eight, Suit.clubs)),
          MoveCardAction(card: c(Rank.eight, Suit.spades)),
        ],
        skippedPlayerNames: ['Ben Kowalski', 'Omar Al-Rashid', 'Jordan Kim'],
        turnContinues: false,
      );
      // ignore: avoid_print
      print('  Sofia ${GameLogFormatter.formatMove(skipEntry)}');
    });
  });
}
