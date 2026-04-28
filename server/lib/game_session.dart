import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:last_cards/core/models/table_position_layout.dart';
import 'package:last_cards/shared/reactions/reaction_catalog.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/engine/shuffle_utils.dart';
import 'package:last_cards/shared/rules/move_log_support.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart'
    show mayDeclareLastCards;
import 'package:last_cards/shared/rules/win_condition_rules.dart'
    show
        canConfirmPlayerWin,
        needsUndeclaredLastCardsDraw,
        wouldConfirmWin;

import 'logger.dart';
import 'server_ai_turn.dart';
import 'trophy_recorder.dart';

// Flutter-only: Ace suit sheet UI, table animations, draw-pile visuals, floating
// action bar layout. This process validates actions and broadcasts snapshots; see
// server/docs/client-flutter-vs-server.md

// Bust mode: 52-card deck; 3+ survivors = 2 turns each per round, eliminate bottom 2;
// 2 survivors = race to empty hand (no turn-cap round end).

// ── Connected player ──────────────────────────────────────────────────────────

class _ConnectedPlayer {
  _ConnectedPlayer({
    required this.displayName,
    this.ws,
    this.firebaseUid,
    this.isAi = false,
    this.aiDifficulty = 'medium',
  });
  dynamic ws;
  final String displayName;
  final String? firebaseUid;
  bool isReady = false;
  final bool isAi;
  final String aiDifficulty;
}

// ── GameSession ───────────────────────────────────────────────────────────────

/// Authoritative server-side game session.
///
/// Responsibilities:
///   • Lobby management (add/remove players, ready-up).
///   • Game initialisation via [_startGame].
///   • Action handling: play_cards, draw_card, declare_joker, end_turn,
///     suit_choice.
///   • 60-second per-turn timer with forced draw + turn_timeout on expiry.
///   • Invalid-play draw penalty (2 cards, or full pick-up stack if active).
///   • Reshuffle when draw pile ≤ 5 cards.
///   • Win detection after every state mutation.
///   • Personalised state_snapshot broadcasts (each client sees own hand only).
// ── Rating deltas for ranked mode ─────────────────────────────────────────────

const _rankedWinDelta = 25;
const _rankedLossDelta = -15;
const _rankedLeaveDelta = -20;

class GameSession {
  GameSession(
    this.roomCode, {
    this.isPrivate = true,
    this.maxPlayerCount,
    this.isBustMode = false,
    this.isKnockoutTournament = false,
    this.isRanked = false,
    this.isHardcore = false,
    TrophyPersistence? trophyRecorder,
    this.onBecameEmpty,
  }) : _trophyRecorder = trophyRecorder ?? TrophyRecorder.instance;

  final String roomCode;

  /// True for private lobbies (create_room/join_room). False for quickplay.
  final bool isPrivate;

  /// For quickplay: the intended player count from the queue.
  /// Trophies are only earned if the game started with this many players.
  final int? maxPlayerCount;

  /// True for Bust mode: 10 players, 52-card deck, multi-round with elimination.
  final bool isBustMode;

  /// Private lobby: knockout tournament UX (finish order) on a standard table.
  /// Does not change server rules — only echoed for clients.
  final bool isKnockoutTournament;

  /// True for ranked matchmaking: enables MMR recording via [TrophyPersistence].
  final bool isRanked;

  /// Hardcore rules (stricter plays, 30s turn timer). Ranked hardcore uses
  /// `ranked_hardcore_stats`; private lobbies can enable the same rules
  /// without MMR ([isRanked] stays false).
  bool isHardcore;

  final TrophyPersistence _trophyRecorder;
  final _log = Logger('GameSession');
  final math.Random _aiRng = math.Random();

  /// Called after [removePlayer] when no players remain. [RoomManager] uses
  /// this to drop the room from memory.
  final void Function(String roomCode)? onBecameEmpty;

  final _players = <String, _ConnectedPlayer>{};

  /// Per-player timestamp of last quick chat message (server-side rate limit).
  final _lastQuickChatTime = <String, DateTime>{};

  // ── Bust round state ─────────────────────────────────────────────────────
  int _bustRoundNumber = 1;
  List<String> _bustSurvivorIds = [];
  Map<String, int> _bustTurnsThisRound = {};
  Map<String, int> _bustPenaltyPoints = {};
  List<String> _bustEliminatedIds = [];
  int _playerCounter = 0;

  /// Server-only: players who falsely declared Last Cards (not sent to clients).
  final Set<String> _lastCardsBluffedBy = {};

  late GameState _state;

  /// The actual remaining draw pile (server-authoritative).
  late List<CardModel> _drawPile;

  /// All discard pile cards except the current top card.
  /// Used for reshuffling back into the draw pile.
  final _discardUnderTop = <CardModel>[];

  bool _started = false;
  bool _gameOver = false;

  /// Set in _startGame. True if the game started with maxPlayerCount (or N/A).
  bool _wasFullRoster = false;

  /// Number of players at game start — used for bracket keys when recording
  /// disconnect wins (where _players has already shed the leaver).
  int _startingPlayerCount = 0;

  /// Per-turn countdown timer.
  Timer? _turnTimer;

  /// After an unexpected socket close during a live game, keep the seat open
  /// briefly so mobile clients can reconnect and [tryReattachSocket] succeeds.
  final Map<String, Timer> _disconnectGraceTimers = {};

  /// Wall-clock grace for [handleSocketDisconnected] (non-forced). Not tied to
  /// turn timer so other players are not blocked by a brief app switch.
  static const Duration socketDisconnectGrace = Duration(seconds: 90);

  bool get _trophyEligible =>
      !isPrivate && (maxPlayerCount == null || _wasFullRoster);

  /// Persist to `ranked_hardcore_stats` instead of `ranked_stats`.
  bool get _rankedHardcoreRecords => isRanked && isHardcore;

  Duration get _turnDuration =>
      Duration(seconds: isHardcore ? 30 : 60);

  // ── Test helpers ───────────────────────────────────────────────────────────

  /// Directly seeds the session with a known state for testing.
  ///
  /// Callers must have already added players via [addPlayer] before calling
  /// this. The [drawPile] and optional [discardUnderTop] replace the server's
  /// internal piles.
  ///
  /// For Bust mode tests, pass [bustSurvivorIds], [bustTurnsThisRound], and
  /// [bustPenaltyPoints] to seed the bust round state.
  void seedStateForTesting({
    required GameState state,
    required List<CardModel> drawPile,
    List<CardModel> discardUnderTop = const [],
    List<String>? bustSurvivorIds,
    Map<String, int>? bustTurnsThisRound,
    Map<String, int>? bustPenaltyPoints,
  }) {
    _state = state;
    _drawPile = List<CardModel>.from(drawPile);
    _discardUnderTop
      ..clear()
      ..addAll(discardUnderTop);
    _started = true;
    _gameOver = false;
    if (bustSurvivorIds != null) _bustSurvivorIds = bustSurvivorIds;
    if (bustTurnsThisRound != null) _bustTurnsThisRound = bustTurnsThisRound;
    if (bustPenaltyPoints != null) _bustPenaltyPoints = bustPenaltyPoints;
    _broadcastStateSnapshots();
  }

  /// Returns the current draw pile size (for assertions in tests).
  int get drawPileCountForTesting => _drawPile.length;

  /// Draw pile order for tests (index 0 is drawn next; bottom == last indices).
  List<CardModel> get drawPileOrderForTesting =>
      List<CardModel>.from(_drawPile);

  /// Returns the current discard-under-top size (for assertions in tests).
  int get discardUnderTopCountForTesting => _discardUnderTop.length;

  /// Current game state (for tests; matches what handlers use after seeding).
  GameState get gameStateForTesting => _state;

  /// True when there are no players left in this session (room may be discarded).
  bool get isEmpty => _players.isEmpty;

  /// Invokes the turn-timeout handler (for tests).
  void triggerTurnTimeoutForTesting() => _onTurnTimeout();

  /// Bust per-player turn counts this round (for tests).
  Map<String, int> get bustTurnsThisRoundForTesting =>
      Map<String, int>.from(_bustTurnsThisRound);

  // ── Lobby ─────────────────────────────────────────────────────────────────

  String addPlayer(dynamic ws, String displayName, {String? firebaseUid}) {
    if (_started) {
      ws.sink.add(
          '{"type":"error","code":"game_started","message":"Game already in progress."}');
      return '';
    }
    for (final entry in _players.entries) {
      if (identical(entry.value.ws, ws)) {
        return entry.key;
      }
    }
    final maxPlayers = isBustMode ? 10 : 7;
    if (_players.length >= maxPlayers) {
      ws.sink.add(
          '{"type":"error","code":"room_full","message":"Room is full (max $maxPlayers players)."}');
      return '';
    }
    final id = 'player-${++_playerCounter}';
    _players[id] = _ConnectedPlayer(
      ws: ws,
      displayName: displayName,
      firebaseUid: firebaseUid,
    );

    _broadcast({
      'type': 'player_joined',
      'player': PlayerModel(
        id: id,
        displayName: displayName,
        tablePosition: _positionFor(_players.length - 1),
        cardCount: 0,
        firebaseUid: firebaseUid,
        isAi: false,
      ).toJson(),
    });

    return id;
  }

