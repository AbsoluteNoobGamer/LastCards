import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/network/game_event_handler.dart';
import 'package:last_cards/core/providers/game_provider.dart';
import 'package:last_cards/core/providers/online_rejoin_provider.dart';

import '../helpers/fake_websocket_client.dart';
import '../helpers/mock_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebSocketClient fakeWs;
  late GameEventHandler handler;
  late GameNotifier notifier;

  GameState makeGameState({String currentPlayerId = 'p1', int drawPileCount = 20}) {
    final p1 = PlayerModel(
      id: 'p1',
      displayName: 'P1',
      tablePosition: TablePosition.bottom,
      hand: const [],
    );
    final p2 = PlayerModel(
      id: 'p2',
      displayName: 'P2',
      tablePosition: TablePosition.top,
      hand: const [],
    );
    return GameState(
      sessionId: 'test',
      phase: GamePhase.playing,
      players: [p1, p2],
      currentPlayerId: currentPlayerId,
      direction: PlayDirection.clockwise,
      discardTopCard: CardModel(id: 'c1', rank: Rank.six, suit: Suit.spades),
      drawPileCount: drawPileCount,
    );
  }

  Future<void> flushEvents() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    mockAudioChannels();
    fakeWs = FakeWebSocketClient();
    handler = GameEventHandler(fakeWs);
    notifier = GameNotifier(handler, OnlineRejoinNotifier());
  });

  tearDown(() async {
    notifier.dispose();
    handler.dispose();
    await fakeWs.dispose();
  });

  test('initial state has null gameState', () {
    expect(notifier.state.gameState, isNull);
  });

  test('state_snapshot replaces full game state', () async {
    final gs = makeGameState();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();
    expect(notifier.state.gameState, isNotNull);
    expect(notifier.state.gameState!.sessionId, 'test');
  });

  test('card_drawn decrements drawPileCount', () async {
    final gs = makeGameState();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();
    final before = notifier.state.gameState!.drawPileCount;

    fakeWs.injectServerMessage(jsonEncode({
      'type': 'card_drawn',
      'playerId': 'p1',
    }));
    await flushEvents();
    expect(notifier.state.gameState!.drawPileCount, before - 1);
  });

  test('drawPileCount clamps to zero', () async {
    final gs = makeGameState(drawPileCount: 0);
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();

    fakeWs.injectServerMessage(jsonEncode({
      'type': 'card_drawn',
      'playerId': 'p1',
    }));
    await flushEvents();
    expect(notifier.state.gameState!.drawPileCount, 0);
  });

  test('suit_choice_required sets pendingSuitChoice', () async {
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': makeGameState().toJson(),
    }));
    await flushEvents();

    fakeWs.injectServerMessage(jsonEncode({
      'type': 'suit_choice_required',
      'cardId': 'ace_hearts',
    }));
    await flushEvents();
    expect(notifier.state.pendingSuitChoice, isTrue);
    expect(notifier.state.pendingSuitChoiceCardId, 'ace_hearts');
  });

  test('playCards sends PlayCardsAction through handler', () {
    notifier.playCards(['c1', 'c2']);
    expect(fakeWs.sentMessages, hasLength(1));
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'play_cards');
    expect(decoded['cardIds'], ['c1', 'c2']);
  });

  test('game_ended sets phase and winnerId', () async {
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': makeGameState().toJson(),
    }));
    await flushEvents();

    fakeWs.injectServerMessage(jsonEncode({
      'type': 'game_ended',
      'winnerId': 'p1',
    }));
    await flushEvents();
    expect(notifier.state.gameState!.phase, GamePhase.ended);
    expect(notifier.state.gameState!.winnerId, 'p1');
  });
}
