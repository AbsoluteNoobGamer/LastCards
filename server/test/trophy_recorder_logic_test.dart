import 'package:last_cards_server/trophy_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('rankedResultStatMaps', () {
    test('winner gets +25 rating and wins', () {
      final m = rankedResultStatMaps(isWinner: true, playerCount: 4);
      expect(m.increments['rating'], 25);
      expect(m.increments['wins'], 1);
      expect(m.increments.containsKey('losses'), isFalse);
      expect(m.increments['gamesPlayed'], 1);
      expect(m.increments['gamesPlayed_4'], 1);
      expect(m.increments['wins_4'], 1);
    });

    test('loser gets -15 rating and losses', () {
      final m = rankedResultStatMaps(isWinner: false, playerCount: 4);
      expect(m.increments['rating'], -15);
      expect(m.increments['losses'], 1);
      expect(m.increments.containsKey('wins'), isFalse);
      expect(m.increments['losses_4'], 1);
    });

    test('playerCount below 2 has no bracket keys', () {
      final m = rankedResultStatMaps(isWinner: true, playerCount: 1);
      expect(m.increments.keys.every((k) => !k.contains('_')), isTrue);
      expect(m.defaultFields.keys.every((k) => !k.contains('_')), isTrue);
    });

    test('playerCount clamps bracket to 2–7', () {
      final m = rankedResultStatMaps(isWinner: true, playerCount: 99);
      expect(m.increments.containsKey('wins_7'), isTrue);
      expect(m.increments.containsKey('wins_99'), isFalse);
    });

    test('defaultFields include baseline rating and bracket zeros when bracketed',
        () {
      final m = rankedResultStatMaps(isWinner: false, playerCount: 3);
      expect(m.defaultFields['rating'], 1000);
      expect(m.defaultFields['gamesPlayed_3'], 0);
    });
  });

  group('rankedLeavePenaltyStatMaps', () {
    test('applies leave delta and counts', () {
      final m = rankedLeavePenaltyStatMaps();
      expect(m.increments['rating'], -20);
      expect(m.increments['leaves'], 1);
      expect(m.increments['gamesPlayed'], 1);
      expect(m.defaultFields['leaves'], 0);
    });
  });

  group('modeLeaderboardStatMaps', () {
    test('winner increments wins and bracket fields', () {
      final m = modeLeaderboardStatMaps(won: true, playerCount: 5);
      expect(m.increments['wins'], 1);
      expect(m.increments['gamesPlayed'], 1);
      expect(m.increments['wins_5'], 1);
      expect(m.increments['gamesPlayed_5'], 1);
      expect(m.increments.containsKey('losses'), isFalse);
    });

    test('loser increments losses', () {
      final m = modeLeaderboardStatMaps(won: false, playerCount: 5);
      expect(m.increments['losses'], 1);
      expect(m.increments['losses_5'], 1);
      expect(m.increments.containsKey('wins'), isFalse);
    });

    test('playerCount clamps bracket to 2–10', () {
      final m = modeLeaderboardStatMaps(won: true, playerCount: 100);
      expect(m.defaultFields.containsKey('wins_10'), isTrue);
      expect(m.defaultFields.containsKey('wins_100'), isFalse);
    });
  });

  group('modeLeaderboardUidEligible', () {
    test('null and empty are ineligible', () {
      expect(modeLeaderboardUidEligible(null), isFalse);
      expect(modeLeaderboardUidEligible(''), isFalse);
    });

    test('non-empty uid is eligible', () {
      expect(modeLeaderboardUidEligible('abc'), isTrue);
    });
  });
}
