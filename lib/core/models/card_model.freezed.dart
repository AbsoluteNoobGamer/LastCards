// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'card_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CardModel _$CardModelFromJson(Map<String, dynamic> json) {
  return _CardModel.fromJson(json);
}

/// @nodoc
mixin _$CardModel {
  String get id => throw _privateConstructorUsedError;
  Rank get rank => throw _privateConstructorUsedError;
  Suit get suit => throw _privateConstructorUsedError;

  /// Only set when this card is a Joker that has been declared by the player.
  Suit? get jokerDeclaredSuit => throw _privateConstructorUsedError;
  Rank? get jokerDeclaredRank => throw _privateConstructorUsedError;

  /// Serializes this CardModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CardModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CardModelCopyWith<CardModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CardModelCopyWith<$Res> {
  factory $CardModelCopyWith(CardModel value, $Res Function(CardModel) then) =
      _$CardModelCopyWithImpl<$Res, CardModel>;
  @useResult
  $Res call(
      {String id,
      Rank rank,
      Suit suit,
      Suit? jokerDeclaredSuit,
      Rank? jokerDeclaredRank});
}

/// @nodoc
class _$CardModelCopyWithImpl<$Res, $Val extends CardModel>
    implements $CardModelCopyWith<$Res> {
  _$CardModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CardModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? rank = null,
    Object? suit = null,
    Object? jokerDeclaredSuit = freezed,
    Object? jokerDeclaredRank = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as Rank,
      suit: null == suit
          ? _value.suit
          : suit // ignore: cast_nullable_to_non_nullable
              as Suit,
      jokerDeclaredSuit: freezed == jokerDeclaredSuit
          ? _value.jokerDeclaredSuit
          : jokerDeclaredSuit // ignore: cast_nullable_to_non_nullable
              as Suit?,
      jokerDeclaredRank: freezed == jokerDeclaredRank
          ? _value.jokerDeclaredRank
          : jokerDeclaredRank // ignore: cast_nullable_to_non_nullable
              as Rank?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CardModelImplCopyWith<$Res>
    implements $CardModelCopyWith<$Res> {
  factory _$$CardModelImplCopyWith(
          _$CardModelImpl value, $Res Function(_$CardModelImpl) then) =
      __$$CardModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      Rank rank,
      Suit suit,
      Suit? jokerDeclaredSuit,
      Rank? jokerDeclaredRank});
}

/// @nodoc
class __$$CardModelImplCopyWithImpl<$Res>
    extends _$CardModelCopyWithImpl<$Res, _$CardModelImpl>
    implements _$$CardModelImplCopyWith<$Res> {
  __$$CardModelImplCopyWithImpl(
      _$CardModelImpl _value, $Res Function(_$CardModelImpl) _then)
      : super(_value, _then);

  /// Create a copy of CardModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? rank = null,
    Object? suit = null,
    Object? jokerDeclaredSuit = freezed,
    Object? jokerDeclaredRank = freezed,
  }) {
    return _then(_$CardModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as Rank,
      suit: null == suit
          ? _value.suit
          : suit // ignore: cast_nullable_to_non_nullable
              as Suit,
      jokerDeclaredSuit: freezed == jokerDeclaredSuit
          ? _value.jokerDeclaredSuit
          : jokerDeclaredSuit // ignore: cast_nullable_to_non_nullable
              as Suit?,
      jokerDeclaredRank: freezed == jokerDeclaredRank
          ? _value.jokerDeclaredRank
          : jokerDeclaredRank // ignore: cast_nullable_to_non_nullable
              as Rank?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CardModelImpl implements _CardModel {
  const _$CardModelImpl(
      {required this.id,
      required this.rank,
      required this.suit,
      this.jokerDeclaredSuit,
      this.jokerDeclaredRank});

  factory _$CardModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$CardModelImplFromJson(json);

  @override
  final String id;
  @override
  final Rank rank;
  @override
  final Suit suit;

  /// Only set when this card is a Joker that has been declared by the player.
  @override
  final Suit? jokerDeclaredSuit;
  @override
  final Rank? jokerDeclaredRank;

  @override
  String toString() {
    return 'CardModel(id: $id, rank: $rank, suit: $suit, jokerDeclaredSuit: $jokerDeclaredSuit, jokerDeclaredRank: $jokerDeclaredRank)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CardModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.rank, rank) || other.rank == rank) &&
            (identical(other.suit, suit) || other.suit == suit) &&
            (identical(other.jokerDeclaredSuit, jokerDeclaredSuit) ||
                other.jokerDeclaredSuit == jokerDeclaredSuit) &&
            (identical(other.jokerDeclaredRank, jokerDeclaredRank) ||
                other.jokerDeclaredRank == jokerDeclaredRank));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, rank, suit, jokerDeclaredSuit, jokerDeclaredRank);

  /// Create a copy of CardModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CardModelImplCopyWith<_$CardModelImpl> get copyWith =>
      __$$CardModelImplCopyWithImpl<_$CardModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CardModelImplToJson(
      this,
    );
  }
}

abstract class _CardModel implements CardModel {
  const factory _CardModel(
      {required final String id,
      required final Rank rank,
      required final Suit suit,
      final Suit? jokerDeclaredSuit,
      final Rank? jokerDeclaredRank}) = _$CardModelImpl;

  factory _CardModel.fromJson(Map<String, dynamic> json) =
      _$CardModelImpl.fromJson;

  @override
  String get id;
  @override
  Rank get rank;
  @override
  Suit get suit;

  /// Only set when this card is a Joker that has been declared by the player.
  @override
  Suit? get jokerDeclaredSuit;
  @override
  Rank? get jokerDeclaredRank;

  /// Create a copy of CardModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CardModelImplCopyWith<_$CardModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
