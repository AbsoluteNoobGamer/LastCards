import 'dart:convert';

import 'card_model.dart';
import 'game_state.dart';
import 'player_model.dart';

/// All WebSocket event types exchanged between client and server.
///
/// Incoming (server → client): [StateSnapshotEvent], [CardPlayedEvent],
///   [CardDrawnEvent], [TurnChangedEvent], [PenaltyAppliedEvent],
///   [PlayerJoinedEvent], [PlayerLeftEvent], [GameEndedEvent], [ErrorEvent],
///   [SuitChoiceRequiredEvent], [JokerChoiceRequiredEvent],
///   [TurnTimeoutEvent], [ReshuffleEvent], [BustRoundOverEvent],
///   [BustRoundStartEvent], [QuickChatEvent]
///
/// Outgoing (client → server): [PlayCardsAction], [DrawCardAction],
///   [DeclareJokerAction], [SuitChoiceAction], [EndTurnAction], [QuickChatAction]
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

  /// Skip stack before this play (for online skip sound / UI).
  final int? activeSkipCountBefore;

  /// Skip stack after this play.
  final int? activeSkipCountAfter;

  /// Display names of players skipped by this play (Eight skip), if any.
  final List<String> skippedPlayers;

  /// True while the same player may continue this turn (stack more cards).
  final bool turnContinues;

  /// True if play direction flipped vs before this play (e.g. King).
  final bool directionReversed;

  const CardPlayedEvent({
    required this.playerId,
    required this.cards,
    required this.newDiscardTop,
    this.activeSkipCountBefore,
    this.activeSkipCountAfter,
    this.skippedPlayers = const [],
    this.turnContinues = true,
    this.directionReversed = false,
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

/// Player drew cards as penalty for attempting an invalid play.
final class InvalidPlayPenaltyEvent extends GameEvent {
  final String playerId;
  final int drawCount;
  const InvalidPlayPenaltyEvent({
    required this.playerId,
    this.drawCount = 2,
  });

  @override
  String get type => 'invalid_play_penalty';
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

  /// Per-player rating deltas for ranked games.
  ///
  /// Key is the server-side player ID; value is the rating change (+25/-15).
  /// Null when the game was not a ranked match.
  final Map<String, int>? ratingChanges;

  const GameEndedEvent(this.winnerId, {this.ratingChanges});

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

/// Room was created; server sends the room code and creator's player ID.
final class RoomCreatedEvent extends GameEvent {
  final String roomCode;
  final String playerId;
  const RoomCreatedEvent(this.roomCode, {this.playerId = ''});

  @override
  String get type => 'room_created';
}

/// Room was joined; server sends the room code and joiner's player ID.
final class RoomJoinedEvent extends GameEvent {
  final String roomCode;
  final String playerId;
  const RoomJoinedEvent(this.roomCode, this.playerId);

  @override
  String get type => 'room_joined';
}

/// A player marked themselves ready in the lobby.
final class PlayerReadyEvent extends GameEvent {
  final String playerId;
  const PlayerReadyEvent(this.playerId);

  @override
  String get type => 'player_ready';
}

/// Server requires the local player to choose a suit after playing an Ace.
///
/// The client should show a suit picker and respond with [SuitChoiceAction].
final class SuitChoiceRequiredEvent extends GameEvent {
  /// The card ID of the Ace that triggered this choice.
  final String cardId;
  const SuitChoiceRequiredEvent({required this.cardId});

  @override
  String get type => 'suit_choice_required';
}

/// Server requires the local player to declare a suit and rank for a Joker.
///
/// The client should show a joker picker and respond with [DeclareJokerAction].
final class JokerChoiceRequiredEvent extends GameEvent {
  /// The card ID of the Joker that triggered this choice.
  final String jokerCardId;
  const JokerChoiceRequiredEvent({required this.jokerCardId});

  @override
  String get type => 'joker_choice_required';
}

/// Server forced a draw and ended the current player's turn due to a timeout.
final class TurnTimeoutEvent extends GameEvent {
  /// The player whose turn timed out.
  final String playerId;

  /// Number of cards drawn as a timeout penalty (may be 0).
  final int cardsDrawn;
  const TurnTimeoutEvent({required this.playerId, required this.cardsDrawn});

  @override
  String get type => 'turn_timeout';
}

/// Server reshuffled the discard pile back into the draw pile.
final class ReshuffleEvent extends GameEvent {
  /// New draw pile size after reshuffle.
  final int newDrawPileCount;
  const ReshuffleEvent({required this.newDrawPileCount});

  @override
  String get type => 'reshuffle';
}

/// Session configuration broadcast (sent when game starts).
/// Contains whether the match is ranked, private, trophy-eligible, etc.
final class SessionConfigEvent extends GameEvent {
  final bool isPrivate;
  final bool isRanked;
  final bool trophyEligible;
  const SessionConfigEvent({
    this.isPrivate = false,
    this.isRanked = false,
    this.trophyEligible = false,
  });

  @override
  String get type => 'session_config';
}

/// Bust mode: a round has ended — contains standings, eliminations, and
/// whether the entire Bust game is over.
final class BustRoundOverEvent extends GameEvent {
  final int roundNumber;
  final List<Map<String, dynamic>> standings;
  final List<String> eliminatedThisRound;
  final List<String> survivorIds;
  final bool isGameOver;
  final String? winnerId;
  const BustRoundOverEvent({
    required this.roundNumber,
    required this.standings,
    required this.eliminatedThisRound,
    required this.survivorIds,
    required this.isGameOver,
    this.winnerId,
  });

  @override
  String get type => 'bust_round_over';
}

/// Bust mode: a new round is starting.
final class BustRoundStartEvent extends GameEvent {
  final int roundNumber;
  const BustRoundStartEvent({required this.roundNumber});

  @override
  String get type => 'bust_round_start';
}

/// A player sent a quick chat message.
final class QuickChatEvent extends GameEvent {
  final String playerId;
  final int messageIndex;
  const QuickChatEvent({required this.playerId, required this.messageIndex});

  @override
  String get type => 'quick_chat';
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

/// End the current turn and pass to the next player.
final class EndTurnAction extends GameEvent {
  const EndTurnAction();

  @override
  String get type => 'end_turn';

  String toJsonString() => jsonEncode({'type': type});
}

/// Respond to a [SuitChoiceRequiredEvent] — declare which suit the Ace locks.
final class SuitChoiceAction extends GameEvent {
  final Suit suit;
  const SuitChoiceAction({required this.suit});

  @override
  String get type => 'suit_choice';

  String toJsonString() => jsonEncode({'type': type, 'suit': suit.name});
}

/// Send a quick chat message to all players.
final class QuickChatAction extends GameEvent {
  final int messageIndex;
  const QuickChatAction({required this.messageIndex});

  @override
  String get type => 'quick_chat';

  String toJsonString() => jsonEncode({'type': type, 'messageIndex': messageIndex});
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
          activeSkipCountBefore:
              (json['activeSkipCountBefore'] as num?)?.toInt(),
          activeSkipCountAfter: (json['activeSkipCountAfter'] as num?)?.toInt(),
          skippedPlayers: (json['skippedPlayers'] as List?)
                  ?.map((e) => e as String)
                  .toList() ??
              const [],
          turnContinues: json['turnContinues'] as bool? ?? true,
          directionReversed: json['directionReversed'] as bool? ?? false,
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
      'invalid_play_penalty' => InvalidPlayPenaltyEvent(
          playerId: json['playerId'] as String? ?? '',
          drawCount: (json['drawCount'] as num?)?.toInt() ?? 2,
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
      'game_ended' => GameEndedEvent(
          json['winnerId'] as String,
          ratingChanges: (json['ratingChanges'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())),
        ),
      'bust_game_ended' => GameEndedEvent(
          json['winnerId'] as String,
          ratingChanges: (json['ratingChanges'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())),
        ),
      'bust_round_over' => BustRoundOverEvent(
          roundNumber: json['roundNumber'] as int? ?? 0,
          standings: (json['standings'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
          eliminatedThisRound: (json['eliminatedThisRound'] as List?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
          survivorIds: (json['survivorIds'] as List?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
          isGameOver: json['isGameOver'] as bool? ?? false,
          winnerId: json['winnerId'] as String?,
        ),
      'bust_round_start' => BustRoundStartEvent(
          roundNumber: json['roundNumber'] as int? ?? 0,
        ),
      'room_created' => RoomCreatedEvent(
          json['roomCode'] as String? ?? '',
          playerId: json['playerId'] as String? ?? ''),
      'room_joined' => RoomJoinedEvent(
          json['roomCode'] as String? ?? '',
          json['playerId'] as String? ?? ''),
      'player_ready' => PlayerReadyEvent(
          json['playerId'] as String? ?? ''),
      'suit_choice_required' => SuitChoiceRequiredEvent(
          cardId: json['cardId'] as String? ?? '',
        ),
      'joker_choice_required' => JokerChoiceRequiredEvent(
          jokerCardId: json['jokerCardId'] as String? ?? '',
        ),
      'turn_timeout' => TurnTimeoutEvent(
          playerId: json['playerId'] as String? ?? '',
          cardsDrawn: json['cardsDrawn'] as int? ?? 0,
        ),
      'reshuffle' => ReshuffleEvent(
          newDrawPileCount: json['newDrawPileCount'] as int? ?? 0,
        ),
      'session_config' => SessionConfigEvent(
          isPrivate: json['isPrivate'] as bool? ?? false,
          isRanked: json['isRanked'] as bool? ?? false,
          trophyEligible: json['trophyEligible'] as bool? ?? false,
        ),
      'quick_chat' => QuickChatEvent(
          playerId: json['playerId'] as String? ?? '',
          messageIndex: json['messageIndex'] as int? ?? 0,
        ),
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
