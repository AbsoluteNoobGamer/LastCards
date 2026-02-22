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
      discardSecondCard: json['discardSecondCard'] == null
          ? null
          : CardModel.fromJson(
              json['discardSecondCard'] as Map<String, dynamic>),
      drawPileCount: (json['drawPileCount'] as num?)?.toInt() ?? 0,
      activePenaltyCount: (json['activePenaltyCount'] as num?)?.toInt() ?? 0,
      activeSkipCount: (json['activeSkipCount'] as num?)?.toInt() ?? 0,
      suitLock: $enumDecodeNullable(_$SuitEnumMap, json['suitLock']),
      queenSuitLock: $enumDecodeNullable(_$SuitEnumMap, json['queenSuitLock']),
      winnerId: json['winnerId'] as String?,
      lastUpdatedAt: (json['lastUpdatedAt'] as num?)?.toInt() ?? 0,
      actionsThisTurn: (json['actionsThisTurn'] as num?)?.toInt() ?? 0,
      lastPlayedThisTurn: json['lastPlayedThisTurn'] == null
          ? null
          : CardModel.fromJson(
              json['lastPlayedThisTurn'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$GameStateImplToJson(_$GameStateImpl instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'phase': _$GamePhaseEnumMap[instance.phase]!,
      'players': instance.players,
      'currentPlayerId': instance.currentPlayerId,
      'direction': _$PlayDirectionEnumMap[instance.direction]!,
      'discardTopCard': instance.discardTopCard,
      'discardSecondCard': instance.discardSecondCard,
      'drawPileCount': instance.drawPileCount,
      'activePenaltyCount': instance.activePenaltyCount,
      'activeSkipCount': instance.activeSkipCount,
      'suitLock': _$SuitEnumMap[instance.suitLock],
      'queenSuitLock': _$SuitEnumMap[instance.queenSuitLock],
      'winnerId': instance.winnerId,
      'lastUpdatedAt': instance.lastUpdatedAt,
      'actionsThisTurn': instance.actionsThisTurn,
      'lastPlayedThisTurn': instance.lastPlayedThisTurn,
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
