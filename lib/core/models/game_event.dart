import 'dart:convert';

import 'card_model.dart';
import 'game_state.dart';
import 'player_model.dart';

/// All WebSocket event types exchanged between client and server.
///
/// Incoming (server → client): [StateSnapshotEvent], [CardPlayedEvent],
///   [CardDrawnEvent], [TurnChangedEvent], [PenaltyAppliedEvent],
///   [PlayerJoinedEvent], [PlayerLeftEvent], [GameEndedEvent], [ErrorEvent]
///
/// Outgoing (client → server): [PlayCardsAction], [DrawCardAction],
///   [DeclareJokerAction], [DeclareSuitAction]
sealed class GameEvent {
  const GameEvent();

  String get type;
}

// ── Incoming events ───────────────────────────────────────────────────────────

/// Full state snapshot — sent on connect/reconnect and after each action.
final class StateSnapshotEvent extends GameEvent {
  final GameState gameState;
  const StateSnapshotEvent(this.gameState);

  @override
  String get type => 'state_snapshot';
}

/// A card (or stack of same-rank cards) was played.
final class CardPlayedEvent extends GameEvent {
  final String playerId;
  final List<CardModel> cards;
  final CardModel newDiscardTop;
  const CardPlayedEvent({
    required this.playerId,
    required this.cards,
    required this.newDiscardTop,
  });

  @override
  String get type => 'card_played';
}

/// A card was drawn from the draw pile.
final class CardDrawnEvent extends GameEvent {
  final String playerId;

  /// Only populated when the drawing player is the local player.
  final CardModel? drawnCard;
  const CardDrawnEvent({required this.playerId, this.drawnCard});

  @override
  String get type => 'card_drawn';
}

/// Turn has moved to the next player.
final class TurnChangedEvent extends GameEvent {
  final String newCurrentPlayerId;
  final PlayDirection direction;
  const TurnChangedEvent({
    required this.newCurrentPlayerId,
    required this.direction,
  });

  @override
  String get type => 'turn_changed';
}

/// A draw penalty was applied to a player.
final class PenaltyAppliedEvent extends GameEvent {
  final String targetPlayerId;
  final int cardsDrawn;
  final int newPenaltyStack;
  const PenaltyAppliedEvent({
    required this.targetPlayerId,
    required this.cardsDrawn,
    required this.newPenaltyStack,
  });

  @override
  String get type => 'penalty_applied';
}

/// A player joined the session.
final class PlayerJoinedEvent extends GameEvent {
  final PlayerModel player;
  const PlayerJoinedEvent(this.player);

  @override
  String get type => 'player_joined';
}

/// A player disconnected.
final class PlayerLeftEvent extends GameEvent {
  final String playerId;
  const PlayerLeftEvent(this.playerId);

  @override
  String get type => 'player_left';
}

/// Game has concluded.
final class GameEndedEvent extends GameEvent {
  final String winnerId;
  const GameEndedEvent(this.winnerId);

  @override
  String get type => 'game_ended';
}

/// Server rejected an action — display error to the acting player.
final class ErrorEvent extends GameEvent {
  final String code;
  final String message;
  const ErrorEvent({required this.code, required this.message});

  @override
  String get type => 'error';
}

// ── Outgoing actions (client → server) ───────────────────────────────────────

/// Play one or more cards (same-rank stack allowed).
final class PlayCardsAction extends GameEvent {
  final List<String> cardIds;

  /// Required when an Ace is played — the new suit to lock.
  final Suit? declaredSuit;
  const PlayCardsAction({required this.cardIds, this.declaredSuit});

  @override
  String get type => 'play_cards';

  Map<String, dynamic> toJson() => {
        'type': type,
        'cardIds': cardIds,
        if (declaredSuit != null) 'declaredSuit': declaredSuit!.name,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Draw a card from the draw pile.
final class DrawCardAction extends GameEvent {
  const DrawCardAction();

  @override
  String get type => 'draw_card';

  String toJsonString() => jsonEncode({'type': type});
}

/// Declare a Joker's suit and rank.
final class DeclareJokerAction extends GameEvent {
  final String jokerCardId;
  final Suit declaredSuit;
  final Rank declaredRank;
  const DeclareJokerAction({
    required this.jokerCardId,
    required this.declaredSuit,
    required this.declaredRank,
  });

  @override
  String get type => 'declare_joker';

  String toJsonString() => jsonEncode({
        'type': type,
        'jokerCardId': jokerCardId,
        'declaredSuit': declaredSuit.name,
        'declaredRank': declaredRank.name,
      });
}

// ── Event parsing ─────────────────────────────────────────────────────────────

/// Parse a raw JSON string from the server into a [GameEvent].
/// Returns [ErrorEvent] if the payload is malformed.
GameEvent parseServerEvent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final type = json['type'] as String? ?? '';

    return switch (type) {
      'state_snapshot' => StateSnapshotEvent(
          GameState.fromJson(json['payload'] as Map<String, dynamic>),
        ),
      'card_played' => CardPlayedEvent(
          playerId: json['playerId'] as String,
          cards: (json['cards'] as List)
              .map((c) => CardModel.fromJson(c as Map<String, dynamic>))
              .toList(),
          newDiscardTop: CardModel.fromJson(
            json['newDiscardTop'] as Map<String, dynamic>,
          ),
        ),
      'card_drawn' => CardDrawnEvent(
          playerId: json['playerId'] as String,
          drawnCard: json['card'] != null
              ? CardModel.fromJson(json['card'] as Map<String, dynamic>)
              : null,
        ),
      'turn_changed' => TurnChangedEvent(
          newCurrentPlayerId: json['currentPlayerId'] as String,
          direction: PlayDirection.values.byName(
            json['direction'] as String,
          ),
        ),
      'penalty_applied' => PenaltyAppliedEvent(
          targetPlayerId: json['targetPlayerId'] as String,
          cardsDrawn: json['cardsDrawn'] as int,
          newPenaltyStack: json['newPenaltyStack'] as int,
        ),
      'player_joined' => PlayerJoinedEvent(
          PlayerModel.fromJson(json['player'] as Map<String, dynamic>),
        ),
      'player_left' => PlayerLeftEvent(json['playerId'] as String),
      'game_ended' => GameEndedEvent(json['winnerId'] as String),
      'error' => ErrorEvent(
          code: json['code'] as String? ?? 'unknown',
          message: json['message'] as String? ?? 'An error occurred.',
        ),
      _ => ErrorEvent(code: 'unknown_event', message: 'Unknown event: $type'),
    };
  } catch (e) {
    return ErrorEvent(
      code: 'parse_error',
      message: 'Failed to parse server message: $e',
    );
  }
}
