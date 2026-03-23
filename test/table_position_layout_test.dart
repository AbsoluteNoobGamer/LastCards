import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/models/table_position_layout.dart';

void main() {
  test('tablePositionForSeatIndex matches server roster order', () {
    expect(tablePositionForSeatIndex(0), TablePosition.bottom);
    expect(tablePositionForSeatIndex(1), TablePosition.left);
    expect(tablePositionForSeatIndex(2), TablePosition.top);
    expect(tablePositionForSeatIndex(3), TablePosition.right);
    expect(tablePositionForSeatIndex(4), TablePosition.bottomLeft);
    expect(tablePositionForSeatIndex(5), TablePosition.topLeft);
    expect(tablePositionForSeatIndex(6), TablePosition.topRight);
    expect(tablePositionForSeatIndex(7), TablePosition.bottomRight);
    expect(tablePositionForSeatIndex(8), TablePosition.farLeft);
    expect(tablePositionForSeatIndex(9), TablePosition.farRight);
    expect(tablePositionForSeatIndex(10), TablePosition.left);
  });

  test('kOpponentTablePositionCycle length is nine', () {
    expect(kOpponentTablePositionCycle.length, 9);
  });
}
