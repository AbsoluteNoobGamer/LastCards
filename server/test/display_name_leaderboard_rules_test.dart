import 'package:last_cards/shared/leaderboard/display_name_leaderboard_rules.dart';
import 'package:last_cards_server/trophy_recorder.dart';
import 'package:test/test.dart';

void main() {
  test('modeLeaderboardDisplayNameEligible matches shared rules', () {
    expect(modeLeaderboardDisplayNameEligible('Guest'), isFalse);
    expect(modeLeaderboardDisplayNameEligible('Player'), isFalse);
    expect(modeLeaderboardDisplayNameEligible('Stella'), isTrue);
    expect(isLeaderboardEligibleDisplayName('Stella'), isTrue);
  });
}