  /// Private lobby: host adds a server-controlled bot seat (standard, knockout, bust).
  void addPrivateLobbyBot(String requesterId, {String aiDifficulty = 'medium'}) {
    if (_started) {
      _sendError(
          requesterId, 'game_started', 'Game already in progress.');
      return;
    }
    if (!isPrivate) {
      _sendError(requesterId, 'invalid_action', 'Bots are not available here.');
      return;
    }
    final host = hostPlayerIdForPrivateLobby;
    if (host == null || requesterId != host) {
      _sendError(
          requesterId, 'not_host', 'Only the room host can add bots.');
      return;
    }
    final maxPlayers = isBustMode ? 10 : 7;
    if (_players.length >= maxPlayers) {
      _sendError(
          requesterId, 'room_full', 'Room is full (max $maxPlayers players).');
      return;
    }
    if (!_players.values.any((p) => !p.isAi)) {
      _sendError(requesterId, 'invalid_action',
          'At least one human player is required before adding bots.');
      return;
    }
    final id = 'player-${++_playerCounter}';
    final botNum = _players.values.where((p) => p.isAi).length + 1;
    final bot = _ConnectedPlayer(
      displayName: 'Bot $botNum',
      isAi: true,
      aiDifficulty: aiDifficulty,
    );
    bot.isReady = true;
    _players[id] = bot;

    // Replay the full roster to every connected client so lobby UIs stay in
    // sync (single player_joined frames can be dropped on flaky links).
    for (final entry in _players.entries) {
      final w = entry.value.ws;
      if (w == null) continue;
      sendPlayerRosterTo(w);
    }
    _broadcast({'type': 'player_ready', 'playerId': id});
  }

  /// Removes a bot added for the private lobby (host only, pre-game).
  void removePrivateLobbyBot(String requesterId, String botPlayerId) {
    if (_started) {
      _sendError(
          requesterId, 'game_started', 'Game already in progress.');
      return;
    }
    if (!isPrivate) return;
    final host = hostPlayerIdForPrivateLobby;
    if (host == null || requesterId != host) {
      _sendError(
          requesterId, 'not_host', 'Only the room host can remove bots.');
      return;
    }
    final bot = _players[botPlayerId];
    if (bot == null || !bot.isAi) {
      _sendError(requesterId, 'invalid_action', 'Not a bot player.');
      return;
    }
    _players.remove(botPlayerId);
    _broadcast({'type': 'player_left', 'playerId': botPlayerId});
  }

  /// Called when a client's socket closes.
  ///
  /// [disconnectedWs] must be the socket that closed. If [tryReattachSocket]
  /// already replaced it, this is ignored so a late close on the old socket
  /// does not clear the new connection.
  ///
  /// When [forceRemove] is true (e.g. the client is joining another room on
  /// the same process), the player is removed immediately. Otherwise, during
  /// an active standard or bust game, the seat is kept for [socketDisconnectGrace]
  /// so the client can [rejoin_session] after a brief disconnect (mobile
  /// backgrounding).
  void handleSocketDisconnected(
    String playerId,
    dynamic disconnectedWs, {
    bool forceRemove = false,
  }) {
    final leavingPlayer = _players[playerId];
    if (leavingPlayer == null) return;

    if (leavingPlayer.ws != null &&
        !identical(leavingPlayer.ws, disconnectedWs)) {
      return;
    }

    if (forceRemove ||
        !_started ||
        _gameOver ||
        leavingPlayer.isAi) {
      _cancelDisconnectGraceTimer(playerId);
      removePlayer(playerId);
      return;
    }

    _cancelDisconnectGraceTimer(playerId);
    leavingPlayer.ws = null;
    _broadcast({
      'type': 'player_socket_lost',
      'playerId': playerId,
    });
    _disconnectGraceTimers[playerId] = Timer(socketDisconnectGrace, () {
      _disconnectGraceTimers.remove(playerId);
      final p = _players[playerId];
      if (p == null) return;
      if (p.ws != null) return;
      removePlayer(playerId);
    });

    if (_started &&
        !_gameOver &&
        _state.currentPlayerId == playerId) {
      _startTurnTimer();
    }
  }

  void _cancelDisconnectGraceTimer(String playerId) {
    _disconnectGraceTimers.remove(playerId)?.cancel();
  }

  void _cancelAllDisconnectGraceTimers() {
    for (final t in _disconnectGraceTimers.values) {
      t.cancel();
    }
    _disconnectGraceTimers.clear();
  }

  /// Replaces the live WebSocket when the same client sends [rejoin_session],
  /// including after a brief disconnect while the grace window in
  /// [handleSocketDisconnected] still holds the seat.
  bool tryReattachSocket(
    String playerId,
    dynamic newWs, {
    String? firebaseUidFromToken,
  }) {
    final p = _players[playerId];
    if (p == null) return false;
    if (p.isAi) return false;

    if (isRanked) {
      final expected = p.firebaseUid;
      if (expected != null) {
        if (firebaseUidFromToken == null ||
            firebaseUidFromToken != expected) {
          return false;
        }
      }
    }

    _cancelDisconnectGraceTimer(playerId);

    final oldWs = p.ws;
    if (oldWs != null) {
      try {
        oldWs.sink.close();
      } catch (_) {}
    }
    p.ws = newWs;
    _broadcast({
      'type': 'player_socket_restored',
      'playerId': playerId,
    });
    _broadcastStateSnapshots();
    return true;
  }

  /// Sends player_joined for every current player to [ws].
  /// Used after quickplay matching so late-joining clients learn about
  /// players that were added before them.
  void sendPlayerRosterTo(dynamic ws) {
    int index = 0;
    for (final entry in _players.entries) {
      ws.sink.add(jsonEncode({
        'type': 'player_joined',
        'player': PlayerModel(
          id: entry.key,
          displayName: entry.value.displayName,
          tablePosition: _positionFor(index),
          cardCount: 0,
          firebaseUid: entry.value.firebaseUid,
          isAi: entry.value.isAi,
        ).toJson(),
      }));
      index++;
    }
  }

  /// Drops the whole session when every remaining seat is an AI bot (or empty).
  /// Call after mutating [_players] so the room is not left running with bots only.
  bool _clearRoomWhenNoHumansRemain() {
    if (_players.values.any((p) => !p.isAi)) return false;
    _turnTimer?.cancel();
    if (_started) {
      _cancelAllDisconnectGraceTimers();
      _gameOver = true;
    }
    _players.clear();
    onBecameEmpty?.call(roomCode);
    return true;
  }

  /// Returns the leaver's cards to the **bottom** of the draw pile (append;
  /// index 0 is still drawn first) for standard mode — same for grace expiry and
  /// forced/immediate removal.
  void removePlayer(String playerId) {
    final leavingPlayer = _players[playerId];
    if (leavingPlayer == null) return;

    _cancelDisconnectGraceTimer(playerId);

    final firebaseUid = leavingPlayer.firebaseUid;
    final displayName = leavingPlayer.displayName;
    final wasCurrentBefore = _started &&
        !_gameOver &&
        !isBustMode &&
        _state.currentPlayerId == playerId;
    _players.remove(playerId);
    _broadcast({'type': 'player_left', 'playerId': playerId});

    if (_clearRoomWhenNoHumansRemain()) {
      return;
    }

    if (!_started || _gameOver) return;

    if (isBustMode) {
      _removePlayerFromBustInProgress(
        playerId: playerId,
        firebaseUid: firebaseUid,
        displayName: displayName,
      );
      return;
    }

    final continueGame = removeDisconnectedStandardPlayer(
      state: _state,
      removedPlayerId: playerId,
      authoritativeDrawPile: _drawPile,
      authoritativeDiscardUnderTop: _discardUnderTop,
      authoritativeDiscardTop: _state.discardTopCard,
    );

    if (continueGame == null || _players.length < 2) {
      _endGameForDisconnect(
        disconnectedPlayerId: playerId,
        firebaseUid: firebaseUid,
        displayName: displayName,
      );
      return;
    }

    _lastCardsBluffedBy.remove(playerId);
    _lastQuickChatTime.remove(playerId);

    if (_trophyEligible && isRanked) {
      final uid = firebaseUid ?? playerId;
      _trophyRecorder.recordLeavePenalty(uid,
          displayName: displayName, rankedHardcore: _rankedHardcoreRecords);
    }

    _drawPile.addAll(continueGame.handForDrawPile);
    _state = continueGame.state.copyWith(drawPileCount: _drawPile.length);

    _checkWin();
    if (_gameOver) return;

    _broadcastStateSnapshots();
    if (wasCurrentBefore) {
      _broadcast({
        'type': 'turn_changed',
        'currentPlayerId': _state.currentPlayerId,
        'direction': _state.direction.name,
      });
      _startTurnTimer();
    }
  }

