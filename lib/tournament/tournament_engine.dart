import 'dart:async';
import 'dart:collection';

import 'package:deck_drop/shared/models/game_state_model.dart';

enum TournamentMode { offline, online }

class TournamentPlayer {
  const TournamentPlayer({
    required this.id,
    required this.displayName,
    this.isAi = false,
  });

  final String id;
  final String displayName;
  final bool isAi;
}

class PlayerAdvancedEvent {
  const PlayerAdvancedEvent({
    required this.roundNumber,
    required this.playerId,
    required this.finishingPosition,
  });

  final int roundNumber;
  final String playerId;
  final int finishingPosition;
}

class PlayerEliminatedEvent {
  const PlayerEliminatedEvent({
    required this.roundNumber,
    required this.playerId,
    required this.finishingPosition,
  });

  final int roundNumber;
  final String playerId;
  final int finishingPosition;
}

class TournamentRoundResult {
  const TournamentRoundResult({
    required this.roundNumber,
    required this.playerIdsInFinishOrder,
    required this.advancedPlayerIds,
    required this.eliminatedPlayerId,
  });

  final int roundNumber;
  final List<String> playerIdsInFinishOrder;
  final List<String> advancedPlayerIds;
  final String eliminatedPlayerId;

  Map<String, int> get finishingPositions {
    final positions = <String, int>{};
    for (var i = 0; i < playerIdsInFinishOrder.length; i++) {
      positions[playerIdsInFinishOrder[i]] = i + 1;
    }
    return UnmodifiableMapView<String, int>(positions);
  }
}

class RoundCompleteEvent {
  const RoundCompleteEvent(this.result);

  final TournamentRoundResult result;
}

class TournamentCompleteEvent {
  const TournamentCompleteEvent({
    required this.winnerPlayerId,
    required this.roundResults,
  });

  final String winnerPlayerId;
  final List<TournamentRoundResult> roundResults;
}

class TournamentEngine {
  TournamentEngine._({
    required List<TournamentPlayer> players,
    required this.mode,
  }) : _allPlayers = List.unmodifiable(players);

  factory TournamentEngine.offline({
    required List<TournamentPlayer> players,
    int requiredPlayers = 4,
  }) {
    final seeded = List<TournamentPlayer>.from(players);
    final aiNeeded = requiredPlayers - seeded.length;
    for (var i = 0; i < aiNeeded; i++) {
      final index = seeded.length + 1;
      seeded.add(TournamentPlayer(
        id: 'tournament-ai-$index',
        displayName: 'Player $index',
        isAi: true,
      ));
    }
    return TournamentEngine._(players: seeded.take(requiredPlayers).toList(), mode: TournamentMode.offline);
  }

  factory TournamentEngine.online({
    required List<TournamentPlayer> players,
  }) {
    return TournamentEngine._(players: players, mode: TournamentMode.online);
  }

  final TournamentMode mode;
  final List<TournamentPlayer> _allPlayers;

  final StreamController<PlayerAdvancedEvent> _playerAdvancedController =
      StreamController<PlayerAdvancedEvent>.broadcast();
  final StreamController<PlayerEliminatedEvent> _playerEliminatedController =
      StreamController<PlayerEliminatedEvent>.broadcast();
  final StreamController<RoundCompleteEvent> _roundCompleteController =
      StreamController<RoundCompleteEvent>.broadcast();
  final StreamController<TournamentCompleteEvent> _tournamentCompleteController =
      StreamController<TournamentCompleteEvent>.broadcast();

  Stream<PlayerAdvancedEvent> get playerAdvanced =>
      _playerAdvancedController.stream;
  Stream<PlayerEliminatedEvent> get playerEliminated =>
      _playerEliminatedController.stream;
  Stream<RoundCompleteEvent> get roundComplete => _roundCompleteController.stream;
  Stream<TournamentCompleteEvent> get tournamentComplete =>
      _tournamentCompleteController.stream;

  int _currentRound = 0;
  bool _roundInProgress = false;
  bool _tournamentStarted = false;
  String? _winnerId;

  List<String> _activePlayerIds = <String>[];
  final List<String> _roundFinishingOrder = <String>[];
  final List<TournamentRoundResult> _roundResults = <TournamentRoundResult>[];
  final Map<int, Map<String, int>> _finishingPositionByRound =
      <int, Map<String, int>>{};
  final Map<String, int> _latestCardCounts = <String, int>{};

  StreamSubscription<GameState>? _stateSubscription;

  List<TournamentPlayer> get allPlayers => _allPlayers;
  int get currentRound => _currentRound;
  bool get hasStarted => _tournamentStarted;
  bool get isRoundInProgress => _roundInProgress;
  bool get isComplete => _winnerId != null;
  String? get winnerId => _winnerId;
  List<String> get activePlayerIds => List.unmodifiable(_activePlayerIds);
  List<String> get currentRoundFinishingOrder =>
      List.unmodifiable(_roundFinishingOrder);
  List<TournamentRoundResult> get roundResults =>
      List.unmodifiable(_roundResults);

  void startTournament() {
    if (_tournamentStarted) {
      return;
    }
    if (_allPlayers.length < 2) {
      throw StateError('Tournament requires at least 2 players.');
    }

    _tournamentStarted = true;
    _activePlayerIds = _allPlayers.map((player) => player.id).toList();
    _currentRound = 1;
    _roundFinishingOrder.clear();
    _roundInProgress = true;
  }

