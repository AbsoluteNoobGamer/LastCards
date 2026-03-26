import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/game_event.dart';
import 'package:last_cards/core/models/game_state.dart';

void main() {
  test('unknown type returns ErrorEvent', () {
    final event = parseServerEvent(jsonEncode({'type': 'banana'}));
    expect(event, isA<ErrorEvent>());
    expect((event as ErrorEvent).code, 'unknown_event');
  });

  test('invalid JSON returns parse_error', () {
    final event = parseServerEvent('not json');
    expect(event, isA<ErrorEvent>());
    expect((event as ErrorEvent).code, 'parse_error');
  });

  test('error event parses code and message', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'error',
      'code': 'invalid_play',
      'message': 'Not your turn',
    }));
    expect(event, isA<ErrorEvent>());
    final e = event as ErrorEvent;
    expect(e.code, 'invalid_play');
    expect(e.message, 'Not your turn');
  });

  test('turn_changed parses direction counterClockwise', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'turn_changed',
      'currentPlayerId': 'p2',
      'direction': 'counterClockwise',
    }));
    expect(event, isA<TurnChangedEvent>());
    final e = event as TurnChangedEvent;
    expect(e.newCurrentPlayerId, 'p2');
    expect(e.direction, PlayDirection.counterClockwise);
  });

  test('reshuffle parses newDrawPileCount', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'reshuffle',
      'newDrawPileCount': 30,
    }));
    expect(event, isA<ReshuffleEvent>());
    expect((event as ReshuffleEvent).newDrawPileCount, 30);
  });

  test('player_socket_lost parses playerId', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'player_socket_lost',
      'playerId': 'player-1',
    }));
    expect(event, isA<PlayerSocketLostEvent>());
    expect((event as PlayerSocketLostEvent).playerId, 'player-1');
  });

  test('player_socket_restored parses playerId', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'player_socket_restored',
      'playerId': 'player-2',
    }));
    expect(event, isA<PlayerSocketRestoredEvent>());
    expect((event as PlayerSocketRestoredEvent).playerId, 'player-2');
  });

  test('quickplay_queue_update parses roster snapshot', () {
    final event = parseServerEvent(jsonEncode({
      'type': 'quickplay_queue_update',
      'playerCount': 4,
      'displayNames': ['A', 'B'],
      'yourIndex': 1,
    }));
    expect(event, isA<QuickplayQueueUpdateEvent>());
    final e = event as QuickplayQueueUpdateEvent;
    expect(e.playerCount, 4);
    expect(e.displayNames, ['A', 'B']);
    expect(e.yourIndex, 1);
  });
}
