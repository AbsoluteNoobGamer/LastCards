import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:last_cards/core/models/game_event.dart';
import 'package:last_cards/core/network/game_event_handler.dart';

import '../helpers/network_mocks.mocks.dart';

void main() {
  late MockWebSocketClient mockWs;
  late StreamController<String> messageController;
  late GameEventHandler handler;

  setUp(() {
    mockWs = MockWebSocketClient();
    messageController = StreamController<String>.broadcast();
    when(mockWs.messages).thenAnswer((_) => messageController.stream);
    when(mockWs.send(any)).thenReturn(true);
    handler = GameEventHandler(mockWs);
  });

  tearDown(() {
    handler.dispose();
    messageController.close();
  });

  Map<String, dynamic> snapshotPayload() => {
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
      };

  test('state_snapshot emits on stateSnapshots stream only', () async {
    final snapshots = <StateSnapshotEvent>[];
    final cardPlays = <CardPlayedEvent>[];
    final cardDraws = <CardDrawnEvent>[];
    handler.stateSnapshots.listen(snapshots.add);
    handler.cardPlays.listen(cardPlays.add);
    handler.cardDraws.listen(cardDraws.add);

    messageController.add(jsonEncode({
      'type': 'state_snapshot',
      'payload': snapshotPayload(),
    }));
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, hasLength(1));
    expect(cardPlays, isEmpty);
    expect(cardDraws, isEmpty);
  });

  test('card_played emits on cardPlays stream only', () async {
    final snapshots = <StateSnapshotEvent>[];
    final cardPlays = <CardPlayedEvent>[];
    final cardDraws = <CardDrawnEvent>[];
    handler.stateSnapshots.listen(snapshots.add);
    handler.cardPlays.listen(cardPlays.add);
    handler.cardDraws.listen(cardDraws.add);

    messageController.add(jsonEncode({
      'type': 'card_played',
      'playerId': 'p1',
      'cards': [
        {'id': 'c1', 'rank': 'six', 'suit': 'spades'},
      ],
      'newDiscardTop': {'id': 'c1', 'rank': 'six', 'suit': 'spades'},
    }));
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, isEmpty);
    expect(cardPlays, hasLength(1));
    expect(cardDraws, isEmpty);
  });

  test('card_drawn emits on cardDraws stream only', () async {
    final snapshots = <StateSnapshotEvent>[];
    final cardPlays = <CardPlayedEvent>[];
    final cardDraws = <CardDrawnEvent>[];
    handler.stateSnapshots.listen(snapshots.add);
    handler.cardPlays.listen(cardPlays.add);
    handler.cardDraws.listen(cardDraws.add);

    messageController.add(jsonEncode({
      'type': 'card_drawn',
      'playerId': 'p1',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, isEmpty);
    expect(cardPlays, isEmpty);
    expect(cardDraws, hasLength(1));
  });

  test('unknown event type does not emit on typed streams', () async {
    final snapshots = <StateSnapshotEvent>[];
    final cardPlays = <CardPlayedEvent>[];
    final cardDraws = <CardDrawnEvent>[];
    handler.stateSnapshots.listen(snapshots.add);
    handler.cardPlays.listen(cardPlays.add);
    handler.cardDraws.listen(cardDraws.add);

    messageController.add(jsonEncode({'type': 'not_a_real_event'}));
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, isEmpty);
    expect(cardPlays, isEmpty);
    expect(cardDraws, isEmpty);
  });

  test('sendPlayCards() sends play_cards payload with card IDs', () {
    handler.sendPlayCards(const PlayCardsAction(cardIds: ['c1', 'c2']));

    final captured = verify(mockWs.send(captureAny)).captured.single as String;
    final decoded = jsonDecode(captured) as Map<String, dynamic>;
    expect(decoded['type'], 'play_cards');
    expect(decoded['cardIds'], ['c1', 'c2']);
  });

  test('sendDrawCard() sends draw_card payload', () {
    handler.sendDrawCard();

    final captured = verify(mockWs.send(captureAny)).captured.single as String;
    final decoded = jsonDecode(captured) as Map<String, dynamic>;
    expect(decoded['type'], 'draw_card');
  });

  test('sendEndTurn() sends end_turn payload', () {
    handler.sendEndTurn();

    final captured = verify(mockWs.send(captureAny)).captured.single as String;
    final decoded = jsonDecode(captured) as Map<String, dynamic>;
    expect(decoded['type'], 'end_turn');
  });
}
