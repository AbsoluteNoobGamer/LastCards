import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards_server/session_match_stats.dart';
import 'package:test/test.dart';

void main() {
  test('tracks plays, draws, and specials', () {
    final stats = SessionMatchStats();
    stats.recordCardsPlayed('p1', [
      CardModel(id: '1', rank: Rank.two, suit: Suit.hearts),
      CardModel(id: '2', rank: Rank.five, suit: Suit.clubs),
    ]);
    stats.recordDraw('p1', 4, isPenalty: true);
    stats.recordStackBlock('p2');

    final json = stats.toJsonByPlayerId(displayNames: {'p1': 'Alice', 'p2': 'Bob'});
    expect(json['p1']!['cardsPlayed'], 2);
    expect(json['p1']!['specialsPlayed'], 1);
    expect(json['p1']!['penaltyCardsDrawn'], 4);
    expect(json['p2']!['stackBlocks'], 1);
  });
}
