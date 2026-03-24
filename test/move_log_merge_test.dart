import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/models/move_log_merge.dart';

void main() {
  group('mergeOrPrependPlayLog', () {
    test('prepends first play of a turn', () {
      final entries = <MoveLogEntry>[];
      final c = CardModel(id: '1', rank: Rank.five, suit: Suit.hearts);
      mergeOrPrependPlayLog(
        entries,
        MoveLogEntry.play(
          playerId: 'p1',
          playerName: 'A',
          cardActions: [MoveCardAction(card: c)],
          skippedPlayerNames: const [],
          turnContinues: true,
        ),
      );
      expect(entries.length, 1);
      expect(entries.first.cardActions.length, 1);
    });

    test('merges second play when top.turnContinues is true', () {
      final c1 = CardModel(id: '1', rank: Rank.five, suit: Suit.hearts);
      final c2 = CardModel(id: '2', rank: Rank.five, suit: Suit.diamonds);
      final entries = <MoveLogEntry>[
        MoveLogEntry.play(
          playerId: 'p1',
          playerName: 'A',
          cardActions: [MoveCardAction(card: c1)],
          skippedPlayerNames: const [],
          turnContinues: true,
        ),
      ];
      mergeOrPrependPlayLog(
        entries,
        MoveLogEntry.play(
          playerId: 'p1',
          playerName: 'A',
          cardActions: [MoveCardAction(card: c2)],
          skippedPlayerNames: const [],
          turnContinues: false,
        ),
      );
      expect(entries.length, 1);
      expect(entries.first.cardActions.length, 2);
      expect(entries.first.turnContinues, false);
    });

    test('does not merge different player', () {
      final c = CardModel(id: '1', rank: Rank.five, suit: Suit.hearts);
      final entries = <MoveLogEntry>[
        MoveLogEntry.play(
          playerId: 'p1',
          playerName: 'A',
          cardActions: [MoveCardAction(card: c)],
          skippedPlayerNames: const [],
          turnContinues: true,
        ),
      ];
      final c2 = CardModel(id: '2', rank: Rank.six, suit: Suit.hearts);
      mergeOrPrependPlayLog(
        entries,
        MoveLogEntry.play(
          playerId: 'p2',
          playerName: 'B',
          cardActions: [MoveCardAction(card: c2)],
          skippedPlayerNames: const [],
          turnContinues: false,
        ),
      );
      expect(entries.length, 2);
      expect(entries.first.playerId, 'p2');
    });
  });
}
