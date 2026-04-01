import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
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

  test('parses card_drawn into CardDrawnEvent on cardDraws stream', () async {
    final future = handler.cardDraws.first;
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'card_drawn',
      'playerId': 'p1',
    }));
    final event = await future;
    expect(event.playerId, 'p1');
  });

  test('cardDraws filter does not emit state_snapshot', () async {
    final draws = <CardDrawnEvent>[];
    handler.cardDraws.listen(draws.add);
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': {
        'sessionId': 's',
        'phase': 'playing',
        'players': [],
        'currentPlayerId': 'p1',
        'direction': 'clockwise',
      },
    }));
    await Future<void>.delayed(Duration.zero);
    expect(draws, isEmpty);
  });

  test('parses turn_changed for turnChanges stream', () async {
    final future = handler.turnChanges.first;
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'turn_changed',
      'currentPlayerId': 'p2',
      'direction': 'counterClockwise',
    }));
    final event = await future;
    expect(event.newCurrentPlayerId, 'p2');
    expect(event.direction.name, 'counterClockwise');
  });

  test('parses penalty_applied for penalties stream', () async {
    final future = handler.penalties.first;
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'penalty_applied',
      'targetPlayerId': 'p1',
      'cardsDrawn': 2,
      'newPenaltyStack': 4,
    }));
    final event = await future;
    expect(event.newPenaltyStack, 4);
  });

  test('stateSnapshots emits only for state_snapshot type', () async {
    final future = handler.stateSnapshots.first;
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': {
        'sessionId': 's',
        'phase': 'playing',
        'players': [
          {
            'id': 'p1',
            'displayName': 'A',
            'tablePosition': 'bottom',
            'hand': [],
            'cardCount': 0,
          },
        ],
        'currentPlayerId': 'p1',
        'direction': 'clockwise',
      },
    }));
    final e = await future;
    expect(e.gameState.sessionId, 's');
  });

  test('sendDrawCard sends draw_card action', () {
    handler.sendDrawCard();
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'draw_card');
  });

  test('sendDeclareJoker sends declare_joker payload', () {
    handler.sendDeclareJoker(
      const DeclareJokerAction(
        jokerCardId: 'j1',
        declaredSuit: Suit.hearts,
        declaredRank: Rank.ace,
      ),
    );
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'declare_joker');
    expect(decoded['jokerCardId'], 'j1');
    expect(decoded['declaredSuit'], 'hearts');
    expect(decoded['declaredRank'], 'ace');
  });
}
