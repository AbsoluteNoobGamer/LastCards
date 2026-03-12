// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'game_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

GameState _$GameStateFromJson(Map<String, dynamic> json) {
  return _GameState.fromJson(json);
}

/// @nodoc
mixin _$GameState {
  String get sessionId => throw _privateConstructorUsedError;
  GamePhase get phase => throw _privateConstructorUsedError;
  List<PlayerModel> get players => throw _privateConstructorUsedError;
  String get currentPlayerId => throw _privateConstructorUsedError;
  PlayDirection get direction => throw _privateConstructorUsedError;

  /// Top card of the discard pile (null only before first card is turned).
  CardModel? get discardTopCard => throw _privateConstructorUsedError;

  /// Second-from-top card for visual stacking effect on the discard pile.
  CardModel? get discardSecondCard => throw _privateConstructorUsedError;

  /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
  List<CardModel> get discardPileHistory => throw _privateConstructorUsedError;

  /// Number of cards remaining in the draw pile.
  int get drawPileCount => throw _privateConstructorUsedError;

  /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
  int get activePenaltyCount => throw _privateConstructorUsedError;

  /// Accumulated skips built up during a turn by playing 8s.
  int get activeSkipCount => throw _privateConstructorUsedError;

  /// Active suit lock from an Ace or Joker declaration.
  Suit? get suitLock => throw _privateConstructorUsedError;

  /// The suit of the centre pile before the first card of the turn was played.
  /// Used to validate sequence continuations originating from an Ace play.
  Suit? get preTurnCentreSuit => throw _privateConstructorUsedError;

  /// Active suit from a Queen — the next player MUST follow this suit.
  Suit? get queenSuitLock => throw _privateConstructorUsedError;

  /// ID of the player who has won (null if game not yet ended).
  String? get winnerId => throw _privateConstructorUsedError;

  /// Server timestamp of the last state update (for stale detection).
  int get lastUpdatedAt => throw _privateConstructorUsedError;

  /// Number of valid actions (plays) taken by the current player this turn.
  /// Resets to 0 whenever the active player changes.
  /// Used to enforce that a player must play or draw before ending their turn.
  int get actionsThisTurn => throw _privateConstructorUsedError;

  /// Number of individual cards played by the current player this turn.
  /// Resets to 0 whenever the active player changes (at start of each new turn).
  /// Used to determine if an Ace was played alone or as part of a sequence.
  int get cardsPlayedThisTurn => throw _privateConstructorUsedError;

  /// The last card played by the current player this turn (as a single play).
  /// Used to enforce rank-adjacency between consecutive individual plays within
  /// the same turn (Numerical Flow Rule). Reset to null when the turn advances.
  CardModel? get lastPlayedThisTurn => throw _privateConstructorUsedError;

  /// True while a Joker has been committed as a play but still needs
  /// its represented card selection to be finalized in UI.
  bool get pendingJokerResolution => throw _privateConstructorUsedError;

  /// Serializes this GameState to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GameStateCopyWith<GameState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GameStateCopyWith<$Res> {
  factory $GameStateCopyWith(GameState value, $Res Function(GameState) then) =
      _$GameStateCopyWithImpl<$Res, GameState>;
  @useResult
  $Res call(
      {String sessionId,
      GamePhase phase,
      List<PlayerModel> players,
      String currentPlayerId,
      PlayDirection direction,
      CardModel? discardTopCard,
      CardModel? discardSecondCard,
      List<CardModel> discardPileHistory,
      int drawPileCount,
      int activePenaltyCount,
      int activeSkipCount,
      Suit? suitLock,
      Suit? preTurnCentreSuit,
      Suit? queenSuitLock,
      String? winnerId,
      int lastUpdatedAt,
      int actionsThisTurn,
      int cardsPlayedThisTurn,
      CardModel? lastPlayedThisTurn,
      bool pendingJokerResolution});

  $CardModelCopyWith<$Res>? get discardTopCard;
  $CardModelCopyWith<$Res>? get discardSecondCard;
  $CardModelCopyWith<$Res>? get lastPlayedThisTurn;
}

