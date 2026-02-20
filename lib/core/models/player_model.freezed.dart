// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

PlayerModel _$PlayerModelFromJson(Map<String, dynamic> json) {
  return _PlayerModel.fromJson(json);
}

/// @nodoc
mixin _$PlayerModel {
  String get id => throw _privateConstructorUsedError;
  String get displayName => throw _privateConstructorUsedError;
  TablePosition get tablePosition => throw _privateConstructorUsedError;

  /// Cards in hand — populated only for the local player.
  /// For opponents, this is always empty (server sends count only).
  List<CardModel> get hand => throw _privateConstructorUsedError;

  /// Number of cards the player holds. Always accurate for all players.
  int get cardCount => throw _privateConstructorUsedError;

  /// Whether the player is currently connected to the game session.
  bool get isConnected => throw _privateConstructorUsedError;

  /// Whether it is currently this player's turn.
  bool get isActiveTurn => throw _privateConstructorUsedError;

  /// Set to true when affected by an 8 (skip) card effect.
  bool get isSkipped => throw _privateConstructorUsedError;

  /// Serializes this PlayerModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PlayerModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlayerModelCopyWith<PlayerModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlayerModelCopyWith<$Res> {
  factory $PlayerModelCopyWith(
          PlayerModel value, $Res Function(PlayerModel) then) =
      _$PlayerModelCopyWithImpl<$Res, PlayerModel>;
  @useResult
  $Res call(
      {String id,
      String displayName,
      TablePosition tablePosition,
      List<CardModel> hand,
      int cardCount,
      bool isConnected,
      bool isActiveTurn,
      bool isSkipped});
}

/// @nodoc
class _$PlayerModelCopyWithImpl<$Res, $Val extends PlayerModel>
    implements $PlayerModelCopyWith<$Res> {
  _$PlayerModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlayerModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? displayName = null,
    Object? tablePosition = null,
    Object? hand = null,
    Object? cardCount = null,
    Object? isConnected = null,
    Object? isActiveTurn = null,
    Object? isSkipped = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      tablePosition: null == tablePosition
          ? _value.tablePosition
          : tablePosition // ignore: cast_nullable_to_non_nullable
              as TablePosition,
      hand: null == hand
          ? _value.hand
          : hand // ignore: cast_nullable_to_non_nullable
              as List<CardModel>,
      cardCount: null == cardCount
          ? _value.cardCount
          : cardCount // ignore: cast_nullable_to_non_nullable
              as int,
      isConnected: null == isConnected
          ? _value.isConnected
          : isConnected // ignore: cast_nullable_to_non_nullable
              as bool,
      isActiveTurn: null == isActiveTurn
          ? _value.isActiveTurn
          : isActiveTurn // ignore: cast_nullable_to_non_nullable
              as bool,
      isSkipped: null == isSkipped
          ? _value.isSkipped
          : isSkipped // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PlayerModelImplCopyWith<$Res>
    implements $PlayerModelCopyWith<$Res> {
  factory _$$PlayerModelImplCopyWith(
          _$PlayerModelImpl value, $Res Function(_$PlayerModelImpl) then) =
      __$$PlayerModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String displayName,
      TablePosition tablePosition,
      List<CardModel> hand,
      int cardCount,
      bool isConnected,
      bool isActiveTurn,
      bool isSkipped});
}

