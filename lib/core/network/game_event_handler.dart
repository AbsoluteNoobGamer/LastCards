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

  Stream<RoomCreatedEvent> get roomCreated =>
      events.where((e) => e is RoomCreatedEvent).cast<RoomCreatedEvent>();

  /// Server requires the local player to pick a suit after an Ace play.
  Stream<SuitChoiceRequiredEvent> get suitChoiceRequired => events
      .where((e) => e is SuitChoiceRequiredEvent)
      .cast<SuitChoiceRequiredEvent>();

  /// Server requires the local player to declare a Joker's identity.
  Stream<JokerChoiceRequiredEvent> get jokerChoiceRequired => events
      .where((e) => e is JokerChoiceRequiredEvent)
      .cast<JokerChoiceRequiredEvent>();

  /// Server forced a draw and ended the turn due to inactivity timeout.
  Stream<TurnTimeoutEvent> get turnTimeouts =>
      events.where((e) => e is TurnTimeoutEvent).cast<TurnTimeoutEvent>();

  /// Server reshuffled the discard pile back into the draw pile.
  Stream<ReshuffleEvent> get reshuffles =>
      events.where((e) => e is ReshuffleEvent).cast<ReshuffleEvent>();

  /// Session config broadcast (isPrivate, isRanked, trophyEligible).
  Stream<SessionConfigEvent> get sessionConfigs =>
      events.where((e) => e is SessionConfigEvent).cast<SessionConfigEvent>();

  /// Server rejected an action (invalid_play, invalid_end_turn, etc.).
  Stream<ErrorEvent> get errors =>
      events.where((e) => e is ErrorEvent).cast<ErrorEvent>();

  /// Quick chat messages from any player.
  Stream<QuickChatEvent> get quickChats =>
      events.where((e) => e is QuickChatEvent).cast<QuickChatEvent>();

  /// Player drew cards for attempting an invalid play (consolidated log entry).
  Stream<InvalidPlayPenaltyEvent> get invalidPlayPenalties =>
      events
          .where((e) => e is InvalidPlayPenaltyEvent)
          .cast<InvalidPlayPenaltyEvent>();

  Stream<LastCardsPressedEvent> get lastCardsPressed =>
      events.where((e) => e is LastCardsPressedEvent).cast<LastCardsPressedEvent>();

  Stream<LastCardsBluffEvent> get lastCardsBluffs =>
      events.where((e) => e is LastCardsBluffEvent).cast<LastCardsBluffEvent>();

  // ── Outgoing helpers ───────────────────────────────────────────────────────

  bool sendPlayCards(PlayCardsAction action) =>
      _wsClient.send(action.toJsonString());

  bool sendDrawCard() =>
      _wsClient.send(const DrawCardAction().toJsonString());

  bool sendDeclareJoker(DeclareJokerAction action) =>
      _wsClient.send(action.toJsonString());

  bool sendEndTurn() => _wsClient.send(const EndTurnAction().toJsonString());

  bool sendDeclareLastCards() =>
      _wsClient.send(const DeclareLastCardsAction().toJsonString());

  bool sendSuitChoice(SuitChoiceAction action) =>
      _wsClient.send(action.toJsonString());

  bool sendQuickChat(QuickChatAction action) =>
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