/// @nodoc
class _$GameStateCopyWithImpl<$Res, $Val extends GameState>
    implements $GameStateCopyWith<$Res> {
  _$GameStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? phase = null,
    Object? players = null,
    Object? currentPlayerId = null,
    Object? direction = null,
    Object? discardTopCard = freezed,
    Object? discardSecondCard = freezed,
    Object? discardPileHistory = null,
    Object? drawPileCount = null,
    Object? activePenaltyCount = null,
    Object? activeSkipCount = null,
    Object? suitLock = freezed,
    Object? preTurnCentreSuit = freezed,
    Object? queenSuitLock = freezed,
    Object? winnerId = freezed,
    Object? lastUpdatedAt = null,
    Object? actionsThisTurn = null,
    Object? cardsPlayedThisTurn = null,
    Object? lastPlayedThisTurn = freezed,
    Object? pendingJokerResolution = null,
  }) {
    return _then(_value.copyWith(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      phase: null == phase
          ? _value.phase
          : phase // ignore: cast_nullable_to_non_nullable
              as GamePhase,
      players: null == players
          ? _value.players
          : players // ignore: cast_nullable_to_non_nullable
              as List<PlayerModel>,
      currentPlayerId: null == currentPlayerId
          ? _value.currentPlayerId
          : currentPlayerId // ignore: cast_nullable_to_non_nullable
              as String,
      direction: null == direction
          ? _value.direction
          : direction // ignore: cast_nullable_to_non_nullable
              as PlayDirection,
      discardTopCard: freezed == discardTopCard
          ? _value.discardTopCard
          : discardTopCard // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      discardSecondCard: freezed == discardSecondCard
          ? _value.discardSecondCard
          : discardSecondCard // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      discardPileHistory: null == discardPileHistory
          ? _value.discardPileHistory
          : discardPileHistory // ignore: cast_nullable_to_non_nullable
              as List<CardModel>,
      drawPileCount: null == drawPileCount
          ? _value.drawPileCount
          : drawPileCount // ignore: cast_nullable_to_non_nullable
              as int,
      activePenaltyCount: null == activePenaltyCount
          ? _value.activePenaltyCount
          : activePenaltyCount // ignore: cast_nullable_to_non_nullable
              as int,
      activeSkipCount: null == activeSkipCount
          ? _value.activeSkipCount
          : activeSkipCount // ignore: cast_nullable_to_non_nullable
              as int,
      suitLock: freezed == suitLock
          ? _value.suitLock
          : suitLock // ignore: cast_nullable_to_non_nullable
              as Suit?,
      preTurnCentreSuit: freezed == preTurnCentreSuit
          ? _value.preTurnCentreSuit
          : preTurnCentreSuit // ignore: cast_nullable_to_non_nullable
              as Suit?,
      queenSuitLock: freezed == queenSuitLock
          ? _value.queenSuitLock
          : queenSuitLock // ignore: cast_nullable_to_non_nullable
              as Suit?,
      winnerId: freezed == winnerId
          ? _value.winnerId
          : winnerId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastUpdatedAt: null == lastUpdatedAt
          ? _value.lastUpdatedAt
          : lastUpdatedAt // ignore: cast_nullable_to_non_nullable
              as int,
      actionsThisTurn: null == actionsThisTurn
          ? _value.actionsThisTurn
          : actionsThisTurn // ignore: cast_nullable_to_non_nullable
              as int,
      cardsPlayedThisTurn: null == cardsPlayedThisTurn
          ? _value.cardsPlayedThisTurn
          : cardsPlayedThisTurn // ignore: cast_nullable_to_non_nullable
              as int,
      lastPlayedThisTurn: freezed == lastPlayedThisTurn
          ? _value.lastPlayedThisTurn
          : lastPlayedThisTurn // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      pendingJokerResolution: null == pendingJokerResolution
          ? _value.pendingJokerResolution
          : pendingJokerResolution // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $CardModelCopyWith<$Res>? get discardTopCard {
    if (_value.discardTopCard == null) {
      return null;
    }

    return $CardModelCopyWith<$Res>(_value.discardTopCard!, (value) {
      return _then(_value.copyWith(discardTopCard: value) as $Val);
    });
  }

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $CardModelCopyWith<$Res>? get discardSecondCard {
    if (_value.discardSecondCard == null) {
      return null;
    }

    return $CardModelCopyWith<$Res>(_value.discardSecondCard!, (value) {
      return _then(_value.copyWith(discardSecondCard: value) as $Val);
    });
  }

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $CardModelCopyWith<$Res>? get lastPlayedThisTurn {
    if (_value.lastPlayedThisTurn == null) {
      return null;
    }

    return $CardModelCopyWith<$Res>(_value.lastPlayedThisTurn!, (value) {
      return _then(_value.copyWith(lastPlayedThisTurn: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$GameStateImplCopyWith<$Res>
    implements $GameStateCopyWith<$Res> {
  factory _$$GameStateImplCopyWith(
          _$GameStateImpl value, $Res Function(_$GameStateImpl) then) =
      __$$GameStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String sessionId,
      GamePhase phase,
      List<PlayerModel> players,
      String currentPlayerId,
      PlayDirection direction,
      CardModel? discardTopCard,
      CardModel? discardSecondCard,
      List<CardModel> discardPileHistory,
      int drawPileCount,
      int activePenaltyCount,
      int activeSkipCount,
      Suit? suitLock,
      Suit? preTurnCentreSuit,
      Suit? queenSuitLock,
      String? winnerId,
      int lastUpdatedAt,
      int actionsThisTurn,
      int cardsPlayedThisTurn,
      CardModel? lastPlayedThisTurn,
      bool pendingJokerResolution});

  @override
  $CardModelCopyWith<$Res>? get discardTopCard;
  @override
  $CardModelCopyWith<$Res>? get discardSecondCard;
  @override
  $CardModelCopyWith<$Res>? get lastPlayedThisTurn;
}

/// @nodoc
class __$$GameStateImplCopyWithImpl<$Res>
    extends _$GameStateCopyWithImpl<$Res, _$GameStateImpl>
    implements _$$GameStateImplCopyWith<$Res> {
  __$$GameStateImplCopyWithImpl(
      _$GameStateImpl _value, $Res Function(_$GameStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? phase = null,
    Object? players = null,
    Object? currentPlayerId = null,
    Object? direction = null,
    Object? discardTopCard = freezed,
    Object? discardSecondCard = freezed,
    Object? discardPileHistory = null,
    Object? drawPileCount = null,
    Object? activePenaltyCount = null,
    Object? activeSkipCount = null,
    Object? suitLock = freezed,
    Object? preTurnCentreSuit = freezed,
    Object? queenSuitLock = freezed,
    Object? winnerId = freezed,
    Object? lastUpdatedAt = null,
    Object? actionsThisTurn = null,
    Object? cardsPlayedThisTurn = null,
    Object? lastPlayedThisTurn = freezed,
    Object? pendingJokerResolution = null,
  }) {
    return _then(_$GameStateImpl(
      sessionId: null == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      phase: null == phase
          ? _value.phase
          : phase // ignore: cast_nullable_to_non_nullable
              as GamePhase,
      players: null == players
          ? _value._players
          : players // ignore: cast_nullable_to_non_nullable
              as List<PlayerModel>,
      currentPlayerId: null == currentPlayerId
          ? _value.currentPlayerId
          : currentPlayerId // ignore: cast_nullable_to_non_nullable
              as String,
      direction: null == direction
          ? _value.direction
          : direction // ignore: cast_nullable_to_non_nullable
              as PlayDirection,
      discardTopCard: freezed == discardTopCard
          ? _value.discardTopCard
          : discardTopCard // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      discardSecondCard: freezed == discardSecondCard
          ? _value.discardSecondCard
          : discardSecondCard // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      discardPileHistory: null == discardPileHistory
          ? _value._discardPileHistory
          : discardPileHistory // ignore: cast_nullable_to_non_nullable
              as List<CardModel>,
      drawPileCount: null == drawPileCount
          ? _value.drawPileCount
          : drawPileCount // ignore: cast_nullable_to_non_nullable
              as int,
      activePenaltyCount: null == activePenaltyCount
          ? _value.activePenaltyCount
          : activePenaltyCount // ignore: cast_nullable_to_non_nullable
              as int,
      activeSkipCount: null == activeSkipCount
          ? _value.activeSkipCount
          : activeSkipCount // ignore: cast_nullable_to_non_nullable
              as int,
      suitLock: freezed == suitLock
          ? _value.suitLock
          : suitLock // ignore: cast_nullable_to_non_nullable
              as Suit?,
      preTurnCentreSuit: freezed == preTurnCentreSuit
          ? _value.preTurnCentreSuit
          : preTurnCentreSuit // ignore: cast_nullable_to_non_nullable
              as Suit?,
      queenSuitLock: freezed == queenSuitLock
          ? _value.queenSuitLock
          : queenSuitLock // ignore: cast_nullable_to_non_nullable
              as Suit?,
      winnerId: freezed == winnerId
          ? _value.winnerId
          : winnerId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastUpdatedAt: null == lastUpdatedAt
          ? _value.lastUpdatedAt
          : lastUpdatedAt // ignore: cast_nullable_to_non_nullable
              as int,
      actionsThisTurn: null == actionsThisTurn
          ? _value.actionsThisTurn
          : actionsThisTurn // ignore: cast_nullable_to_non_nullable
              as int,
      cardsPlayedThisTurn: null == cardsPlayedThisTurn
          ? _value.cardsPlayedThisTurn
          : cardsPlayedThisTurn // ignore: cast_nullable_to_non_nullable
              as int,
      lastPlayedThisTurn: freezed == lastPlayedThisTurn
          ? _value.lastPlayedThisTurn
          : lastPlayedThisTurn // ignore: cast_nullable_to_non_nullable
              as CardModel?,
      pendingJokerResolution: null == pendingJokerResolution
          ? _value.pendingJokerResolution
          : pendingJokerResolution // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GameStateImpl implements _GameState {
  const _$GameStateImpl(
      {required this.sessionId,
      required this.phase,
      required final List<PlayerModel> players,
      required this.currentPlayerId,
      required this.direction,
      this.discardTopCard,
      this.discardSecondCard,
      final List<CardModel> discardPileHistory = const [],
      this.drawPileCount = 0,
      this.activePenaltyCount = 0,
      this.activeSkipCount = 0,
      this.suitLock,
      this.preTurnCentreSuit,
      this.queenSuitLock,
      this.winnerId,
      this.lastUpdatedAt = 0,
      this.actionsThisTurn = 0,
      this.cardsPlayedThisTurn = 0,
      this.lastPlayedThisTurn,
      this.pendingJokerResolution = false})
      : _players = players,
        _discardPileHistory = discardPileHistory;

  factory _$GameStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$GameStateImplFromJson(json);

  @override
  final String sessionId;
  @override
  final GamePhase phase;
  final List<PlayerModel> _players;
  @override
  List<PlayerModel> get players {
    if (_players is EqualUnmodifiableListView) return _players;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_players);
  }

  @override
  final String currentPlayerId;
  @override
  final PlayDirection direction;

  /// Top card of the discard pile (null only before first card is turned).
  @override
  final CardModel? discardTopCard;

  /// Second-from-top card for visual stacking effect on the discard pile.
  @override
  final CardModel? discardSecondCard;

  /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
  final List<CardModel> _discardPileHistory;

  /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
  @override
  @JsonKey()
  List<CardModel> get discardPileHistory {
    if (_discardPileHistory is EqualUnmodifiableListView)
      return _discardPileHistory;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_discardPileHistory);
  }

  /// Number of cards remaining in the draw pile.
  @override
  @JsonKey()
  final int drawPileCount;

  /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
  @override
  @JsonKey()
  final int activePenaltyCount;

  /// Accumulated skips built up during a turn by playing 8s.
  @override
  @JsonKey()
  final int activeSkipCount;

  /// Active suit lock from an Ace or Joker declaration.
  @override
  final Suit? suitLock;

  /// The suit of the centre pile before the first card of the turn was played.
  /// Used to validate sequence continuations originating from an Ace play.
  @override
  final Suit? preTurnCentreSuit;

  /// Active suit from a Queen — the next player MUST follow this suit.
  @override
  final Suit? queenSuitLock;

  /// ID of the player who has won (null if game not yet ended).
  @override
  final String? winnerId;

  /// Server timestamp of the last state update (for stale detection).
  @override
  @JsonKey()
  final int lastUpdatedAt;

  /// Number of valid actions (plays) taken by the current player this turn.
  /// Resets to 0 whenever the active player changes.
  /// Used to enforce that a player must play or draw before ending their turn.
  @override
  @JsonKey()
  final int actionsThisTurn;

  /// Number of individual cards played by the current player this turn.
  /// Resets to 0 whenever the active player changes (at start of each new turn).
  /// Used to determine if an Ace was played alone or as part of a sequence.
  @override
  @JsonKey()
  final int cardsPlayedThisTurn;

  /// The last card played by the current player this turn (as a single play).
  /// Used to enforce rank-adjacency between consecutive individual plays within
  /// the same turn (Numerical Flow Rule). Reset to null when the turn advances.
  @override
  final CardModel? lastPlayedThisTurn;

  /// True while a Joker has been committed as a play but still needs
  /// its represented card selection to be finalized in UI.
  @override
  @JsonKey()
  final bool pendingJokerResolution;

  @override
  String toString() {
    return 'GameState(sessionId: $sessionId, phase: $phase, players: $players, currentPlayerId: $currentPlayerId, direction: $direction, discardTopCard: $discardTopCard, discardSecondCard: $discardSecondCard, discardPileHistory: $discardPileHistory, drawPileCount: $drawPileCount, activePenaltyCount: $activePenaltyCount, activeSkipCount: $activeSkipCount, suitLock: $suitLock, preTurnCentreSuit: $preTurnCentreSuit, queenSuitLock: $queenSuitLock, winnerId: $winnerId, lastUpdatedAt: $lastUpdatedAt, actionsThisTurn: $actionsThisTurn, cardsPlayedThisTurn: $cardsPlayedThisTurn, lastPlayedThisTurn: $lastPlayedThisTurn, pendingJokerResolution: $pendingJokerResolution)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GameStateImpl &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.phase, phase) || other.phase == phase) &&
            const DeepCollectionEquality().equals(other._players, _players) &&
            (identical(other.currentPlayerId, currentPlayerId) ||
                other.currentPlayerId == currentPlayerId) &&
            (identical(other.direction, direction) ||
                other.direction == direction) &&
            (identical(other.discardTopCard, discardTopCard) ||
                other.discardTopCard == discardTopCard) &&
            (identical(other.discardSecondCard, discardSecondCard) ||
                other.discardSecondCard == discardSecondCard) &&
            const DeepCollectionEquality()
                .equals(other._discardPileHistory, _discardPileHistory) &&
            (identical(other.drawPileCount, drawPileCount) ||
                other.drawPileCount == drawPileCount) &&
            (identical(other.activePenaltyCount, activePenaltyCount) ||
                other.activePenaltyCount == activePenaltyCount) &&
            (identical(other.activeSkipCount, activeSkipCount) ||
                other.activeSkipCount == activeSkipCount) &&
            (identical(other.suitLock, suitLock) ||
                other.suitLock == suitLock) &&
            (identical(other.preTurnCentreSuit, preTurnCentreSuit) ||
                other.preTurnCentreSuit == preTurnCentreSuit) &&
            (identical(other.queenSuitLock, queenSuitLock) ||
                other.queenSuitLock == queenSuitLock) &&
            (identical(other.winnerId, winnerId) ||
                other.winnerId == winnerId) &&
            (identical(other.lastUpdatedAt, lastUpdatedAt) ||
                other.lastUpdatedAt == lastUpdatedAt) &&
            (identical(other.actionsThisTurn, actionsThisTurn) ||
                other.actionsThisTurn == actionsThisTurn) &&
            (identical(other.cardsPlayedThisTurn, cardsPlayedThisTurn) ||
                other.cardsPlayedThisTurn == cardsPlayedThisTurn) &&
            (identical(other.lastPlayedThisTurn, lastPlayedThisTurn) ||
                other.lastPlayedThisTurn == lastPlayedThisTurn) &&
            (identical(other.pendingJokerResolution, pendingJokerResolution) ||
                other.pendingJokerResolution == pendingJokerResolution));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        sessionId,
        phase,
        const DeepCollectionEquality().hash(_players),
        currentPlayerId,
        direction,
        discardTopCard,
        discardSecondCard,
        const DeepCollectionEquality().hash(_discardPileHistory),
        drawPileCount,
        activePenaltyCount,
        activeSkipCount,
        suitLock,
        preTurnCentreSuit,
        queenSuitLock,
        winnerId,
        lastUpdatedAt,
        actionsThisTurn,
        cardsPlayedThisTurn,
        lastPlayedThisTurn,
        pendingJokerResolution
      ]);

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GameStateImplCopyWith<_$GameStateImpl> get copyWith =>
      __$$GameStateImplCopyWithImpl<_$GameStateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GameStateImplToJson(
      this,
    );
  }
}

abstract class _GameState implements GameState {
  const factory _GameState(
      {required final String sessionId,
      required final GamePhase phase,
      required final List<PlayerModel> players,
      required final String currentPlayerId,
      required final PlayDirection direction,
      final CardModel? discardTopCard,
      final CardModel? discardSecondCard,
      final List<CardModel> discardPileHistory,
      final int drawPileCount,
      final int activePenaltyCount,
      final int activeSkipCount,
      final Suit? suitLock,
      final Suit? preTurnCentreSuit,
      final Suit? queenSuitLock,
      final String? winnerId,
      final int lastUpdatedAt,
      final int actionsThisTurn,
      final int cardsPlayedThisTurn,
      final CardModel? lastPlayedThisTurn,
      final bool pendingJokerResolution}) = _$GameStateImpl;

  factory _GameState.fromJson(Map<String, dynamic> json) =
      _$GameStateImpl.fromJson;

  @override
  String get sessionId;
  @override
  GamePhase get phase;
  @override
  List<PlayerModel> get players;
  @override
  String get currentPlayerId;
  @override
  PlayDirection get direction;

  /// Top card of the discard pile (null only before first card is turned).
  @override
  CardModel? get discardTopCard;

  /// Second-from-top card for visual stacking effect on the discard pile.
  @override
  CardModel? get discardSecondCard;

  /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
  @override
  List<CardModel> get discardPileHistory;

  /// Number of cards remaining in the draw pile.
  @override
  int get drawPileCount;

  /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
  @override
  int get activePenaltyCount;

  /// Accumulated skips built up during a turn by playing 8s.
  @override
  int get activeSkipCount;

  /// Active suit lock from an Ace or Joker declaration.
  @override
  Suit? get suitLock;

  /// The suit of the centre pile before the first card of the turn was played.
  /// Used to validate sequence continuations originating from an Ace play.
  @override
  Suit? get preTurnCentreSuit;

  /// Active suit from a Queen — the next player MUST follow this suit.
  @override
  Suit? get queenSuitLock;

  /// ID of the player who has won (null if game not yet ended).
  @override
  String? get winnerId;

  /// Server timestamp of the last state update (for stale detection).
  @override
  int get lastUpdatedAt;

  /// Number of valid actions (plays) taken by the current player this turn.
  /// Resets to 0 whenever the active player changes.
  /// Used to enforce that a player must play or draw before ending their turn.
  @override
  int get actionsThisTurn;

  /// Number of individual cards played by the current player this turn.
  /// Resets to 0 whenever the active player changes (at start of each new turn).
  /// Used to determine if an Ace was played alone or as part of a sequence.
  @override
  int get cardsPlayedThisTurn;

  /// The last card played by the current player this turn (as a single play).
  /// Used to enforce rank-adjacency between consecutive individual plays within
  /// the same turn (Numerical Flow Rule). Reset to null when the turn advances.
  @override
  CardModel? get lastPlayedThisTurn;

  /// True while a Joker has been committed as a play but still needs
  /// its represented card selection to be finalized in UI.
  @override
  bool get pendingJokerResolution;

  /// Create a copy of GameState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GameStateImplCopyWith<_$GameStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
