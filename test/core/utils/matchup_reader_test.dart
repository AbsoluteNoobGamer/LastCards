import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/utils/matchup_reader.dart';

void main() {
  test('matchupPairDocId orders uids lexicographically', () {
    expect(matchupPairDocId('zzz', 'aaa'), 'aaa_zzz');
    expect(matchupPairDocId('aaa', 'zzz'), 'aaa_zzz');
  });
}
