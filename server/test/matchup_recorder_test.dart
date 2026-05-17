import 'package:last_cards_server/trophy_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('matchupPairDocId', () {
    test('orders uids lexicographically', () {
      expect(
        matchupPairDocId('zzz', 'aaa'),
        'aaa_zzz',
      );
      expect(matchupPairDocId('aaa', 'zzz'), 'aaa_zzz');
    });
  });

  group('appendRecentResult', () {
    test('caps at five entries', () {
      expect(
        appendRecentResult(
          const ['win', 'loss', 'win', 'loss', 'win'],
          'loss',
        ),
        ['loss', 'win', 'loss', 'win', 'loss'],
      );
    });
  });

  group('headToHeadRow', () {
    test('builds json map', () {
      final row = headToHeadRow(
        opponentUid: 'opp',
        opponentName: 'Bob',
        yourWins: 3,
        theirWins: 2,
        recentResults: const ['win', 'loss'],
      );
      expect(row['yourWins'], 3);
      expect(row['recentResults'], ['win', 'loss']);
    });
  });
}