/// @nodoc
class __$$PlayerModelImplCopyWithImpl<$Res>
    extends _$PlayerModelCopyWithImpl<$Res, _$PlayerModelImpl>
    implements _$$PlayerModelImplCopyWith<$Res> {
  __$$PlayerModelImplCopyWithImpl(
      _$PlayerModelImpl _value, $Res Function(_$PlayerModelImpl) _then)
      : super(_value, _then);

  /// Create a copy of PlayerModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? displayName = null,
    Object? tablePosition = null,
    Object? hand = null,
    Object? cardCount = null,
    Object? isConnected = null,
    Object? isActiveTurn = null,
    Object? isSkipped = null,
  }) {
    return _then(_$PlayerModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      tablePosition: null == tablePosition
          ? _value.tablePosition
          : tablePosition // ignore: cast_nullable_to_non_nullable
              as TablePosition,
      hand: null == hand
          ? _value._hand
          : hand // ignore: cast_nullable_to_non_nullable
              as List<CardModel>,
      cardCount: null == cardCount
          ? _value.cardCount
          : cardCount // ignore: cast_nullable_to_non_nullable
              as int,
      isConnected: null == isConnected
          ? _value.isConnected
          : isConnected // ignore: cast_nullable_to_non_nullable
              as bool,
      isActiveTurn: null == isActiveTurn
          ? _value.isActiveTurn
          : isActiveTurn // ignore: cast_nullable_to_non_nullable
              as bool,
      isSkipped: null == isSkipped
          ? _value.isSkipped
          : isSkipped // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PlayerModelImpl implements _PlayerModel {
  const _$PlayerModelImpl(
      {required this.id,
      required this.displayName,
      required this.tablePosition,
      final List<CardModel> hand = const [],
      this.cardCount = 0,
      this.isConnected = true,
      this.isActiveTurn = false,
      this.isSkipped = false})
      : _hand = hand;

  factory _$PlayerModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$PlayerModelImplFromJson(json);

  @override
  final String id;
  @override
  final String displayName;
  @override
  final TablePosition tablePosition;

  /// Cards in hand — populated only for the local player.
  /// For opponents, this is always empty (server sends count only).
  final List<CardModel> _hand;

  /// Cards in hand — populated only for the local player.
  /// For opponents, this is always empty (server sends count only).
  @override
  @JsonKey()
  List<CardModel> get hand {
    if (_hand is EqualUnmodifiableListView) return _hand;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_hand);
  }

  /// Number of cards the player holds. Always accurate for all players.
  @override
  @JsonKey()
  final int cardCount;

  /// Whether the player is currently connected to the game session.
  @override
  @JsonKey()
  final bool isConnected;

  /// Whether it is currently this player's turn.
  @override
  @JsonKey()
  final bool isActiveTurn;

  /// Set to true when affected by an 8 (skip) card effect.
  @override
  @JsonKey()
  final bool isSkipped;

  @override
  String toString() {
    return 'PlayerModel(id: $id, displayName: $displayName, tablePosition: $tablePosition, hand: $hand, cardCount: $cardCount, isConnected: $isConnected, isActiveTurn: $isActiveTurn, isSkipped: $isSkipped)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.tablePosition, tablePosition) ||
                other.tablePosition == tablePosition) &&
            const DeepCollectionEquality().equals(other._hand, _hand) &&
            (identical(other.cardCount, cardCount) ||
                other.cardCount == cardCount) &&
            (identical(other.isConnected, isConnected) ||
                other.isConnected == isConnected) &&
            (identical(other.isActiveTurn, isActiveTurn) ||
                other.isActiveTurn == isActiveTurn) &&
            (identical(other.isSkipped, isSkipped) ||
                other.isSkipped == isSkipped));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      displayName,
      tablePosition,
      const DeepCollectionEquality().hash(_hand),
      cardCount,
      isConnected,
      isActiveTurn,
      isSkipped);

  /// Create a copy of PlayerModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlayerModelImplCopyWith<_$PlayerModelImpl> get copyWith =>
      __$$PlayerModelImplCopyWithImpl<_$PlayerModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PlayerModelImplToJson(
      this,
    );
  }
}

abstract class _PlayerModel implements PlayerModel {
  const factory _PlayerModel(
      {required final String id,
      required final String displayName,
      required final TablePosition tablePosition,
      final List<CardModel> hand,
      final int cardCount,
      final bool isConnected,
      final bool isActiveTurn,
      final bool isSkipped}) = _$PlayerModelImpl;

  factory _PlayerModel.fromJson(Map<String, dynamic> json) =
      _$PlayerModelImpl.fromJson;

  @override
  String get id;
  @override
  String get displayName;
  @override
  TablePosition get tablePosition;

  /// Cards in hand — populated only for the local player.
  /// For opponents, this is always empty (server sends count only).
  @override
  List<CardModel> get hand;

  /// Number of cards the player holds. Always accurate for all players.
  @override
  int get cardCount;

  /// Whether the player is currently connected to the game session.
  @override
  bool get isConnected;

  /// Whether it is currently this player's turn.
  @override
  bool get isActiveTurn;

  /// Set to true when affected by an 8 (skip) card effect.
  @override
  bool get isSkipped;

  /// Create a copy of PlayerModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlayerModelImplCopyWith<_$PlayerModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
