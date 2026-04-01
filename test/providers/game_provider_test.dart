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

class _SendFailingFake extends FakeWebSocketClient {
  @override
  bool send(String jsonPayload) => false;
}

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

  test('turn_changed updates currentPlayerId and resets per-turn counters', () async {
    final gs = makeGameState();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'turn_changed',
      'currentPlayerId': 'p2',
      'direction': 'counterClockwise',
    }));
    await flushEvents();
    expect(notifier.state.gameState!.currentPlayerId, 'p2');
    expect(notifier.state.gameState!.direction, PlayDirection.counterClockwise);
    expect(notifier.state.gameState!.actionsThisTurn, 0);
  });

  test('penalty_applied updates activePenaltyCount', () async {
    final gs = makeGameState();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'penalty_applied',
      'targetPlayerId': 'p1',
      'cardsDrawn': 2,
      'newPenaltyStack': 6,
    }));
    await flushEvents();
    expect(notifier.state.gameState!.activePenaltyCount, 6);
  });

  test('drawCard sets lastError when WebSocket send fails', () async {
    final failingWs = _SendFailingFake();
    final h = GameEventHandler(failingWs);
    final n = GameNotifier(h, OnlineRejoinNotifier());
    addTearDown(() async {
      n.dispose();
      h.dispose();
      await failingWs.dispose();
    });
    n.drawCard();
    await flushEvents();
    expect(n.state.lastError, isNotNull);
  });

  test('declareJoker sends payload and clears pending joker flag', () async {
    final gs = makeGameState();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'state_snapshot',
      'payload': gs.toJson(),
    }));
    await flushEvents();
    fakeWs.injectServerMessage(jsonEncode({
      'type': 'joker_choice_required',
      'jokerCardId': 'joker1',
    }));
    await flushEvents();
    expect(notifier.state.pendingJokerResolution, isTrue);

    notifier.declareJoker(
      jokerCardId: 'joker1',
      suitName: 'hearts',
      rankName: 'ace',
    );
    expect(notifier.state.pendingJokerResolution, isFalse);
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'declare_joker');
  });

  test('endTurn sends end_turn through handler', () {
    notifier.endTurn();
    expect(fakeWs.sentMessages, hasLength(1));
    final decoded = jsonDecode(fakeWs.sentMessages.first) as Map<String, dynamic>;
    expect(decoded['type'], 'end_turn');
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