  /// Standard (non-Bust): end the session after a leave when fewer than two
  /// players remain or the roster could not be updated.
  void _endGameForDisconnect({
    required String disconnectedPlayerId,
    required String? firebaseUid,
    required String displayName,
  }) {
    _turnTimer?.cancel();
    _cancelAllDisconnectGraceTimers();
    _gameOver = true;

    final trophyPenaltyForLeaver = _trophyEligible;
    if (trophyPenaltyForLeaver && isRanked) {
      final uid = firebaseUid ?? disconnectedPlayerId;
      _trophyRecorder.recordLeavePenalty(uid,
          displayName: displayName, rankedHardcore: _rankedHardcoreRecords);

      // Also record ranked wins for every player who is still connected.
      // The leaver's penalty is already handled by recordLeavePenalty above;
      // without this call the remaining players' wins were silently dropped.
      final remainingUids = _players.entries
          .map((e) => (
                playerId: e.key,
                uid: e.value.firebaseUid ?? e.key,
                displayName: e.value.displayName,
              ))
          .toList();
      if (remainingUids.isNotEmpty) {
        // All remaining players are treated as winners.  For a 1v1 game there
        // is exactly one; for sessions that somehow reach this path with more
        // survivors the first connected player is the canonical winner so the
        // bracket stats stay balanced.
        final winnerUid = remainingUids.first.uid;
        _trophyRecorder.recordRankedResult(
          winnerUid: winnerUid,
          allPlayerUids: remainingUids,
          playerCount: _startingPlayerCount,
          rankedHardcore: _rankedHardcoreRecords,
        );
      }
    }

    Map<String, int>? ratingChanges;
    if (trophyPenaltyForLeaver && isRanked) {
      ratingChanges = {
        disconnectedPlayerId: _rankedLeaveDelta,
        for (final p in _state.players)
          if (p.id != disconnectedPlayerId) p.id: _rankedWinDelta,
      };
    }

    final remainingIds = _players.keys.toSet();
    final prunedPlayers =
        _state.players.where((p) => remainingIds.contains(p.id)).toList();

    _state = _state.copyWith(
      phase: GamePhase.ended,
      players: prunedPlayers,
    );

    _broadcast({
      'type': 'game_ended',
      'winnerId': '',
      'reason': 'player_disconnected',
      'disconnectedPlayerId': disconnectedPlayerId,
      'trophyPenaltyForLeaver': trophyPenaltyForLeaver,
      if (ratingChanges != null) 'ratingChanges': ratingChanges,
    });
    // Authoritative ended snapshot so clients never sit in a playing state until
    // the turn timer fires; also syncs draw pile / roster with pruned players.
    _broadcastStateSnapshots();

    if (!_players.values.any((p) => !p.isAi)) {
      _players.clear();
      onBecameEmpty?.call(roomCode);
    }
  }

  /// Bust: drop the leaver from the table; continue if more than 2 survivors remain.
  void _removePlayerFromBustInProgress({
    required String playerId,
    required String? firebaseUid,
    required String displayName,
  }) {
    if (_clearRoomWhenNoHumansRemain()) {
      return;
    }

    _bustSurvivorIds.remove(playerId);
    _bustTurnsThisRound.remove(playerId);
    _bustPenaltyPoints.remove(playerId);
    if (!_bustEliminatedIds.contains(playerId)) {
      _bustEliminatedIds.add(playerId);
    }

    if (_bustSurvivorIds.length <= 2) {
      _endGameForDisconnect(
        disconnectedPlayerId: playerId,
        firebaseUid: firebaseUid,
        displayName: displayName,
      );
      return;
    }

    final oldState = _state;
    final newPlayers =
        oldState.players.where((p) => p.id != playerId).toList();
    if (newPlayers.isEmpty) {
      _endGameForDisconnect(
        disconnectedPlayerId: playerId,
        firebaseUid: firebaseUid,
        displayName: displayName,
      );
      return;
    }

    final wasCurrent = oldState.currentPlayerId == playerId;
    if (wasCurrent) {
      final nextCurrent = nextPlayerId(state: oldState);
      final s = oldState.copyWith(players: newPlayers);
      _state = advanceTurn(s, nextId: nextCurrent);
    } else {
      _state = oldState.copyWith(players: newPlayers);
    }

    if (_isBustRoundComplete()) {
      _finalizeBustRound();
      return;
    }

    if (wasCurrent) {
      _broadcast({
        'type': 'turn_changed',
        'currentPlayerId': _state.currentPlayerId,
        'direction': _state.direction.name,
      });
    }

    _broadcastStateSnapshots();
    _startTurnTimer();
  }

  void markReady(String playerId) {
    final player = _players[playerId];
    if (player != null) player.isReady = true;

    _broadcast({'type': 'player_ready', 'playerId': playerId});

    if (_players.length >= 2 &&
        _players.values.every((p) => p.isAi || p.isReady) &&
        _players.values.any((p) => !p.isAi) &&
        !_started) {
      _startGame();
    }
  }

  /// Private lobbies: lowest-numbered `player-N` id among **human** players
  /// (first joiner still present) is the host and may call [startGameFromHost].
  String? get hostPlayerIdForPrivateLobby {
    String? bestId;
    int? bestN;
    for (final id in _players.keys) {
      if (_players[id]?.isAi == true) continue;
      final match = RegExp(r'^player-(\d+)$').firstMatch(id);
      if (match == null) continue;
      final n = int.parse(match.group(1)!);
      if (bestN == null || n < bestN) {
        bestN = n;
        bestId = id;
      }
    }
    return bestId;
  }

  /// Host-only: starts the match with the current roster (minimum 2 players).
  /// Does not require every player to have pressed Ready.
  void startGameFromHost(String playerId) {
    if (_started) {
      _sendError(
          playerId, 'game_started', 'Game already in progress.');
      return;
    }
    if (!isPrivate) {
      _sendError(playerId, 'invalid_action',
          'Host start is only available in private rooms.');
      return;
    }
    final host = hostPlayerIdForPrivateLobby;
    if (host == null || playerId != host) {
      _sendError(
          playerId, 'not_host', 'Only the room host can start the game.');
      return;
    }
    if (_players.length < 2) {
      _sendError(playerId, 'not_enough_players',
          'Need at least 2 players to start.');
      return;
    }
    if (!_players.values.any((p) => !p.isAi)) {
      _sendError(playerId, 'not_enough_players',
          'At least one human player is required.');
      return;
    }
    _startGame();
  }

  /// Private lobbies only: host may toggle hardcore rules before the match.
  void setPrivateLobbyHardcore(String playerId, bool hardcore) {
    if (!isPrivate || _started) return;
    final host = hostPlayerIdForPrivateLobby;
    if (host == null || playerId != host) {
      _sendError(
        playerId,
        'not_host',
        'Only the room host can change game rules.',
      );
      return;
    }
    if (isHardcore == hardcore) return;
    isHardcore = hardcore;
    _broadcast({
      'type': 'private_lobby_settings',
      'isHardcore': isHardcore,
    });
  }

  // ── Game start ────────────────────────────────────────────────────────────

  void _startGame() {
    _started = true;
    _gameOver = false;
    _wasFullRoster =
        maxPlayerCount == null || _players.length >= maxPlayerCount!;
    _startingPlayerCount = _players.length;

    final entries = _players.entries.toList();
    final totalPlayers = entries.length;

    final List<CardModel> deck;
    final int handSize;
    if (isBustMode) {
      deck = buildBustDeck(seed: DateTime.now().millisecondsSinceEpoch);
      handSize = handSizeForBust(totalPlayers);
      _bustSurvivorIds = entries.map((e) => e.key).toList();
      _bustTurnsThisRound = {for (final e in entries) e.key: 0};
      _bustPenaltyPoints = {for (final e in entries) e.key: 0};
      _bustEliminatedIds = [];
      _bustRoundNumber = 1;
    } else {
      deck = buildShuffledDeck();
      handSize = 7;
    }

    int idx = 0;
    final playerModels = <PlayerModel>[];
    for (int i = 0; i < totalPlayers; i++) {
      final hand = deck.sublist(idx, idx + handSize);
      idx += handSize;
      playerModels.add(PlayerModel(
        id: entries[i].key,
        displayName: entries[i].value.displayName,
        tablePosition: _positionFor(i),
        hand: hand,
        cardCount: hand.length,
        firebaseUid: entries[i].value.firebaseUid,
        isAi: entries[i].value.isAi,
      ));
    }

    final discardTop = deck[idx];
    idx++;
    _drawPile = List<CardModel>.from(deck.sublist(idx));
    _discardUnderTop.clear();

    _state = GameState(
      sessionId: roomCode,
      phase: GamePhase.playing,
      players: playerModels,
      currentPlayerId: playerModels.first.id,
      direction: PlayDirection.clockwise,
      discardTopCard: discardTop,
      drawPileCount: _drawPile.length,
      isHardcore: isHardcore,
      // preTurnCentreSuit is set after applyInitialFaceUpEffect below.
    );

    // Apply the opening face-up card's special effect (2, Jack, King, Queen,
    // Ace, 8, Joker all have start-of-game consequences).
    _state = applyInitialFaceUpEffect(state: _state);

    // If the opening card was an 8 (skip), advance past the first player.
    if (_state.activeSkipCount > 0) {
      final skippedId = nextPlayerId(state: _state);
      _state = _state.copyWith(
        currentPlayerId: skippedId,
        activeSkipCount: 0,
        preTurnCentreSuit: _state.discardTopCard?.effectiveSuit,
      );
    } else {
      _state = _state.copyWith(
        preTurnCentreSuit: _state.discardTopCard?.effectiveSuit,
      );
    }

    _state = initializeFirstTurnClearability(_state, isBustMode: isBustMode);

    // Notify clients of session type (private vs ranked, trophy eligibility).
    _broadcast({
      'type': 'session_config',
      'roomCode': roomCode,
      'isPrivate': isPrivate,
      'isRanked': isRanked,
      'isHardcore': isHardcore,
      'isBustMode': isBustMode,
      'isKnockoutTournament': isKnockoutTournament,
      'trophyEligible': _trophyEligible,
    });
    _aiDeclareLastCardsIfNeeded();
    _seedOpeningCurrentPlayerLastCardsIfNoOffTurnWindowYet();
    _broadcastStateSnapshots();
    _startTurnTimer();
  }

