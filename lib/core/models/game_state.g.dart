// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GameStateImpl _$$GameStateImplFromJson(Map<String, dynamic> json) =>
    _$GameStateImpl(
      sessionId: json['sessionId'] as String,
      phase: $enumDecode(_$GamePhaseEnumMap, json['phase']),
      players: (json['players'] as List<dynamic>)
          .map((e) => PlayerModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPlayerId: json['currentPlayerId'] as String,
      direction: $enumDecode(_$PlayDirectionEnumMap, json['direction']),
      discardTopCard: json['discardTopCard'] == null
          ? null
          : CardModel.fromJson(json['discardTopCard'] as Map<String, dynamic>),
      discardPileHistory: (json['discardPileHistory'] as List<dynamic>?)
              ?.map((e) => CardModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      drawPileCount: (json['drawPileCount'] as num?)?.toInt() ?? 0,
      activePenaltyCount: (json['activePenaltyCount'] as num?)?.toInt() ?? 0,
      penaltyChainLive: json['penaltyChainLive'] as bool? ?? false,
      activeSkipCount: (json['activeSkipCount'] as num?)?.toInt() ?? 0,
      suitLock: $enumDecodeNullable(_$SuitEnumMap, json['suitLock']),
      preTurnCentreSuit:
          $enumDecodeNullable(_$SuitEnumMap, json['preTurnCentreSuit']),
      queenSuitLock: $enumDecodeNullable(_$SuitEnumMap, json['queenSuitLock']),
      winnerId: json['winnerId'] as String?,
      actionsThisTurn: (json['actionsThisTurn'] as num?)?.toInt() ?? 0,
      cardsPlayedThisTurn: (json['cardsPlayedThisTurn'] as num?)?.toInt() ?? 0,
      lastPlayedThisTurn: json['lastPlayedThisTurn'] == null
          ? null
          : CardModel.fromJson(
              json['lastPlayedThisTurn'] as Map<String, dynamic>),
      pendingJokerResolution: json['pendingJokerResolution'] as bool? ?? false,
      lastCardsDeclaredBy: json['lastCardsDeclaredBy'] == null
          ? const {}
          : _stringSetFromJson(json['lastCardsDeclaredBy']),
      isHardcore: json['isHardcore'] as bool? ?? false,
    );

Map<String, dynamic> _$$GameStateImplToJson(_$GameStateImpl instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'phase': _$GamePhaseEnumMap[instance.phase]!,
      'players': instance.players,
      'currentPlayerId': instance.currentPlayerId,
      'direction': _$PlayDirectionEnumMap[instance.direction]!,
      'discardTopCard': instance.discardTopCard,
      'discardPileHistory': instance.discardPileHistory,
      'drawPileCount': instance.drawPileCount,
      'activePenaltyCount': instance.activePenaltyCount,
      'penaltyChainLive': instance.penaltyChainLive,
      'activeSkipCount': instance.activeSkipCount,
      'suitLock': _$SuitEnumMap[instance.suitLock],
      'preTurnCentreSuit': _$SuitEnumMap[instance.preTurnCentreSuit],
      'queenSuitLock': _$SuitEnumMap[instance.queenSuitLock],
      'winnerId': instance.winnerId,
      'actionsThisTurn': instance.actionsThisTurn,
      'cardsPlayedThisTurn': instance.cardsPlayedThisTurn,
      'lastPlayedThisTurn': instance.lastPlayedThisTurn,
      'pendingJokerResolution': instance.pendingJokerResolution,
      'lastCardsDeclaredBy': _stringSetToJson(instance.lastCardsDeclaredBy),
      'isHardcore': instance.isHardcore,
    };

const _$GamePhaseEnumMap = {
  GamePhase.lobby: 'lobby',
  GamePhase.playing: 'playing',
  GamePhase.ended: 'ended',
};

const _$PlayDirectionEnumMap = {
  PlayDirection.clockwise: 'clockwise',
  PlayDirection.counterClockwise: 'counterClockwise',
};

const _$SuitEnumMap = {
  Suit.spades: 'spades',
  Suit.clubs: 'clubs',
  Suit.hearts: 'hearts',
  Suit.diamonds: 'diamonds',
};
