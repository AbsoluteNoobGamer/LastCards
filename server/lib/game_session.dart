import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart';

// ── Turn timer duration ───────────────────────────────────────────────────────

const _turnDuration = Duration(seconds: 60);

// ── Connected player ──────────────────────────────────────────────────────────

class _ConnectedPlayer {
  _ConnectedPlayer({
    required this.ws,
    required this.displayName,
  });
  final dynamic ws;
  final String displayName;
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
class GameSession {
  GameSession(this.roomCode);

  final String roomCode;
  final _players = <String, _ConnectedPlayer>{};
  int _playerCounter = 0;

  late GameState _state;

  /// The actual remaining draw pile (server-authoritative).
  late List<CardModel> _drawPile;

  /// All discard pile cards except the current top card.
  /// Used for reshuffling back into the draw pile.
  final _discardUnderTop = <CardModel>[];

  bool _started = false;
  bool _gameOver = false;

  /// Per-turn countdown timer.
  Timer? _turnTimer;

  // ── Test helpers ───────────────────────────────────────────────────────────

  /// Directly seeds the session with a known state for testing.
  ///
  /// Callers must have already added players via [addPlayer] before calling
  /// this. The [drawPile] and optional [discardUnderTop] replace the server's
  /// internal piles.
  void seedStateForTesting({
    required GameState state,
    required List<CardModel> drawPile,
    List<CardModel> discardUnderTop = const [],
  }) {
    _state = state;
    _drawPile = List<CardModel>.from(drawPile);
    _discardUnderTop
      ..clear()
      ..addAll(discardUnderTop);
    _started = true;
    _gameOver = false;
    _broadcastStateSnapshots();
  }

  /// Returns the current draw pile size (for assertions in tests).
  int get drawPileCountForTesting => _drawPile.length;

  /// Returns the current discard-under-top size (for assertions in tests).
  int get discardUnderTopCountForTesting => _discardUnderTop.length;

  // ── Lobby ─────────────────────────────────────────────────────────────────

  String addPlayer(dynamic ws, String displayName) {
    if (_started) {
      ws.sink.add(
          '{"type":"error","code":"game_started","message":"Game already in progress."}');
      return '';
    }
    if (_players.length >= 4) {
      ws.sink.add(
          '{"type":"error","code":"room_full","message":"Room is full (max 4 players)."}');
      return '';
    }
    final id = 'player-${++_playerCounter}';
    _players[id] = _ConnectedPlayer(ws: ws, displayName: displayName);

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
    _players.remove(playerId);
    _broadcast({'type': 'player_left', 'playerId': playerId});

    // If the game is in progress, end it — removing a player's hand mid-game
    // would corrupt the state, and the turn timer could fire for a ghost player.
    if (_started && !_gameOver) {
      _turnTimer?.cancel();
      _gameOver = true;
      _state = _state.copyWith(phase: GamePhase.ended);
      _broadcast({
        'type': 'game_ended',
        'winnerId': '',
        'reason': 'player_disconnected',
        'disconnectedPlayerId': playerId,
      });
    }
  }

  void markReady(String playerId) {
    final player = _players[playerId];
    if (player != null) player.isReady = true;

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

    final deck = buildShuffledDeck();
    int idx = 0;
    final entries = _players.entries.toList();
    final totalPlayers = entries.length;

    // Hand size scaled so the full deal always fits in the 54-card deck.
    // 53 usable cards (54 minus 1 face-up discard) ÷ players, capped at 7.
    final handSize = math.min(7, 53 ~/ totalPlayers);

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
        isActiveTurn: i == 0,
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
      try {
        cards.add(player.hand.firstWhere((c) => c.id == id));
      } catch (_) {
        _sendError(playerId, 'invalid_card', 'Card $id not found in hand.');
        return;
      }
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

    CardModel jokerCard;
    try {
      jokerCard = player.hand.firstWhere((c) => c.id == jokerCardId);
    } catch (_) {
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
  void _advanceTurn() {
    _state = advanceTurn(_state);

    _broadcast({
      'type': 'turn_changed',
      'currentPlayerId': _state.currentPlayerId,
      'direction': _state.direction.name,
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

    _advanceTurn();
  }

  // ── Win detection ─────────────────────────────────────────────────────────

  void _checkWin() {
    if (_gameOver) return;
    if (!wouldConfirmWin(_state)) return;

    final winnerId =
        _state.players.firstWhere((p) => p.hand.isEmpty && p.cardCount == 0).id;
    _state = _state.copyWith(phase: GamePhase.ended, winnerId: winnerId);
    _gameOver = true;
    _turnTimer?.cancel();
    _broadcast({'type': 'game_ended', 'winnerId': winnerId});
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
    final rng = math.Random();
    final toShuffle = List<CardModel>.from(_discardUnderTop);
    _discardUnderTop.clear();

    // Fisher-Yates shuffle
    for (int i = toShuffle.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = toShuffle[i];
      toShuffle[i] = toShuffle[j];
      toShuffle[j] = tmp;
    }

    _drawPile.addAll(toShuffle);
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

      ws.sink.add(jsonEncode({
        'type': 'state_snapshot',
        'payload': personalizedState.toJson(),
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

  // ── Position helper ───────────────────────────────────────────────────────

  TablePosition _positionFor(int index) {
    const positions = [
      TablePosition.bottom,
      TablePosition.left,
      TablePosition.top,
      TablePosition.right,
    ];
    return positions[index % positions.length];
  }
}
