// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PlayerModelImpl _$$PlayerModelImplFromJson(Map<String, dynamic> json) =>
    _$PlayerModelImpl(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      tablePosition: $enumDecode(_$TablePositionEnumMap, json['tablePosition']),
      hand: (json['hand'] as List<dynamic>?)
              ?.map((e) => CardModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$PlayerModelImplToJson(_$PlayerModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'tablePosition': _$TablePositionEnumMap[instance.tablePosition]!,
      'hand': instance.hand,
      'cardCount': instance.cardCount,
    };

const _$TablePositionEnumMap = {
  TablePosition.bottom: 'bottom',
  TablePosition.top: 'top',
  TablePosition.left: 'left',
  TablePosition.right: 'right',
};
