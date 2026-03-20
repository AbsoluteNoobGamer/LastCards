import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:last_cards/shared/constants/quick_chat_messages.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/engine/shuffle_utils.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart';

import 'trophy_recorder.dart';

// Bust mode: 52-card deck, 2 turns per player per round, eliminate bottom 2 each round.

// ── Turn timer duration ───────────────────────────────────────────────────────

const _turnDuration = Duration(seconds: 60);

// ── Connected player ──────────────────────────────────────────────────────────

class _ConnectedPlayer {
  _ConnectedPlayer({
    required this.ws,
    required this.displayName,
    this.firebaseUid,
  });
  final dynamic ws;
  final String displayName;
  final String? firebaseUid;
  bool isReady = false;
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
///   • Invalid-play 2-card draw penalty.
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
    this.isRanked = false,
    TrophyRecorder? trophyRecorder,
  }) : _trophyRecorder = trophyRecorder ?? TrophyRecorder.instance;

  final String roomCode;

  /// True for private lobbies (create_room/join_room). False for quickplay.
  final bool isPrivate;

  /// For quickplay: the intended player count from the queue.
  /// Trophies are only earned if the game started with this many players.
  final int? maxPlayerCount;

  /// True for Bust mode: 10 players, 52-card deck, multi-round with elimination.
  final bool isBustMode;

  /// True for ranked matchmaking: enables MMR recording via [TrophyRecorder].
  final bool isRanked;

  final TrophyRecorder _trophyRecorder;

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

  /// Per-turn countdown timer.
  Timer? _turnTimer;

  bool get _trophyEligible =>
      !isPrivate && (maxPlayerCount == null || _wasFullRoster);

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

  /// Returns the current discard-under-top size (for assertions in tests).
  int get discardUnderTopCountForTesting => _discardUnderTop.length;

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
      ).toJson(),
    });

    return id;
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
        ).toJson(),
      }));
      index++;
    }
  }

  void removePlayer(String playerId) {
    final leavingPlayer = _players[playerId];
    final firebaseUid = leavingPlayer?.firebaseUid;
    final displayName = leavingPlayer?.displayName ?? playerId;
    _players.remove(playerId);
    _broadcast({'type': 'player_left', 'playerId': playerId});

    if (!_started || _gameOver) return;

    if (isBustMode) {
      _removePlayerFromBustInProgress(
        playerId: playerId,
        firebaseUid: firebaseUid,
        displayName: displayName,
      );
      return;
    }

    _endGameForDisconnect(
      disconnectedPlayerId: playerId,
      firebaseUid: firebaseUid,
      displayName: displayName,
    );
  }

  /// Standard (non-Bust) games end when any player disconnects mid-session.
  void _endGameForDisconnect({
    required String disconnectedPlayerId,
    required String? firebaseUid,
    required String displayName,
  }) {
    _turnTimer?.cancel();
    _gameOver = true;
    _state = _state.copyWith(phase: GamePhase.ended);

    final trophyPenaltyForLeaver = _trophyEligible;
    if (trophyPenaltyForLeaver && isRanked) {
      final uid = firebaseUid ?? disconnectedPlayerId;
      _trophyRecorder.recordLeavePenalty(uid, displayName: displayName);
    }

    _broadcast({
      'type': 'game_ended',
      'winnerId': '',
      'reason': 'player_disconnected',
      'disconnectedPlayerId': disconnectedPlayerId,
      'trophyPenaltyForLeaver': trophyPenaltyForLeaver,
      if (isRanked)
        'ratingChanges': {
          disconnectedPlayerId: _rankedLeaveDelta,
        },
    });
  }

  /// Bust: drop the leaver from the table; continue if more than 2 survivors remain.
  void _removePlayerFromBustInProgress({
    required String playerId,
    required String? firebaseUid,
    required String displayName,
  }) {
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
        _players.values.every((p) => p.isReady) &&
        !_started) {
      _startGame();
    }
  }

  // ── Game start ────────────────────────────────────────────────────────────

  void _startGame() {
    _started = true;
    _gameOver = false;
    _wasFullRoster =
        maxPlayerCount == null || _players.length >= maxPlayerCount!;

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

    // Notify clients of session type (private vs ranked, trophy eligibility).
    _broadcast({
      'type': 'session_config',
      'isPrivate': isPrivate,
      'isRanked': isRanked,
      'trophyEligible': _trophyEligible,
    });
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
      // Invalid play: send error and apply 2-card draw penalty.
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
      _pushDiscardUnderTop();
      _state = applyPlay(state: _state, playerId: playerId, cards: cards);
      _checkBustPlacementPileRule();

      _broadcast({
        'type': 'card_played',
        'playerId': playerId,
        'cards': cards.map((c) => c.toJson()).toList(),
        'newDiscardTop': _state.discardTopCard!.toJson(),
      });

      // Ask the acting player to choose a suit.
      _sendTo(playerId, {
        'type': 'suit_choice_required',
        'cardId': cards.first.id,
      });

      _checkWin();
      _broadcastStateSnapshots();
      return;
    }

    _pushDiscardUnderTop();
    _state = applyPlay(
      state: _state,
      playerId: playerId,
      cards: cards,
      declaredSuit: declaredSuit,
    );
    _checkBustPlacementPileRule();

    _broadcast({
      'type': 'card_played',
      'playerId': playerId,
      'cards': cards.map((c) => c.toJson()).toList(),
      'newDiscardTop': _state.discardTopCard!.toJson(),
    });

    _checkWin();
    _broadcastStateSnapshots();
  }

  // ── suit_choice ───────────────────────────────────────────────────────────

  void _handleSuitChoice(String playerId, Map<String, dynamic> json) {
    if (_state.currentPlayerId != playerId) return;

    final suitStr = json['suit'] as String?;
    if (suitStr == null) return;
    final suit = Suit.values.byName(suitStr);

    // Lock the declared suit onto the current state.
    _state = _state.copyWith(suitLock: suit);
    _broadcastStateSnapshots();
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
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': playerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          entry.value.ws.sink.add(encoded);
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

    _broadcast({
      'type': 'card_played',
      'playerId': playerId,
      'cards': [resolvedCard.toJson()],
      'newDiscardTop': _state.discardTopCard!.toJson(),
    });

    _checkWin();
    _broadcastStateSnapshots();
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

  // ── Turn advancement (shared by end_turn and timeout) ─────────────────────

  /// Advances to the next player, broadcasts turn_changed, resets timer.
  /// In Bust mode, records turns and finalizes the round when complete.
  void _advanceTurn() {
    final completedPlayerId = _state.currentPlayerId;
    final oldSkipCount = _state.activeSkipCount;
    final players = _state.players;
    final directionForWalk = _state.direction;
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
    }

    _broadcast({
      'type': 'turn_changed',
      'currentPlayerId': _state.currentPlayerId,
      'direction': _state.direction.name,
    });

    _broadcastStateSnapshots();
    _startTurnTimer();
  }

  bool _isBustRoundComplete() =>
      _bustSurvivorIds.every((id) => (_bustTurnsThisRound[id] ?? 0) >= 2);

  void _finalizeBustRound() {
    _turnTimer?.cancel();

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
    _turnTimer = Timer(_turnDuration, _onTurnTimeout);
  }

  void _onTurnTimeout() {
    if (_gameOver) return;
    final timedOutPlayerId = _state.currentPlayerId;

    // Force draw 1 card as timeout penalty.
    final drawnCards = <CardModel>[];
    _state = applyDraw(
      state: _state,
      playerId: timedOutPlayerId,
      count: 1,
      cardFactory: (n) {
        final cards = _drawCards(n);
        drawnCards.addAll(cards);
        return cards;
      },
    );

    // Send the drawn card only to the timed-out player.
    for (final card in drawnCards) {
      _sendTo(timedOutPlayerId, {
        'type': 'card_drawn',
        'playerId': timedOutPlayerId,
        'card': card.toJson(),
      });
    }
    for (final entry in _players.entries) {
      if (entry.key != timedOutPlayerId) {
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': timedOutPlayerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          entry.value.ws.sink.add(encoded);
        }
      }
    }

    // Broadcast turn_timeout before advancing.
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

  /// Draws 2 cards for [playerId] as punishment for an invalid play attempt,
  /// then ends their turn.
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
        final encoded = jsonEncode({
          'type': 'card_drawn',
          'playerId': playerId,
        });
        for (int i = 0; i < drawnCards.length; i++) {
          entry.value.ws.sink.add(encoded);
        }
      }
    }

    _checkBustPlacementPileRule();
    _advanceTurn();
  }

  // ── Win detection ─────────────────────────────────────────────────────────

  void _checkWin() {
    if (_gameOver) return;
    // Bust rounds end when everyone has 2 turns, not on first empty hand.
    if (isBustMode) return;
    if (!wouldConfirmWin(_state)) return;

    final winnerId =
        _state.players.firstWhere((p) => p.hand.isEmpty && p.cardCount == 0).id;
    _state = _state.copyWith(phase: GamePhase.ended, winnerId: winnerId);
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
      _trophyRecorder.recordRankedResult(
        winnerUid: winnerUid,
        allPlayerUids: allPlayerUids,
        playerCount: _players.length,
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

  /// Bust placement pile: when the visible discard pile reaches 5 cards,
  /// shuffle all cards under the top back into the draw pile (see
  /// [BustEngine.applyPlacementPileRule] / docs/rules-by-mode.md).
  void _checkBustPlacementPileRule() {
    if (!isBustMode) return;
    if (_state.discardTopCard == null) return;
    if (_discardUnderTop.length + 1 < 5) return;

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

      final personalizedPlayers = <PlayerModel>[];
      final others = <PlayerModel>[];

      for (final p in _state.players) {
        if (p.id == playerId) {
          personalizedPlayers
              .add(p.copyWith(tablePosition: TablePosition.bottom));
        } else {
          others.add(p.copyWith(hand: const [], cardCount: p.hand.length));
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
      p.ws.sink.add(encoded);
    }
  }

  void _sendTo(String playerId, Map<String, dynamic> event) {
    _players[playerId]?.ws.sink.add(jsonEncode(event));
  }

  void _sendError(String playerId, String code, String message) {
    _sendTo(playerId, {'type': 'error', 'code': code, 'message': message});
  }

  // ── Quick chat ─────────────────────────────────────────────────────────────

  /// Broadcasts a preset quick chat message to all players.
  /// Message index must be in range [0, kQuickMessages.length).
  void handleQuickChat(String playerId, Map<String, dynamic> json) {
    if (!_started || _gameOver) return;
    final messageIndex = json['messageIndex'] as int?;
    if (messageIndex == null || messageIndex < 0 || messageIndex >= kQuickMessages.length) return;

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

  TablePosition _positionFor(int index) {
    if (index == 0) return TablePosition.bottom;
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
    return opponentPositions[(index - 1) % opponentPositions.length];
  }
}