  void startNextRound() {
    if (!_tournamentStarted) {
      throw StateError('Tournament has not started.');
    }
    if (isComplete) {
      throw StateError('Tournament is already complete.');
    }
    if (_roundInProgress) {
      throw StateError('Current round is still in progress.');
    }
    if (_activePlayerIds.length < 2) {
      throw StateError('Not enough players to start another round.');
    }

    _currentRound += 1;
    _roundFinishingOrder.clear();
    _roundInProgress = true;
  }

  void attachGameStateStream(Stream<GameState> gameStateStream) {
    _stateSubscription?.cancel();
    _stateSubscription = gameStateStream.listen(onGameStateUpdated);
  }

  void onGameStateUpdated(GameState gameState) {
    if (!_roundInProgress || !_tournamentStarted || isComplete) {
      return;
    }

    final playersById = {for (final player in gameState.players) player.id: player};

    for (final playerId in _activePlayerIds) {
      final p = playersById[playerId];
      if (p != null) {
        _latestCardCounts[playerId] = p.cardCount;
      }
      if (p == null || _roundFinishingOrder.contains(playerId)) {
        continue;
      }
      if (p.cardCount == 0 && p.hand.isEmpty) {
        _recordFinisher(playerId);
      }
    }
  }

  void registerHandEmpty(String playerId) {
    if (!_roundInProgress ||
        !_tournamentStarted ||
        isComplete ||
        !_activePlayerIds.contains(playerId) ||
        _roundFinishingOrder.contains(playerId)) {
      return;
    }
    _recordFinisher(playerId);
  }

  void recordPlayerFinished(String playerId, {int? finishPosition}) {
    // finishPosition is accepted for compatibility with caller APIs;
    // finishing order is sourced from event sequence to keep state authoritative.
    if (!_roundInProgress ||
        !_tournamentStarted ||
        isComplete ||
        !_activePlayerIds.contains(playerId) ||
        _roundFinishingOrder.contains(playerId)) {
      return;
    }

    _recordFinisher(playerId);

    final stillActive =
        _activePlayerIds.where((p) => !_roundFinishingOrder.contains(p)).toList();

    if (stillActive.length == 1) {
      final lastPlayer = stillActive.first;
      _eliminatePlayer(lastPlayer);
      _endRound();
    }
  }

  int? finishingPositionFor({
    required int roundNumber,
    required String playerId,
  }) {
    return _finishingPositionByRound[roundNumber]?[playerId];
  }

  Map<String, int> liveCardCountsForRemainingPlayers() {
    final remaining = _activePlayerIds
        .where((playerId) => !_roundFinishingOrder.contains(playerId));
    final map = <String, int>{};
    for (final playerId in remaining) {
      map[playerId] = _latestCardCounts[playerId] ?? 0;
    }
    return UnmodifiableMapView<String, int>(map);
  }

  void _recordFinisher(String playerId) {
    _roundFinishingOrder.add(playerId);
    _finishingPositionByRound
        .putIfAbsent(_currentRound, () => <String, int>{})[playerId] =
        _roundFinishingOrder.length;

    if (_roundFinishingOrder.length == _activePlayerIds.length) {
      _completeRound();
    }
  }

  void _eliminatePlayer(String playerId) {
    if (_roundFinishingOrder.contains(playerId)) {
      return;
    }
    _roundFinishingOrder.add(playerId);
    _finishingPositionByRound
        .putIfAbsent(_currentRound, () => <String, int>{})[playerId] =
        _roundFinishingOrder.length;
  }

  void _endRound() {
    if (_roundFinishingOrder.length == _activePlayerIds.length) {
      _completeRound();
    }
  }

  void _completeRound() {
    final eliminated = _roundFinishingOrder.last;
    final advanced =
        _roundFinishingOrder.take(_roundFinishingOrder.length - 1).toList();

    for (var i = 0; i < advanced.length; i++) {
      _playerAdvancedController.add(PlayerAdvancedEvent(
        roundNumber: _currentRound,
        playerId: advanced[i],
        finishingPosition: i + 1,
      ));
    }

    _playerEliminatedController.add(PlayerEliminatedEvent(
      roundNumber: _currentRound,
      playerId: eliminated,
      finishingPosition: _roundFinishingOrder.length,
    ));

    final result = TournamentRoundResult(
      roundNumber: _currentRound,
      playerIdsInFinishOrder: List.unmodifiable(_roundFinishingOrder),
      advancedPlayerIds: List.unmodifiable(advanced),
      eliminatedPlayerId: eliminated,
    );
    _roundResults.add(result);
    _roundCompleteController.add(RoundCompleteEvent(result));

    _activePlayerIds = advanced;
    _roundInProgress = false;

    if (_activePlayerIds.length == 1) {
      _winnerId = _activePlayerIds.first;
      _tournamentCompleteController.add(TournamentCompleteEvent(
        winnerPlayerId: _winnerId!,
        roundResults: List.unmodifiable(_roundResults),
      ));
    }
  }

  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _playerAdvancedController.close();
    await _playerEliminatedController.close();
    await _roundCompleteController.close();
    await _tournamentCompleteController.close();
  }
}
