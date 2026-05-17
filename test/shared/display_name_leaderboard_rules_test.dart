import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/leaderboard/display_name_leaderboard_rules.dart';

void main() {
  test('default names are not leaderboard eligible', () {
    expect(isLeaderboardEligibleDisplayName('Guest'), isFalse);
    expect(isLeaderboardEligibleDisplayName('Player'), isFalse);
    expect(isLeaderboardEligibleDisplayName('player 2'), isFalse);
    expect(isLeaderboardEligibleDisplayName('Alice'), isTrue);
  });

  test('filter drops guest and duplicate names', () {
    final entries = [
      (name: 'Guest', id: '1'),
      (name: 'Alice', id: '2'),
      (name: 'alice', id: '3'),
      (name: 'Bob', id: '4'),
    ];
    final filtered = filterLeaderboardEntriesForDisplay(
      entries,
      (e) => e.name,
    );
    expect(filtered.map((e) => e.id).toList(), ['2', '4']);
  });
}
