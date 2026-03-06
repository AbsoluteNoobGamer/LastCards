import 'dart:async';

import '../models/game_event.dart';
import 'websocket_client.dart';

/// Sits between [WebSocketClient] and the Riverpod providers.
///
/// Converts raw JSON strings from the server into typed [GameEvent] objects
/// and re-emits them on a broadcast [Stream].
class GameEventHandler {
  GameEventHandler(this._wsClient) {
    _subscription = _wsClient.messages.listen(_onRawMessage);
  }

  final WebSocketClient _wsClient;
  late final StreamSubscription<String> _subscription;

  final _eventController = StreamController<GameEvent>.broadcast();

  /// Typed stream of all server-sent events.
  Stream<GameEvent> get events => _eventController.stream;

  // ── Filters ────────────────────────────────────────────────────────────────

  /// Convenience typed sub-streams.
  Stream<StateSnapshotEvent> get stateSnapshots =>
      events.where((e) => e is StateSnapshotEvent).cast<StateSnapshotEvent>();

  Stream<CardPlayedEvent> get cardPlays =>
      events.where((e) => e is CardPlayedEvent).cast<CardPlayedEvent>();
  Stream<CardDrawnEvent> get cardDraws =>
      events.where((e) => e is CardDrawnEvent).cast<CardDrawnEvent>();
  Stream<TurnChangedEvent> get turnChanges =>
      events.where((e) => e is TurnChangedEvent).cast<TurnChangedEvent>();
  Stream<PenaltyAppliedEvent> get penalties =>
      events.where((e) => e is PenaltyAppliedEvent).cast<PenaltyAppliedEvent>();
  Stream<GameEndedEvent> get gameEnded =>
      events.where((e) => e is GameEndedEvent).cast<GameEndedEvent>();

  // ── Outgoing helpers ───────────────────────────────────────────────────────

  void sendPlayCards(PlayCardsAction action) =>
      _wsClient.send(action.toJsonString());

  void sendDrawCard() => _wsClient.send(const DrawCardAction().toJsonString());

  void sendDeclareJoker(DeclareJokerAction action) =>
      _wsClient.send(action.toJsonString());

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onRawMessage(String raw) {
    final event = parseServerEvent(raw);
    _eventController.add(event);
  }

  void dispose() {
    _subscription.cancel();
    _eventController.close();
  }
}
