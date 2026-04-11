import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/player_model.dart';

void main() {
  test('PlayerModel roundtrips firebaseUid for online roster payloads', () {
    final p = PlayerModel(
      id: 'player-1',
      displayName: 'A',
      tablePosition: TablePosition.bottom,
      firebaseUid: 'test-uid-abc',
    );
    final json = p.toJson();
    final back = PlayerModel.fromJson(json);
    expect(back.firebaseUid, 'test-uid-abc');
  });
}
