import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/features/leaderboard/data/local_combo_leaderboard_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  CardModel c(Rank r, Suit s) => CardModel(id: '${r.name}_${s.name}', rank: r, suit: s);

  group('LocalComboLeaderboardStore.recordIfBest', () {
    test('first record for a player is always accepted', () async {
      final (entry, isNew) =
          await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 4,
        cards: [c(Rank.four, Suit.hearts)],
        achievedAtMillis: 1000,
      );

      expect(isNew, isTrue);
      expect(entry.comboCount, 4);
      expect(entry.cards, hasLength(1));
    });

    test('a bigger combo replaces the stored record', () async {
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 4,
        cards: [c(Rank.four, Suit.hearts)],
        achievedAtMillis: 1000,
      );

      final (entry, isNew) =
          await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 7,
        cards: List.generate(7, (i) => c(Rank.values[i], Suit.spades)),
        achievedAtMillis: 2000,
      );

      expect(isNew, isTrue);
      expect(entry.comboCount, 7);
      expect(entry.cards, hasLength(7));
    });

    test('a smaller combo does NOT overwrite the stored record', () async {
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 7,
        cards: List.generate(7, (i) => c(Rank.values[i], Suit.spades)),
        achievedAtMillis: 1000,
      );

      final (entry, isNew) =
          await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 4,
        cards: [c(Rank.four, Suit.hearts)],
        achievedAtMillis: 2000,
      );

      expect(isNew, isFalse);
      expect(entry.comboCount, 7, reason: 'the higher record must be kept');
    });

    test('an equal combo does NOT overwrite the stored record', () async {
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 5,
        cards: List.generate(5, (i) => c(Rank.values[i], Suit.spades)),
        achievedAtMillis: 1000,
      );

      final (_, isNew) = await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 5,
        cards: List.generate(5, (i) => c(Rank.values[i], Suit.hearts)),
        achievedAtMillis: 2000,
      );

      expect(isNew, isFalse);
    });

    test('entries for different players are independent', () async {
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 8,
        cards: List.generate(8, (i) => c(Rank.values[i], Suit.spades)),
        achievedAtMillis: 1000,
      );
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p2',
        displayName: 'Sam',
        comboCount: 3,
        cards: [c(Rank.three, Suit.clubs)],
        achievedAtMillis: 1000,
      );

      final entries = await LocalComboLeaderboardStore.instance.loadEntries();
      expect(entries, hasLength(2));
      expect(entries.first.uid, 'p1', reason: 'sorted by comboCount descending');
      expect(entries.last.uid, 'p2');
    });

    test('cards round-trip through persistence correctly', () async {
      final played = [c(Rank.king, Suit.hearts), c(Rank.king, Suit.spades)];
      await LocalComboLeaderboardStore.instance.recordIfBest(
        uid: 'p1',
        displayName: 'Alex',
        comboCount: 2,
        cards: played,
        achievedAtMillis: 1000,
      );

      final loaded = await LocalComboLeaderboardStore.instance.loadEntryForUser('p1');
      expect(loaded, isNotNull);
      expect(loaded!.cards.map((c) => (c.rank, c.suit)),
          played.map((c) => (c.rank, c.suit)));
    });
  });
}
