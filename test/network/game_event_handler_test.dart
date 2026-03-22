import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/game_event.dart';
import 'package:last_cards/core/network/game_event_handler.dart';

import '../helpers/fake_websocket_client.dart';

void main() {
  late FakeWebSocketClient fakeWs;
  late GameEventHandler handler;

  setUp(() {
    fakeWs = FakeWebSocketClient();
    handler = GameEventHandler(fakeWs);
  });

  tearDown(() async {
    handler.dispose();
    await fakeWs.dispose();
  });

  test('parses card_played JSON into CardPlayedEvent', () async {
    final future = handler.cardPlays.first;
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'card_played',
      'playerId': 'p1',
      'cards': [
        {'id': 'c1', 'rank': 'six', 'suit': 'spades'}
      ],
      'newDiscardTop': {'id': 'c1', 'rank': 'six', 'suit': 'spades'},
    }));
    final event = await future;
    expect(event.playerId, 'p1');
    expect(event.cards.length, 1);
  });

  test('stateSnapshots filter only emits StateSnapshotEvent', () async {
    final snapshotEvents = <StateSnapshotEvent>[];
    final cardEvents = <CardPlayedEvent>[];
    handler.stateSnapshots.listen(snapshotEvents.add);
    handler.cardPlays.listen(cardEvents.add);

    fakeWs.injectServerMessage(jsonEncode({
      'type': 'card_played',
      'playerId': 'p1',
      'cards': [
        {'id': 'c1', 'rank': 'six', 'suit': 'spades'}
      ],
      'newDiscardTop': {'id': 'c1', 'rank': 'six', 'suit': 'spades'},
    }));

    await Future<void>.delayed(Duration.zero);
    expect(snapshotEvents, isEmpty);
    expect(cardEvents, hasLength(1));
  });

  test('malformed JSON emits ErrorEvent with parse_error code', () async {
    final future = handler.errors.first;
    fakeWs.injectServerMessage('not valid json');
    final event = await future;
    expect(event.code, 'parse_error');
  });

  test('sendPlayCards sends correct JSON to WebSocket', () {
    handler.sendPlayCards(const PlayCardsAction(cardIds: ['c1', 'c2']));
    expect(fakeWs.sentMessages, hasLength(1));
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'play_cards');
    expect(decoded['cardIds'], ['c1', 'c2']);
  });

  test('sendEndTurn sends end_turn action', () {
    handler.sendEndTurn();
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'end_turn');
  });
}