  // ── Action dispatch ───────────────────────────────────────────────────────

  void handleAction(String playerId, Map<String, dynamic> json) {
    if (!_started || _gameOver) return;
    final type = json['type'] as String;

    switch (type) {
      case 'play_cards':
        _handlePlayCards(playerId, json);
      case 'draw_card':
        _handleDrawCard(playerId);
      case 'declare_joker':
        _handleDeclareJoker(playerId, json);
      case 'end_turn':
        _handleEndTurn(playerId);
      case 'suit_choice':
        _handleSuitChoice(playerId, json);
      case 'declare_last_cards':
        _handleDeclareLastCards(playerId);
    }
  }

  // ── play_cards ────────────────────────────────────────────────────────────

  void _handlePlayCards(String playerId, Map<String, dynamic> json) {
    if (_state.currentPlayerId != playerId) {
      _sendError(playerId, 'not_your_turn', 'It is not your turn.');
      return;
    }

    final cardIds = (json['cardIds'] as List).cast<String>();
    final player = _state.playerById(playerId);
    if (player == null) return;

    // Resolve card objects from the player's hand.
    final List<CardModel> cards = [];
    for (final id in cardIds) {
      final card = player.hand.firstWhereOrNull((c) => c.id == id);
      if (card == null) {
        _sendError(playerId, 'invalid_card', 'Card $id not found in hand.');
        return;
      }
      cards.add(card);
    }

    if (cards.any((c) => c.rank == Rank.joker)) {
      _sendError(
        playerId,
        'joker_must_declare',
        'Jokers must use the declare_joker action.',
      );
      return;
    }

    final err = validatePlay(
      cards: cards,
      discardTop: _state.discardTopCard!,
      state: _state,
    );

    if (err != null) {
      // Invalid play: send error and apply draw penalty (2 cards, or full stack
      // if a pick-up penalty is active — see [applyInvalidPlayPenalty]).
      _sendError(playerId, 'invalid_play', err);
      _applyInvalidPlayPenalty(playerId);
      return;
    }

    final declaredSuitStr = json['declaredSuit'] as String?;
    final declaredSuit =
        declaredSuitStr != null ? Suit.values.byName(declaredSuitStr) : null;

    // If an Ace is played as the first card of the turn and no suit was
    // declared in this message, ask the client to choose one.
    final isWildAce = cards.length == 1 &&
        cards.first.effectiveRank == Rank.ace &&
        _state.actionsThisTurn == 0;
    if (isWildAce && declaredSuit == null) {
      // Apply the play without a suit lock for now; the suit_choice response
      // will lock it. We still need to track the card as played.
      final skipBefore = _state.activeSkipCount;
      final dirBefore = _state.direction;
      _pushDiscardUnderTop();
      _state = applyPlay(state: _state, playerId: playerId, cards: cards);
      _checkBustPlacementPileRule();

      _broadcastCardPlayed(
        playerId: playerId,
        cards: cards,
        activeSkipBefore: skipBefore,
        directionBefore: dirBefore,
      );

      // Ask the acting player to choose a suit.
      _sendTo(playerId, {
        'type': 'suit_choice_required',
        'cardId': cards.first.id,
      });

      _checkWin();
      _broadcastStateSnapshots();
      if (_gameOver) return;
      if (_players[playerId]?.isAi == true) {
        final suit = Suit.values[_aiRng.nextInt(Suit.values.length)];
        _handleSuitChoice(playerId, {
          'type': 'suit_choice',
          'suit': suit.name,
        });
      }
      return;
    }

    final skipBefore = _state.activeSkipCount;
    final dirBefore = _state.direction;
    _pushDiscardUnderTop();
    _state = applyPlay(
      state: _state,
      playerId: playerId,
      cards: cards,
      declaredSuit: declaredSuit,
    );
    _checkBustPlacementPileRule();

    _broadcastCardPlayed(
      playerId: playerId,
      cards: cards,
      activeSkipBefore: skipBefore,
      directionBefore: dirBefore,
    );

    _checkWin();
    if (!_maybeAutoAdvanceSamePlayerAfterPlay(playerId)) {
      _broadcastStateSnapshots();
      if (_players[playerId]?.isAi == true) {
        _startTurnTimer();
      }
    }
  }

  // ── suit_choice ───────────────────────────────────────────────────────────

  void _handleSuitChoice(String playerId, Map<String, dynamic> json) {
    if (_state.currentPlayerId != playerId) return;

    if (_state.discardTopCard?.effectiveRank != Rank.ace ||
        _state.cardsPlayedThisTurn != 1 ||
        _state.suitLock != null) {
      _sendError(playerId, 'invalid_action', 'No suit choice required.');
      return;
    }

    final suitStr = json['suit'] as String?;
    if (suitStr == null) return;
    final suit = Suit.values.byName(suitStr);

    // Lock the declared suit onto the current state.
    _state = _state.copyWith(suitLock: suit);
    _broadcastStateSnapshots();
    if (_players[playerId]?.isAi == true) {
      _startTurnTimer();
    }
  }

  // ── draw_card ─────────────────────────────────────────────────────────────

  void _handleDrawCard(String playerId) {
    if (_state.currentPlayerId != playerId) {
      _sendError(playerId, 'not_your_turn', 'It is not your turn.');
      return;
    }

    // A player's turn consists of ONE action — either playing OR drawing.
    // If they have already played a card this turn, the draw action is blocked.
    // EXCEPTION: If there is a Queen suit lock, they MUST draw if they cannot play.
    if (_state.actionsThisTurn > 0 && _state.queenSuitLock == null) {
      _sendError(
          playerId, 'already_acted', 'You have already acted this turn.');
      return;
    }

    final count = _state.activePenaltyCount > 0 ? _state.activePenaltyCount : 1;

    final drawnCards = <CardModel>[];
    _state = applyDraw(
      state: _state,
      playerId: playerId,
      count: count,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawnCards.addAll(cards);
        return cards;
      },
    );

    // Send the actual drawn cards only to the drawing player.
    for (final card in drawnCards) {
      _sendTo(playerId, {
        'type': 'card_drawn',
        'playerId': playerId,
        'card': card.toJson(),
      });
    }

    // Other players see one draw event per card (without card details) so
    // their GameNotifier decrements drawPileCount correctly.
    for (final entry in _players.entries) {
      if (entry.key != playerId) {
        final w = entry.value.ws;
        if (w == null) continue;
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': playerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          w.sink.add(encoded);
        }
      }
    }

    if (count > 1) {
      _broadcast({
        'type': 'penalty_applied',
        'targetPlayerId': playerId,
        'cardsDrawn': count,
        'newPenaltyStack': 0,
      });
    }

    _broadcastStateSnapshots();

    // Deferred win: opponent may have emptied on a pick-up; the chain clears
    // only when this draw runs. Mirrors play_cards / joker paths that call
    // [_checkWin] after mutating state.
    final drawerId = playerId;
    _checkWin();
    if (_gameOver) return;
    if (_state.currentPlayerId != drawerId) {
      // Undeclared Last Cards path advanced the turn inside [_checkWin].
      return;
    }

    // A draw always ends the turn — mirrors offline mode where every draw
    // (voluntary or penalty) immediately advances to the next player.
    _advanceTurn();
  }

  // ── declare_joker ─────────────────────────────────────────────────────────

  void _handleDeclareJoker(String playerId, Map<String, dynamic> json) {
    if (_state.currentPlayerId != playerId) {
      _sendError(playerId, 'not_your_turn', 'It is not your turn.');
      return;
    }

    final declaredSuit = Suit.values.byName(json['declaredSuit'] as String);
    final declaredRank = Rank.values.byName(json['declaredRank'] as String);
    final jokerCardId = json['jokerCardId'] as String;

    final player = _state.playerById(playerId);
    if (player == null) return;

    final jokerCard = player.hand.firstWhereOrNull((c) => c.id == jokerCardId);
    if (jokerCard == null) {
      _sendError(playerId, 'invalid_card', 'Joker $jokerCardId not in hand.');
      return;
    }

    if (_state.isHardcore && player.hand.length == 1) {
      _sendError(
        playerId,
        'hardcore_joker_last',
        'Hardcore: cannot play a Joker as your last card.',
      );
      return;
    }

    final top = _state.discardTopCard;
    if (top == null) {
      _sendError(playerId, 'invalid_joker', 'Invalid Joker declaration.');
      return;
    }
    final jokerIn =
        resolveJokerPlayInputs(state: _state, discardTop: top);
    // Pass raw [jokerIn.resolvedContext] so [getValidJokerOptions] can apply the
    // 2-player King → turn-starter upgrade internally (do not pass
    // [jokerIn.effectivePlayContext] here).
    final validOptions = getValidJokerOptions(
      state: _state,
      discardTop: top,
      context: jokerIn.resolvedContext,
      contextTopCard: jokerIn.anchor,
    );
    final declarationOk = validOptions.any(
      (c) => c.suit == declaredSuit && c.rank == declaredRank,
    );
    if (!declarationOk) {
      _sendError(playerId, 'invalid_joker', 'Invalid Joker declaration.');
      return;
    }

    final skipBefore = _state.activeSkipCount;
    final dirBefore = _state.direction;
    _pushDiscardUnderTop();
    _state = beginJokerPlay(
      state: _state,
      playerId: playerId,
      jokerCard: jokerCard,
    );

    final resolvedCard = CardModel(
      id: jokerCardId,
      rank: Rank.joker,
      suit: jokerCard.suit,
      jokerDeclaredSuit: declaredSuit,
      jokerDeclaredRank: declaredRank,
    );
    _state = resolveJokerPlay(
      state: _state,
      resolvedJokerCard: resolvedCard,
    );
    _checkBustPlacementPileRule();

    _broadcastCardPlayed(
      playerId: playerId,
      cards: [resolvedCard],
      activeSkipBefore: skipBefore,
      directionBefore: dirBefore,
    );

    _checkWin();
    if (!_maybeAutoAdvanceSamePlayerAfterPlay(playerId)) {
      _broadcastStateSnapshots();
      if (_players[playerId]?.isAi == true) {
        _startTurnTimer();
      }
    }
  }

  // ── end_turn ──────────────────────────────────────────────────────────────

  void _handleEndTurn(String playerId) {
    if (_state.currentPlayerId != playerId) {
      _sendError(playerId, 'not_your_turn', 'It is not your turn.');
      return;
    }

    final err = validateEndTurn(_state);
    if (err != null) {
      _sendError(playerId, 'invalid_end_turn', err);
      return;
    }

    _advanceTurn();
  }

  void _handleDeclareLastCards(String playerId) {
    if (isBustMode) return;
    if (_state.lastCardsDeclaredBy.contains(playerId)) return;
    if (!mayDeclareLastCards(
        currentPlayerId: _state.currentPlayerId, playerId: playerId)) {
      _sendError(
        playerId,
        'last_cards_own_turn',
        'Declare Last Cards when it is not your turn.',
      );
      return;
    }

    final player = _state.players.firstWhereOrNull((p) => p.id == playerId);
    if (player == null) return;

    _state = _state.copyWith(
      lastCardsDeclaredBy: {..._state.lastCardsDeclaredBy, playerId},
    );

    final hasJoker = player.hand.any((c) => c.isJoker);
    if (!hasJoker &&
        !canClearHandInOneTurn(
          state: _state,
          playerId: playerId,
          isBustMode: isBustMode,
        )) {
      _lastCardsBluffedBy.add(playerId);
    }

    _broadcast({
      'type': 'last_cards_pressed',
      'playerId': playerId,
    });
    _broadcastStateSnapshots();
  }

  void _applyLastCardsBluffPenalty(String nextPlayerId) {
    final name = _players[nextPlayerId]?.displayName ?? nextPlayerId;
    _lastCardsBluffedBy.remove(nextPlayerId);
    _state = _state.copyWith(
      lastCardsDeclaredBy: {..._state.lastCardsDeclaredBy}..remove(nextPlayerId),
    );

    final drawnCards = <CardModel>[];
    _state = applyLastCardsBluffPenaltyDraw(
      state: _state,
      playerId: nextPlayerId,
      count: 2,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawnCards.addAll(cards);
        return cards;
      },
    );

    _broadcast({
      'type': 'last_cards_bluff',
      'playerId': nextPlayerId,
      'playerName': name,
      'drawCount': drawnCards.length,
    });

    for (final card in drawnCards) {
      _sendTo(nextPlayerId, {
        'type': 'card_drawn',
        'playerId': nextPlayerId,
        'card': card.toJson(),
      });
    }
    for (final entry in _players.entries) {
      if (entry.key != nextPlayerId) {
        final w = entry.value.ws;
        if (w == null) continue;
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': nextPlayerId,
        });
        for (var i = 0; i < drawnCards.length; i++) {
          w.sink.add(encoded);
        }
      }
    }

    _broadcast({
      'type': 'penalty_applied',
      'targetPlayerId': nextPlayerId,
      'cardsDrawn': drawnCards.length,
      'newPenaltyStack': _state.activePenaltyCount,
    });
  }

  void _applyUndeclaredLastCardsDrawAndEndTurn(String playerId) {
    final drawn = <CardModel>[];
    _state = applyUndeclaredLastCardsDraw(
      state: _state,
      playerId: playerId,
      isBustMode: false,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawn.addAll(cards);
        return cards;
      },
    );

    _sendTo(playerId, {
      'type': 'error',
      'code': 'last_cards_required',
      'message': 'You must declare Last Cards before winning!',
    });

    for (final card in drawn) {
      _sendTo(playerId, {
        'type': 'card_drawn',
        'playerId': playerId,
        'card': card.toJson(),
      });
    }
    for (final entry in _players.entries) {
      if (entry.key != playerId) {
        final w = entry.value.ws;
        if (w == null) continue;
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': playerId,
        });
        for (var i = 0; i < drawn.length; i++) {
          w.sink.add(encoded);
        }
      }
    }

    _broadcast({
      'type': 'penalty_applied',
      'targetPlayerId': playerId,
      'cardsDrawn': drawn.length,
      'newPenaltyStack': _state.activePenaltyCount,
    });

    _broadcastStateSnapshots();
    _advanceTurn();
  }

  /// When [nextPlayerId] resolves to the same seat as [playerId] (e.g. Skip/8 or
  /// King in 2-player), the offline client resets per-turn fields so the next card
  /// is validated as the first card of a fresh turn, **without** removing that
  /// player from [GameState.lastCardsDeclaredBy]. Do not use [advanceTurn] here:
  /// when outgoing and incoming are the same seat, [advanceTurn] incorrectly drops
  /// the player from [lastCardsDeclaredBy].
  ///
  /// Returns true if `turn_changed` and snapshots were broadcast (and the turn
  /// timer restarted), or if Bust mode ended the round early from this path.
  bool _maybeAutoAdvanceSamePlayerAfterPlay(String playerId) {
    if (_gameOver) return false;
    if (_state.currentPlayerId != playerId) return false;
    if (_state.queenSuitLock != null) return false;
    if (nextPlayerId(state: _state) != playerId) return false;
    _sameSeatFreshTurnAfterSkipOrKing(playerId);
    return true;
  }

  /// Same-seat “new turn” after skip/King wrap: mirrors offline
  /// `table_screen` copyWith (preserves [lastCardsDeclaredBy]), not [advanceTurn].
  void _sameSeatFreshTurnAfterSkipOrKing(String playerId) {
    final completedPlayerId = _state.currentPlayerId;
    final oldSkipCount = _state.activeSkipCount;
    final playersOrder = _state.players;
    final directionForWalk = _state.direction;

    if (!isBustMode) {
      final nextId = nextPlayerId(state: _state);
      if (_lastCardsBluffedBy.contains(nextId)) {
        _applyLastCardsBluffPenalty(nextId);
      }
      _lastCardsBluffedBy.remove(completedPlayerId);
    }

    final lastCard = _state.lastPlayedThisTurn;
    final lastWasPenalty = lastCard != null &&
        (lastCard.effectiveRank == Rank.two ||
            lastCard.effectiveRank == Rank.jack);

    final base = _state.copyWith(
      currentPlayerId: playerId,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
      lastPlayedThisTurn: null,
      activeSkipCount: 0,
      preTurnCentreSuit: _state.discardTopCard?.effectiveSuit,
      queenSuitLock: null,
      penaltyChainLive: lastWasPenalty ? _state.penaltyChainLive : false,
    );

    final updatedPlayers = base.players.map((p) {
      if (p.id != playerId) {
        return p.copyWith(lastCardsHandWasClearableAtTurnStart: false);
      }
      final clearable = canClearHandInOneTurn(
        state: base,
        playerId: playerId,
      );
      return p.copyWith(lastCardsHandWasClearableAtTurnStart: clearable);
    }).toList();

    _state = base.copyWith(players: updatedPlayers);

    if (isBustMode) {
      _bustTurnsThisRound[completedPlayerId] =
          (_bustTurnsThisRound[completedPlayerId] ?? 0) + 1;

      if (oldSkipCount > 0) {
        final currentIdx =
            playersOrder.indexWhere((p) => p.id == completedPlayerId);
        if (currentIdx >= 0) {
          final step =
              directionForWalk == PlayDirection.clockwise ? 1 : -1;
          var idx = currentIdx;
          for (var safety = playersOrder.length; safety > 0; safety--) {
            idx = (idx + step) % playersOrder.length;
            if (idx < 0) idx += playersOrder.length;
            final pid = playersOrder[idx].id;
            if (pid == playerId) break;
            _bustTurnsThisRound[pid] = (_bustTurnsThisRound[pid] ?? 0) + 1;
          }
        }
      }

      if (_isBustRoundComplete()) {
        _finalizeBustRound();
        return;
      }

      if (_bustSurvivorIds.length == 2) {
        for (final id in _bustSurvivorIds) {
          if (canConfirmPlayerWin(
            state: _state,
            playerId: id,
            skipLastCardsCheck: true,
          )) {
            _completeBustFinalShowdown(id);
            return;
          }
        }
      }
    }

    _broadcast({
      'type': 'turn_changed',
      'currentPlayerId': _state.currentPlayerId,
      'direction': _state.direction.name,
    });

    _broadcastStateSnapshots();
    _aiDeclareLastCardsIfNeeded();
    _startTurnTimer();
  }

  // ── Turn advancement (shared by end_turn and timeout) ─────────────────────

  /// Advances to the next player, broadcasts turn_changed, resets timer.
  /// In Bust mode, records turns and finalizes the round when complete.
  void _advanceTurn() {
    final completedPlayerId = _state.currentPlayerId;
    final oldSkipCount = _state.activeSkipCount;
    final players = _state.players;
    final directionForWalk = _state.direction;

    if (!isBustMode) {
      final nextId = nextPlayerId(state: _state);
      if (_lastCardsBluffedBy.contains(nextId)) {
        _applyLastCardsBluffPenalty(nextId);
      }
      _lastCardsBluffedBy.remove(completedPlayerId);
    }

    _state = advanceTurn(_state);
    final newCurrentId = _state.currentPlayerId;

    if (isBustMode) {
      _bustTurnsThisRound[completedPlayerId] =
          (_bustTurnsThisRound[completedPlayerId] ?? 0) + 1;

      // Skipped players never "take" a turn, but each still consumes one of
      // the two required turns per round — mirror offline [_recordSkippedTurns].
      if (oldSkipCount > 0) {
        final currentIdx =
            players.indexWhere((p) => p.id == completedPlayerId);
        if (currentIdx >= 0) {
          final step =
              directionForWalk == PlayDirection.clockwise ? 1 : -1;
          var idx = currentIdx;
          for (var safety = players.length; safety > 0; safety--) {
            idx = (idx + step) % players.length;
            if (idx < 0) idx += players.length;
            final pid = players[idx].id;
            if (pid == newCurrentId) break;
            _bustTurnsThisRound[pid] = (_bustTurnsThisRound[pid] ?? 0) + 1;
          }
        }
      }

      if (_isBustRoundComplete()) {
        _finalizeBustRound();
        return;
      }

      // 1v1 showdown: a deferred win (e.g. last card was a 2) may now be
      // confirmable after the penalty was drawn.  Mirrors the client's
      // _onTurnComplete → _maybeFinalizeBustFinalShowdown() check.
      if (_bustSurvivorIds.length == 2) {
        for (final id in _bustSurvivorIds) {
          if (canConfirmPlayerWin(
            state: _state,
            playerId: id,
            skipLastCardsCheck: true,
          )) {
            _completeBustFinalShowdown(id);
            return;
          }
        }
      }

    }

    _broadcast({
      'type': 'turn_changed',
      'currentPlayerId': _state.currentPlayerId,
      'direction': _state.direction.name,
    });

    _broadcastStateSnapshots();
    _aiDeclareLastCardsIfNeeded();
    _startTurnTimer();
  }

  /// After [turn_changed], non-current AI seats may declare Last Cards
  /// ([mayDeclareLastCards]). Mirrors offline AI when the hand can be cleared
  /// in one turn (see `offline_game_engine_ai.dart`).
  void _aiDeclareLastCardsIfNeeded() {
    if (_gameOver || !_started || isBustMode) return;

    for (final p in List<PlayerModel>.from(_state.players)) {
      final pid = p.id;
      if (_players[pid]?.isAi != true) continue;
      if (pid == _state.currentPlayerId) continue;
      if (_state.lastCardsDeclaredBy.contains(pid)) continue;
      if (!mayDeclareLastCards(
        currentPlayerId: _state.currentPlayerId,
        playerId: pid,
      )) {
        continue;
      }
      if (!canClearHandInOneTurn(
        state: _state,
        playerId: pid,
        isBustMode: isBustMode,
      )) {
        continue;
      }
      _handleDeclareLastCards(pid);
    }
  }

  /// The opening [GameState.currentPlayerId] has not yet had a moment when
  /// [mayDeclareLastCards] could apply (it is always their turn until the first
  /// [advanceTurn]). Other seats are handled by [_aiDeclareLastCardsIfNeeded].
  /// Uses shared [applyOpeningSeatLastCardsSeedIfNeeded]; broadcasts
  /// [last_cards_pressed] like [_handleDeclareLastCards].
  void _seedOpeningCurrentPlayerLastCardsIfNoOffTurnWindowYet() {
    if (_gameOver || !_started || isBustMode) return;

    final r = applyOpeningSeatLastCardsSeedIfNeeded(
      state: _state,
      isBustMode: isBustMode,
    );
    if (!r.applied) return;
    _state = r.state;
    final id = _state.currentPlayerId;
    if (r.isBluff) _lastCardsBluffedBy.add(id);
    _broadcast({
      'type': 'last_cards_pressed',
      'playerId': id,
    });
  }

  /// With two survivors the finale is a race to empty hand — never end the
  /// round from turn counts alone.
  bool _isBustRoundComplete() {
    if (_bustSurvivorIds.length == 2) return false;
    return _bustSurvivorIds
        .every((id) => (_bustTurnsThisRound[id] ?? 0) >= 2);
  }

  void _finalizeBustRound() {
    _turnTimer?.cancel();

    if (_bustSurvivorIds.length == 2) {
      for (final id in _bustSurvivorIds) {
        if (canConfirmPlayerWin(
          state: _state,
          playerId: id,
          skipLastCardsCheck: true,
        )) {
          _completeBustFinalShowdown(id);
          return;
        }
      }
    }

    // 1. Add cards-remaining penalty for each survivor
    final roundPenalties = <String, int>{};
    for (final id in _bustSurvivorIds) {
      final p = _state.playerById(id);
      roundPenalties[id] = p?.hand.length ?? 0;
    }
    for (final id in _bustSurvivorIds) {
      _bustPenaltyPoints[id] =
          (_bustPenaltyPoints[id] ?? 0) + (roundPenalties[id] ?? 0);
    }

    // 2. Sort by cumulative penalty (highest = worst), eliminate bottom 2
    final sorted = List<String>.from(_bustSurvivorIds)
      ..sort((a, b) =>
          (_bustPenaltyPoints[b] ?? 0).compareTo(_bustPenaltyPoints[a] ?? 0));
    final activeCount = _bustSurvivorIds.length;
    final eliminateCount = activeCount <= 2 ? 1 : 2;
    final eliminatedThisRound = sorted.take(eliminateCount).toList();
    final survivors = sorted.skip(eliminateCount).toList();
    _bustEliminatedIds = [..._bustEliminatedIds, ...eliminatedThisRound];

    final isGameOver = survivors.length <= 1;
    final winnerId = isGameOver && survivors.isNotEmpty ? survivors.first : null;

    final standings = sorted.reversed.map((id) {
      final name = _players[id]?.displayName ?? id;
      return {
        'playerId': id,
        'playerName': name,
        'cardsThisRound': roundPenalties[id] ?? 0,
        'totalPenalty': _bustPenaltyPoints[id] ?? 0,
      };
    }).toList();

    _broadcast({
      'type': 'bust_round_over',
      'roundNumber': _bustRoundNumber,
      'standings': standings,
      'eliminatedThisRound': eliminatedThisRound,
      'survivorIds': survivors,
      'isGameOver': isGameOver,
      if (winnerId != null) 'winnerId': winnerId,
    });

    if (isGameOver) {
      _cancelAllDisconnectGraceTimers();
      _gameOver = true;
      _state = _state.copyWith(phase: GamePhase.ended, winnerId: winnerId);
      final bustTrophyEligible = _trophyEligible;

      Map<String, int>? ratingChanges;
      if (bustTrophyEligible && isRanked && winnerId != null) {
        ratingChanges = {
          for (final entry in _players.entries)
            entry.key:
                entry.key == winnerId ? _rankedWinDelta : _rankedLossDelta,
        };
        final winnerUid = _players[winnerId]?.firebaseUid ?? winnerId;
        final allPlayerUids = _players.entries
            .map((e) => (
                  playerId: e.key,
                  uid: e.value.firebaseUid ?? e.key,
                  displayName: e.value.displayName,
                ))
            .toList();
      _trophyRecorder.recordRankedResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: _players.length,
        rankedHardcore: _rankedHardcoreRecords,
      );
    }

    if (bustTrophyEligible && winnerId != null) {
        final bustPlayers = _players.entries
            .map((e) => (
                  playerId: e.key,
                  firebaseUid: e.value.firebaseUid,
                  displayName: e.value.displayName,
                ))
            .toList();
        _trophyRecorder.recordLeaderboardBustOnline(
          winnerPlayerId: winnerId,
          players: bustPlayers,
          playerCount: _players.length,
        );
      }

      _broadcast({
        'type': 'bust_game_ended',
        'winnerId': winnerId ?? '',
        'trophyEligible': bustTrophyEligible,
        if (ratingChanges != null) 'ratingChanges': ratingChanges,
      });
      return;
    }

    _bustRoundNumber++;
    _bustSurvivorIds = survivors;
    _bustTurnsThisRound = {for (final id in survivors) id: 0};
    _startBustNextRound();
  }

  /// 1v1 bust finale: [winnerId] has a confirmed empty hand.
  void _completeBustFinalShowdown(String winnerId) {
    _turnTimer?.cancel();
    final roundPenalties = <String, int>{};
    for (final id in _bustSurvivorIds) {
      final p = _state.playerById(id);
      roundPenalties[id] = p?.hand.length ?? 0;
    }
    for (final id in _bustSurvivorIds) {
      _bustPenaltyPoints[id] =
          (_bustPenaltyPoints[id] ?? 0) + (roundPenalties[id] ?? 0);
    }

    final loserId = _bustSurvivorIds.firstWhere((id) => id != winnerId);
    final eliminatedThisRound = <String>[loserId];
    final survivors = <String>[winnerId];
    _bustEliminatedIds = [..._bustEliminatedIds, ...eliminatedThisRound];

    final standings = [winnerId, loserId].map((id) {
      final name = _players[id]?.displayName ?? id;
      return {
        'playerId': id,
        'playerName': name,
        'cardsThisRound': roundPenalties[id] ?? 0,
        'totalPenalty': _bustPenaltyPoints[id] ?? 0,
      };
    }).toList();

    _broadcast({
      'type': 'bust_round_over',
      'roundNumber': _bustRoundNumber,
      'standings': standings,
      'eliminatedThisRound': eliminatedThisRound,
      'survivorIds': survivors,
      'isGameOver': true,
      'winnerId': winnerId,
    });

    _cancelAllDisconnectGraceTimers();
    _gameOver = true;
    _state = _state.copyWith(phase: GamePhase.ended, winnerId: winnerId);
    final bustTrophyEligible = _trophyEligible;

    Map<String, int>? ratingChanges;
    if (bustTrophyEligible && isRanked) {
      ratingChanges = {
        for (final entry in _players.entries)
          entry.key:
              entry.key == winnerId ? _rankedWinDelta : _rankedLossDelta,
      };
      final winnerUid = _players[winnerId]?.firebaseUid ?? winnerId;
      final allPlayerUids = _players.entries
          .map((e) => (
                playerId: e.key,
                uid: e.value.firebaseUid ?? e.key,
                displayName: e.value.displayName,
              ))
          .toList();
      _trophyRecorder.recordRankedResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: _players.length,
        rankedHardcore: _rankedHardcoreRecords,
      );
    }

    if (bustTrophyEligible) {
      final bustPlayers = _players.entries
          .map((e) => (
                playerId: e.key,
                firebaseUid: e.value.firebaseUid,
                displayName: e.value.displayName,
              ))
          .toList();
      _trophyRecorder.recordLeaderboardBustOnline(
        winnerPlayerId: winnerId,
        players: bustPlayers,
        playerCount: _players.length,
      );
    }

    _broadcast({
      'type': 'bust_game_ended',
      'winnerId': winnerId,
      'trophyEligible': bustTrophyEligible,
      if (ratingChanges != null) 'ratingChanges': ratingChanges,
    });
  }

  void _startBustNextRound() {
    final entries = _bustSurvivorIds
        .map((id) => MapEntry(id, _players[id]!))
        .toList();
    final totalPlayers = entries.length;
    final deck =
        buildBustDeck(seed: DateTime.now().millisecondsSinceEpoch + _bustRoundNumber);
    final handSize = handSizeForBust(totalPlayers);

    int idx = 0;
    final playerModels = <PlayerModel>[];
    for (int i = 0; i < totalPlayers; i++) {
      final hand = deck.sublist(idx, idx + handSize);
      idx += handSize;
      playerModels.add(PlayerModel(
        id: entries[i].key,
        displayName: entries[i].value.displayName,
        tablePosition: _positionFor(i),
        hand: hand,
        cardCount: hand.length,
        firebaseUid: entries[i].value.firebaseUid,
        isAi: entries[i].value.isAi,
      ));
    }

    final discardTop = deck[idx];
    idx++;
    _drawPile = List<CardModel>.from(deck.sublist(idx));
    _discardUnderTop.clear();

    _state = GameState(
      sessionId: roomCode,
      phase: GamePhase.playing,
      players: playerModels,
      currentPlayerId: playerModels.first.id,
      direction: PlayDirection.clockwise,
      discardTopCard: discardTop,
      drawPileCount: _drawPile.length,
      isHardcore: isHardcore,
    );
    _state = applyInitialFaceUpEffect(state: _state);
    if (_state.activeSkipCount > 0) {
      final skippedId = nextPlayerId(state: _state);
      _state = _state.copyWith(
        currentPlayerId: skippedId,
        activeSkipCount: 0,
        preTurnCentreSuit: _state.discardTopCard?.effectiveSuit,
      );
    } else {
      _state = _state.copyWith(
        preTurnCentreSuit: _state.discardTopCard?.effectiveSuit,
      );
    }

    _broadcast({
      'type': 'bust_round_start',
      'roundNumber': _bustRoundNumber,
    });
    _broadcastStateSnapshots();
    _startTurnTimer();
  }

  // ── Turn timer ────────────────────────────────────────────────────────────

  void _startTurnTimer() {
    _turnTimer?.cancel();
    if (_gameOver) return;
    final currentId = _state.currentPlayerId;
    final slot = _players[currentId];
    if (slot != null && slot.isAi) {
      _turnTimer = Timer(const Duration(milliseconds: 420), _executeAiTurn);
      return;
    }
    if (slot != null && !slot.isAi && slot.ws == null) {
      _turnTimer = Timer(
        Duration.zero,
        () => _onGraceDisconnectedTurnTimeout(currentId),
      );
      return;
    }
    _turnTimer = Timer(_turnDuration, _onTurnTimeout);
  }

  void _executeAiTurn() {
    if (_gameOver) return;
    final playerId = _state.currentPlayerId;
    final slot = _players[playerId];
    if (slot == null || !slot.isAi) return;

    final plan = planServerAiTurn(
      state: _state,
      playerId: playerId,
      difficulty: slot.aiDifficulty,
      rng: _aiRng,
      isHardcore: isHardcore,
    );

    if (plan.kind == ServerAiTurnKind.playCards) {
      _handlePlayCards(playerId, plan.payload!);
    } else if (plan.kind == ServerAiTurnKind.declareJoker) {
      _handleDeclareJoker(playerId, plan.payload!);
    } else if (plan.kind == ServerAiTurnKind.draw) {
      _handleDrawCard(playerId);
    } else {
      _handleEndTurn(playerId);
    }
  }

  void _onTurnTimeout() {
    if (_gameOver) return;
    _executeTurnTimeoutDrawAndAdvance(_state.currentPlayerId);
  }

  /// When the current seat is in disconnect grace ([_ConnectedPlayer.ws] null),
  /// resolves their turn immediately like [_onTurnTimeout] so others are not
  /// blocked for the full [_turnDuration].
  void _onGraceDisconnectedTurnTimeout(String expectedPlayerId) {
    if (_gameOver) return;
    if (_state.currentPlayerId != expectedPlayerId) return;
    final slot = _players[expectedPlayerId];
    if (slot == null) return;
    if (slot.ws != null) {
      _startTurnTimer();
      return;
    }
    _executeTurnTimeoutDrawAndAdvance(expectedPlayerId);
  }

  void _executeTurnTimeoutDrawAndAdvance(String timedOutPlayerId) {
    if (_gameOver) return;
    if (_state.currentPlayerId != timedOutPlayerId) return;

    final count =
        _state.activePenaltyCount > 0 ? _state.activePenaltyCount : 1;
    final drawnCards = <CardModel>[];
    _state = applyDraw(
      state: _state,
      playerId: timedOutPlayerId,
      count: count,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawnCards.addAll(cards);
        return cards;
      },
    );

    for (final card in drawnCards) {
      _sendTo(timedOutPlayerId, {
        'type': 'card_drawn',
        'playerId': timedOutPlayerId,
        'card': card.toJson(),
      });
    }
    for (final entry in _players.entries) {
      if (entry.key != timedOutPlayerId) {
        final w = entry.value.ws;
        if (w == null) continue;
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': timedOutPlayerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          w.sink.add(encoded);
        }
      }
    }

    if (count > 1) {
      _broadcast({
        'type': 'penalty_applied',
        'targetPlayerId': timedOutPlayerId,
        'cardsDrawn': count,
        'newPenaltyStack': 0,
      });
    }

    _broadcast({
      'type': 'turn_timeout',
      'playerId': timedOutPlayerId,
      'cardsDrawn': drawnCards.length,
    });

    _checkWin();
    if (_gameOver) return;

    _advanceTurn();
  }

  // ── Invalid play penalty ──────────────────────────────────────────────────

  /// Draws penalty cards for [playerId] after an invalid play attempt (2 cards,
  /// or the full stacked pick-up count when applicable), then ends their turn.
  void _applyInvalidPlayPenalty(String playerId) {
    final drawnCards = <CardModel>[];
    _state = applyInvalidPlayPenalty(
      state: _state,
      playerId: playerId,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawnCards.addAll(cards);
        return cards;
      },
    );

    // Broadcast once so clients can show "drew N cards for invalid play" instead of N separate lines.
    _broadcast({
      'type': 'invalid_play_penalty',
      'playerId': playerId,
      'drawCount': drawnCards.length,
    });

    for (final card in drawnCards) {
      _sendTo(playerId, {
        'type': 'card_drawn',
        'playerId': playerId,
        'card': card.toJson(),
      });
    }
    for (final entry in _players.entries) {
      if (entry.key != playerId) {
        final w = entry.value.ws;
        if (w == null) continue;
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': playerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          w.sink.add(encoded);
        }
      }
    }

    // Same contract as [_handleDrawCard] for multi-card penalty draws: clients
    // play one cardDraw + one penaltyDraw from [penalty_applied], not from
    // each [card_drawn].
    _broadcast({
      'type': 'penalty_applied',
      'targetPlayerId': playerId,
      'cardsDrawn': drawnCards.length,
      'newPenaltyStack': _state.activePenaltyCount,
    });

    _checkBustPlacementPileRule();
    _advanceTurn();
  }

  // ── Win detection ─────────────────────────────────────────────────────────

  void _checkWin() {
    if (_gameOver) return;

    if (!isBustMode) {
      for (final p in _state.players) {
        if (needsUndeclaredLastCardsDraw(
          state: _state,
          playerId: p.id,
          isBustMode: false,
        )) {
          _applyUndeclaredLastCardsDrawAndEndTurn(p.id);
          return;
        }
      }
    }

    if (isBustMode && _bustSurvivorIds.length == 2) {
      if (!wouldConfirmWin(_state, skipLastCardsCheck: true)) return;
      final winnerId = _state.players
          .where((p) => p.hand.isEmpty && p.cardCount == 0)
          .firstOrNull
          ?.id;
      if (winnerId == null || !_bustSurvivorIds.contains(winnerId)) {
        return;
      }
      _completeBustFinalShowdown(winnerId);
      return;
    }

    // Bust rounds with 3+ survivors end when everyone has 2 turns, not on
    // empty hand.
    if (isBustMode) return;
    if (!wouldConfirmWin(_state)) return;

    final winner = _state.players.firstWhereOrNull(
        (p) => p.hand.isEmpty && p.cardCount == 0);
    if (winner == null) return;
    final winnerId = winner.id;
    _state = _state.copyWith(phase: GamePhase.ended, winnerId: winnerId);
    _cancelAllDisconnectGraceTimers();
    _gameOver = true;
    _turnTimer?.cancel();

    final trophyEligible = _trophyEligible;

    // Compute per-player rating deltas for ranked games.
    Map<String, int>? ratingChanges;
    if (trophyEligible && isRanked) {
      ratingChanges = {
        for (final entry in _players.entries)
          entry.key: entry.key == winnerId ? _rankedWinDelta : _rankedLossDelta,
      };
      final winnerUid = _players[winnerId]?.firebaseUid ?? winnerId;
      final allPlayerUids = _players.entries
          .map((e) => (
                playerId: e.key,
                uid: e.value.firebaseUid ?? e.key,
                displayName: e.value.displayName,
              ))
          .toList();
      _log.info(
        '[RANKED WIN] room=$roomCode winner: id=$winnerId '
        'uid=$winnerUid name=${_players[winnerId]?.displayName} | '
        'all: ${allPlayerUids.map((e) => '${e.playerId}(${e.displayName})=${e.uid}').join(', ')}',
      );
      _trophyRecorder.recordRankedResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: _players.length,
        rankedHardcore: _rankedHardcoreRecords,
      );
    }

    if (trophyEligible && !isRanked && !isBustMode) {
      final casualPlayers = _players.entries
          .map((e) => (
                playerId: e.key,
                firebaseUid: e.value.firebaseUid,
                displayName: e.value.displayName,
              ))
          .toList();
      _trophyRecorder.recordLeaderboardOnlineCasual(
        winnerPlayerId: winnerId,
        players: casualPlayers,
        playerCount: _players.length,
      );
    }

    _broadcast({
      'type': 'game_ended',
      'winnerId': winnerId,
      'trophyEligible': trophyEligible,
      if (ratingChanges != null) 'ratingChanges': ratingChanges,
    });
  }

  // ── Draw pile management ──────────────────────────────────────────────────

  /// Pops [n] cards from the draw pile, reshuffling when ≤ 5 remain.
  List<CardModel> _drawCards(int n) {
    // Reshuffle before drawing if pile is low.
    if (_drawPile.length <= 5 && _discardUnderTop.isNotEmpty) {
      _reshuffleDiscardIntoDraw();
    }
    final count = math.min(n, _drawPile.length);
    final drawn = List<CardModel>.from(_drawPile.sublist(0, count));
    _drawPile.removeRange(0, count);
    _state = _state.copyWith(drawPileCount: _drawPile.length);
    return drawn;
  }

  void _reshuffleDiscardIntoDraw() {
    final toShuffle = List<CardModel>.from(_discardUnderTop);
    _discardUnderTop.clear();

    fisherYatesShuffle(toShuffle);

    _drawPile.addAll(toShuffle);
    _state = _state.copyWith(drawPileCount: _drawPile.length);

    _broadcast({
      'type': 'reshuffle',
      'newDrawPileCount': _drawPile.length,
    });
  }

  /// Bust placement pile: when the visible discard reaches [bustPlacementPileThreshold]
  /// cards, shuffle all cards under the top back into the draw pile (see
  /// [needsBustPlacementPileReshuffleFromUnderTop] / docs/rules-by-mode.md).
  void _checkBustPlacementPileRule() {
    if (!isBustMode) return;
    if (_state.discardTopCard == null) return;
    if (!needsBustPlacementPileReshuffleFromUnderTop(_discardUnderTop.length)) {
      return;
    }

    final toShuffle = List<CardModel>.from(_discardUnderTop);
    fisherYatesShuffle(toShuffle);
    _drawPile.addAll(toShuffle);
    _discardUnderTop.clear();
    _state = _state.copyWith(drawPileCount: _drawPile.length);

    _broadcast({
      'type': 'reshuffle',
      'newDrawPileCount': _drawPile.length,
    });
  }

  /// Saves the current discard top (before it is replaced) into the under-pile.
  void _pushDiscardUnderTop() {
    final prev = _state.discardTopCard;
    if (prev != null) _discardUnderTop.add(prev);
  }

  void _broadcastCardPlayed({
    required String playerId,
    required List<CardModel> cards,
    required int activeSkipBefore,
    required PlayDirection directionBefore,
  }) {
    _broadcast({
      'type': 'card_played',
      'playerId': playerId,
      'cards': cards.map((c) => c.toJson()).toList(),
      'newDiscardTop': _state.discardTopCard!.toJson(),
      'activeSkipCountBefore': activeSkipBefore,
      'activeSkipCountAfter': _state.activeSkipCount,
      'skippedPlayers': skippedPlayerDisplayNamesForSkipState(_state),
      'turnContinues': _state.currentPlayerId == playerId,
      'directionReversed': directionBefore != _state.direction,
    });
  }

  // ── Broadcast helpers ─────────────────────────────────────────────────────

  /// Sends a personalised state_snapshot to every connected player.
  ///
  /// Each player receives:
  ///   • Their own hand (full card objects).
  ///   • Opponents with empty hands but accurate cardCount.
  ///   • Themselves always at [TablePosition.bottom].
  void _broadcastStateSnapshots() {
    const opponentPositions = [
      TablePosition.left,
      TablePosition.top,
      TablePosition.right,
      TablePosition.bottomLeft,
      TablePosition.topLeft,
      TablePosition.topRight,
      TablePosition.bottomRight,
      TablePosition.farLeft,
      TablePosition.farRight,
    ];

    for (final entry in _players.entries) {
      final playerId = entry.key;
      final ws = entry.value.ws;
      if (ws == null) continue;

      final personalizedPlayers = <PlayerModel>[];
      final others = <PlayerModel>[];

      for (final p in _state.players) {
        if (p.id == playerId) {
          personalizedPlayers
              .add(p.copyWith(tablePosition: TablePosition.bottom));
        } else {
          others.add(p.copyWith(hand: const [], cardCount: p.cardCount));
        }
      }
      personalizedPlayers.addAll(others);

      // Assign relative positions so each client sees themselves at bottom.
      for (var i = 1; i < personalizedPlayers.length; i++) {
        final pos = opponentPositions[(i - 1) % opponentPositions.length];
        personalizedPlayers[i] =
            personalizedPlayers[i].copyWith(tablePosition: pos);
      }

      final personalizedState = _state.copyWith(players: personalizedPlayers);

      final stateWithHistory = personalizedState.copyWith(
        discardPileHistory: _discardUnderTop.reversed.take(5).toList(),
      );

      ws.sink.add(jsonEncode({
        'type': 'state_snapshot',
        'payload': stateWithHistory.toJson(),
      }));
    }
  }

  void _broadcast(Map<String, dynamic> event) {
    final encoded = jsonEncode(event);
    for (final p in _players.values) {
      final w = p.ws;
      if (w != null) w.sink.add(encoded);
    }
  }

  void _sendTo(String playerId, Map<String, dynamic> event) {
    final w = _players[playerId]?.ws;
    if (w != null) w.sink.add(jsonEncode(event));
  }

  void _sendError(String playerId, String code, String message) {
    _sendTo(playerId, {'type': 'error', 'code': code, 'message': message});
  }

  // ── Quick chat ─────────────────────────────────────────────────────────────

  /// Broadcasts a preset reaction (emoji / GIF catalogue index) to all players.
  /// Index must satisfy [isValidReactionWireIndex].
  void handleQuickChat(String playerId, Map<String, dynamic> json) {
    if (!_started || _gameOver) return;
    final messageIndex = json['messageIndex'] as int?;
    if (messageIndex == null || !isValidReactionWireIndex(messageIndex)) return;

    // Server-side rate limit: 10 seconds between messages per player.
    final now = DateTime.now();
    final lastTime = _lastQuickChatTime[playerId];
    if (lastTime != null && now.difference(lastTime).inSeconds < 10) return;
    _lastQuickChatTime[playerId] = now;

    _broadcast({
      'type': 'quick_chat',
      'playerId': playerId,
      'messageIndex': messageIndex,
    });
  }

  // ── Position helper ───────────────────────────────────────────────────────

  TablePosition _positionFor(int index) => tablePositionForSeatIndex(index);
}
