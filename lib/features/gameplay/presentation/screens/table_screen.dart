import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/card.dart';
import '../../domain/usecases/offline_game_engine.dart';
import '../../data/datasources/offline_game_state_datasource.dart';
import '../../domain/entities/game_state.dart';
import '../../domain/entities/player.dart';
import '../controllers/connection_provider.dart';
import '../controllers/game_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../domain/entities/move_log_entry.dart';
import '../../data/datasources/websocket_client.dart';

import '../widgets/integrated_game_log.dart';
import '../widgets/discard_pile_widget.dart';
import '../widgets/draw_pile_widget.dart';
import '../widgets/hud_overlay_widget.dart';
import '../widgets/player_hand_widget.dart';
import '../widgets/player_zone_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/status_bar_widget.dart';
import '../widgets/turn_indicator_overlay.dart';
import '../controllers/audio_service.dart';

part 'table_screen_background.dart';
part 'table_screen_layout.dart';
part 'table_screen_overlays.dart';
part 'table_screen_sheets.dart';

/// The main game table screen.
///
/// Layout (top-down casino table view):
/// ```
/// ┌───────────────────────────────────────────┐
/// │           Opponent (top)                  │
/// │                                           │
/// │  Opp (left)   [DRAW] [DISCARD]  Opp (right)│
/// │                    [HUD]                  │
/// │           Local Player (bottom)           │
/// └───────────────────────────────────────────┘
/// ```
class TableScreen extends ConsumerStatefulWidget {
  final int totalPlayers;
  const TableScreen({this.totalPlayers = 2, super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

// ── imports extended for engine ───────────────────────────────────────────────
// (already imported above)

class _TableScreenState extends ConsumerState<TableScreen> {
  final Set<String> _selectedCardIds = {};

  /// Mutable offline state — set by initState via buildWithDeck().
  late GameState _offlineState;

  bool _aiThinking = false;

  // ── Move log ──────────────────────────────────────────────────────
  final List<MoveLogEntry> _moveLog = [
    MoveLogEntry(
        isGameEvent: true, eventText: '🎮 Game started — match suit or rank')
  ];

  // ── Discard tracking for reshuffle ────────────────────────────────
  // Starts at 1 because the initial face-up card is already "discarded".
  int _totalDiscarded = 1;

  // ── Real shuffled draw pile + discard tracking ────────────────────
  late List<CardModel> _drawPile; // actual remaining cards
  final List<CardModel> _discardPile = []; // tracks all discarded cards

  // ── Turn timer ────────────────────────────────────────────────────
  Timer? _turnTimer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _initNewGame();
    // BGM start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(audioServiceProvider).startBgm();
    });
  }

  void _initNewGame() {
    final (state, drawPile) =
        OfflineGameState.buildWithDeck(totalPlayers: widget.totalPlayers);
    _offlineState = state;
    _drawPile = drawPile;
    _discardPile
      ..clear()
      ..add(state.discardTopCard!); // seed discard with starting face-up card
    _totalDiscarded = 1;
    _startTimer();
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    // BGM stop
    ref.read(audioServiceProvider).stopBgm();
    super.dispose();
  }

  void _startTimer() {
    _turnTimer?.cancel();
    _secondsLeft = 30;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          // Timer expired
          timer.cancel();
          if (_offlineState.currentPlayerId == OfflineGameState.localId &&
              !_aiThinking) {
            if (_offlineState.queenSuitLock != null) {
              // Timer expired while Queen uncovered -> force 1 draw, keep turn active
              _addLog('⏳ Timeout! Forced to draw for Queen cover.');
              _showError('Timeout! Drew 1 card to find cover.');
              _forcedQueenTimeoutDraw();
            } else {
              _addLog('⏳ Turn timer expired!');
              _endTurn();
            }
          }
        }
      });
    });
  }

  void _forcedQueenTimeoutDraw() {
    // Similar to demoDrawCard but explicitly just 1 card penalty for timeout
    // Turn DOES NOT advance because they still must cover the Queen!
    if (_aiThinking) return;

    var newState = applyDraw(
      state: _offlineState,
      playerId: OfflineGameState.localId,
      count: 1,
      cardFactory: _makeCards,
    );

    setState(() {
      _offlineState = newState;
    });

    // Restart timer to give them a chance to play the drawn card or draw again explicitly
    _startTimer();
  }

  void _endTurn() {
    if (_aiThinking) return;
    if (_offlineState.currentPlayerId != OfflineGameState.localId) return;

    final err = validateEndTurn(_offlineState);
    if (err != null) {
      _showError(err);
      return;
    }

    _turnTimer?.cancel();
    _addLog('You ended your turn.');
    setState(() => _selectedCardIds.clear());

    final nextId = nextPlayerId(state: _offlineState);
    setState(() {
      _offlineState = _offlineState.copyWith(
        currentPlayerId: nextId,
        actionsThisTurn: 0,
        lastPlayedThisTurn: null,
        activeSkipCount: 0,
      );
    });

    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
  }

  /// Pops [n] cards from the real draw pile.
  /// Triggers a reshuffle automatically if the pile is about to run dry.
  List<CardModel> _makeCards(int n) {
    _reshuffleIfNeeded(needed: n);
    final count = math.min(n, _drawPile.length);
    final drawn = _drawPile.sublist(0, count);
    _drawPile.removeRange(0, count);
    // Keep GameState count in sync
    _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
    return drawn;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(gameStateProvider);
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        WsConnectionState.disconnected;

    final isOfflineMode = liveState == null;
    final gameState = liveState ?? _offlineState;
    final isMyTurn = isOfflineMode
        ? (_offlineState.currentPlayerId == OfflineGameState.localId &&
            !_aiThinking)
        : ref.watch(isLocalTurnProvider);
    final penaltyCount = isOfflineMode
        ? _offlineState.activePenaltyCount
        : ref.watch(penaltyCountProvider);

    return Scaffold(
      backgroundColor: AppColors.feltDeep,
      body: Stack(
        children: [
          const _FeltTableBackground(),

          // ── Turn indicator ring ──────────────────────────────────────
          Positioned.fill(
            child: TurnIndicatorOverlay(direction: gameState.direction),
          ),

          SafeArea(
            child: Column(
              children: [
                StatusBarWidget(
                  activePlayerName: gameState
                          .playerById(gameState.currentPlayerId)
                          ?.displayName ??
                      '',
                  direction: gameState.direction,
                  upcomingPlayerNames: _getUpcomingPlayerNames(gameState),
                  secondsLeft: _secondsLeft,
                  canEndTurn: isOfflineMode
                      ? (validateEndTurn(_offlineState) == null)
                      : true,
                  onEndTurn: isOfflineMode
                      ? _endTurn
                      : () {}, // TODO: handle live server End Turn
                ),
                Expanded(
                  child: _TableLayout(
                    gameState: gameState,
                    selectedCardIds: _selectedCardIds,
                    isMyTurn: isMyTurn,
                    secondsLeft: _secondsLeft,
                    penaltyCount: penaltyCount,
                    connState: isOfflineMode
                        ? WsConnectionState.disconnected
                        : connState,
                    canEndTurn: isOfflineMode
                        ? (validateEndTurn(_offlineState) == null)
                        : true,
                    onCardTap: _onCardTap,
                    onDrawTap: isOfflineMode
                        ? () => _offlineDrawCard(OfflineGameState.localId)
                        : _onDrawTap,
                    onPlayTap: isOfflineMode
                        ? () => _offlinePlayCards(OfflineGameState.localId)
                        : _onPlayTap,
                    onEndTurnTap: isOfflineMode ? _endTurn : () {},
                  ),
                ),
              ],
            ),
          ),

          // ── Offline banner ─────────────────────────────────────────
          if (isOfflineMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _OfflineBanner(
                  aiThinking: _aiThinking,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),

          // ── Integrated Move log (left edge) ────────────────────────────────
          if (isOfflineMode)
            Positioned(
              left: 0,
              top: 180,
              bottom: 0,
              child: SafeArea(
                child: IntegratedGameLog(
                  entries: _moveLog,
                  activePlayerName: isMyTurn
                      ? 'YOUR TURN'
                      : (gameState
                              .playerById(gameState.currentPlayerId)
                              ?.displayName ??
                          'Unknown'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Card tap ───────────────────────────────────────────────────────

  List<String> _getUpcomingPlayerNames(GameState state) {
    if (state.players.isEmpty) return [];

    final int currentIndex =
        state.players.indexWhere((p) => p.id == state.currentPlayerId);
    if (currentIndex == -1) return [];

    final names = <String>[];
    final int dir = state.direction == PlayDirection.clockwise ? 1 : -1;
    final int count = state.players.length;

    for (int i = 1; i < count; i++) {
      int nextIdx = (currentIndex + i * dir) % count;
      if (nextIdx < 0) nextIdx += count;
      names.add(state.players[nextIdx].displayName);
    }
    return names;
  }

  void _onCardTap(String cardId) {
    if (_aiThinking) return;
    setState(() {
      if (_selectedCardIds.contains(cardId)) {
        _selectedCardIds.remove(cardId);
      } else {
        _selectedCardIds.add(cardId);
      }
    });
  }

  // ── Live server actions ────────────────────────────────────────────

  void _onDrawTap() {
    if (!ref.read(isLocalTurnProvider)) return;
    ref.read(gameNotifierProvider.notifier).drawCard();
    setState(() => _selectedCardIds.clear());
  }

  void _onPlayTap() {
    if (_selectedCardIds.isEmpty) return;
    ref
        .read(gameNotifierProvider.notifier)
        .playCards(_selectedCardIds.toList());
    setState(() => _selectedCardIds.clear());
  }

  // ── Offline mode: play cards ───────────────────────────────────────────────

  Future<void> _offlinePlayCards(String playerId) async {
    if (_selectedCardIds.isEmpty || _aiThinking) return;
    if (_offlineState.currentPlayerId != playerId) return;

    final local = _offlineState.players.firstWhere((p) => p.id == playerId);
    final played =
        local.hand.where((c) => _selectedCardIds.contains(c.id)).toList();

    // Rule validation
    final err = validatePlay(
      cards: played,
      discardTop: _offlineState.discardTopCard!,
      state: _offlineState,
    );
    if (err != null) {
      _showError(err);
      setState(() => _selectedCardIds.clear());
      return;
    }

    // Only ask for a suit if the Ace is acting as a wild card.
    // An Ace is a wild card ONLY if it's the very first card played this turn.
    final isWildAce = _offlineState.actionsThisTurn == 0 &&
        played.first.effectiveRank == Rank.ace;
    if (isWildAce && mounted) {
      final chosenSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AceSuitPickerSheet(),
      );
      if (!mounted) return;
      // If dismissed without picking, cancel the play.
      if (chosenSuit == null) {
        setState(() => _selectedCardIds.clear());
        return;
      }

      // Apply play with the declared suit.
      var newState = applyPlay(
        state: _offlineState,
        playerId: playerId,
        cards: played,
        declaredSuit: chosenSuit,
      );

      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        cards: played,
        isSpecial: isWildAce,
      ));
      _addLog('↻ Suit changed to ${chosenSuit.displayName}!');

      _totalDiscarded += played.length;
      _discardPile.addAll(played);

      setState(() {
        _offlineState = newState;
        _selectedCardIds.clear();
      });

      _reshuffleIfNeeded();
      if (_checkWin(playerId, newState)) return;

      // Wild Aces always end the turn immediately
      _addLog('  ↳ Wild Ace played! Turn ends.');
      _endTurn();

      return;
    }

    // Intercept Joker plays
    if (played.length == 1 && played.first.isJoker && mounted) {
      final validOptions = getValidJokerOptions(
        state: _offlineState,
        discardTop: _offlineState.discardTopCard!,
      );

      if (validOptions.isEmpty) {
        _showError('No valid moves available for the Joker right now.');
        setState(() => _selectedCardIds.clear());
        return;
      }

      final chosenCard = await showModalBottomSheet<CardModel>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _JokerSelectionSheet(options: validOptions),
      );

      if (!mounted) return;
      if (chosenCard == null) {
        setState(() => _selectedCardIds.clear());
        return;
      }

      final identityStr = chosenCard.shortLabel;

      // Override the Joker's identity locally before passing to engine
      // (The engine doesn't currently accept `jokerDeclaredSuit` and a rank natively
      // through `applyPlay` parameters like it does for Ace's `declaredSuit`,
      // so we modify the CardModel copy here to emulate the UI choice).
      final assignedJoker = played.first.copyWith(
        jokerDeclaredRank: chosenCard.rank,
        jokerDeclaredSuit: chosenCard.suit,
      );

      var newState = applyPlay(
          state: _offlineState, playerId: playerId, cards: [assignedJoker]);

      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        playerPosition: TablePosition.bottom,
        cards: [assignedJoker],
        isSpecial: true,
      ));
      _noteSpecialEffect([assignedJoker]);

      _totalDiscarded += 1;
      _discardPile.add(assignedJoker);

      setState(() {
        _offlineState = newState;
        _selectedCardIds.clear();
      });

      _reshuffleIfNeeded();
      if (_checkWin(playerId, newState)) return;

      // Allow the player to continue their turn (stack more cards if they want).
      return;
    }

    // Apply play + special effects
    var newState =
        applyPlay(state: _offlineState, playerId: playerId, cards: played);

    final skipCounts = _offlineState.activeSkipCount;
    if (skipCounts > 0 && playerId != OfflineGameState.aiId) {
      _addLog(
          '  ↳ ${skipCounts == 1 ? "1 player" : "$skipCounts players"} skipped! (Applies on End Turn)');
    }

    // Log + track discards
    _addLogEntry(MoveLogEntry(
      player: 'YOU',
      playerPosition: TablePosition.bottom,
      cards: played,
      isSpecial: _isSpecial(played.first),
    ));
    _noteSpecialEffect(played);

    _totalDiscarded += played.length;
    _discardPile.addAll(played);

    setState(() {
      _offlineState = newState;
      _selectedCardIds.clear();
    });

    _reshuffleIfNeeded();
    if (_checkWin(playerId, newState)) return;

    // Auto-advance if this play guarantees we get another turn immediately and
    // there are no unresolved obligations (like covering a Queen).
    // This happens when playing a Skip (8) or a King in a 2-player game.
    final nextId = nextPlayerId(state: newState);

    if (nextId == playerId && newState.queenSuitLock == null) {
      _addLog('  ↳ Extra turn granted!');
      _endTurn();
    }
  }

  // ── Offline mode: draw card ────────────────────────────────────────────────

  void _offlineDrawCard(String playerId) {
    if (_aiThinking) return;
    if (_offlineState.currentPlayerId != playerId) return;

    final isPenaltyDraw = _offlineState.activePenaltyCount > 0;
    final isQueenPenaltyDraw = _offlineState.queenSuitLock != null;
    final drawCount = isPenaltyDraw ? _offlineState.activePenaltyCount : 1;

    var newState = applyDraw(
      state: _offlineState,
      playerId: playerId,
      count: drawCount,
      cardFactory: _makeCards,
    );

    if (isQueenPenaltyDraw) {
      newState = newState.copyWith(queenSuitLock: null);
      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        playerPosition: TablePosition.bottom,
        isDraw: true,
        drawCount: 1,
        drawReason: '(Queen penalty)',
      ));
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, activeSkipCount: 0);
      setState(() {
        _offlineState = newState;
        _selectedCardIds.clear();
      });
      _turnTimer?.cancel();
      if (nextId != OfflineGameState.localId) _scheduleAiTurn(nextId);
    } else if (isPenaltyDraw) {
      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        playerPosition: TablePosition.bottom,
        isDraw: true,
        drawCount: drawCount,
        drawReason: '(penalty)',
      ));
      // Penalty draw: turn advances automatically.
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, activeSkipCount: 0);
      setState(() {
        _offlineState = newState;
        _selectedCardIds.clear();
      });
      _turnTimer?.cancel();
      if (nextId != OfflineGameState.localId) _scheduleAiTurn(nextId);
    } else {
      // Voluntary draw (no valid moves) — auto-end turn per the rules.
      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        playerPosition: TablePosition.bottom,
        isDraw: true,
        drawCount: 1,
        drawReason: '(no moves)',
      ));
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, activeSkipCount: 0);
      setState(() {
        _offlineState = newState;
        _selectedCardIds.clear();
      });
      _turnTimer?.cancel();
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        _startTimer();
      }
    }
  }

  // ── AI turn ────────────────────────────────────────────────────────

  void _scheduleAiTurn(String aiId) {
    if (_aiThinking) return;
    setState(() => _aiThinking = true);

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      final result = aiTakeTurn(
        state: _offlineState,
        aiPlayerId: aiId,
        cardFactory: _makeCards,
      );

      // Track AI-played card into discard pile
      final playedByAi = result.log.expand((l) => l.cards).toList();
      if (playedByAi.isNotEmpty) {
        _discardPile.addAll(playedByAi);
        _totalDiscarded += playedByAi.length;
      }

      for (final entry in result.log) {
        _addLogEntry(entry);
      }

      setState(() {
        _offlineState = result.state;
        _aiThinking = false;
      });

      if (_checkWin(aiId, result.state)) return;

      final nextId = result.state.currentPlayerId;
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        // AI turn ended, back to local player
        _startTimer();
      }
    });
  }

  // ── Reshuffle discard → draw (Fisher-Yates) ───────────────────────

  void _reshuffleIfNeeded({int needed = 1}) {
    if (_drawPile.length >= needed && _drawPile.isNotEmpty) return;
    if (_discardPile.length <= 1) return; // nothing to reshuffle

    // Keep the top discard in place; shuffle the rest back.
    final topCard = _discardPile.last;
    final toShuffle = _discardPile.sublist(0, _discardPile.length - 1);
    _discardPile
      ..clear()
      ..add(topCard);

    // Fisher-Yates
    final rng = math.Random();
    for (int i = toShuffle.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = toShuffle[i];
      toShuffle[i] = toShuffle[j];
      toShuffle[j] = tmp;
    }

    _drawPile.addAll(toShuffle);
    _totalDiscarded = 1;

    // Don't call setState here — _makeCards will sync the count after this.
    _addLog('♻️ Shuffled +${toShuffle.length} discards back into draw pile');
  }

  // ── Win detection ──────────────────────────────────────────────────

  bool _checkWin(String lastActorId, GameState state) {
    final winner = state.players
        .where((p) => p.hand.isEmpty && p.cardCount == 0)
        .firstOrNull;

    if (winner == null) return false;

    // Prevent immediate win if the player's last card was a Queen that still needs covering.
    if (state.queenSuitLock != null && winner.id == state.currentPlayerId) {
      return false;
    }

    Future.microtask(() {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WinDialog(
          winnerName: winner.displayName,
          isLocalWin: winner.id == OfflineGameState.localId,
          onPlayAgain: () {
            Navigator.of(context).pop();
            setState(() {
              _initNewGame();
              _selectedCardIds.clear();
              _aiThinking = false;
              _moveLog
                ..clear()
                ..add(MoveLogEntry(
                    isGameEvent: true,
                    eventText: '🎮 New game started — fresh shuffle!'));
            });
          },
        ),
      );
    });
    return true;
  }

  // ── Helpers ────────────────────────────────────────────────────────

  bool _isSpecial(CardModel c) {
    const specials = {
      Rank.two,
      Rank.jack,
      Rank.queen,
      Rank.king,
      Rank.ace,
      Rank.eight,
    };
    return specials.contains(c.effectiveRank) || c.isJoker;
  }

  void _addLog(String msg) {
    setState(() {
      _moveLog.add(MoveLogEntry(isGameEvent: true, eventText: msg));
      if (_moveLog.length > 100) _moveLog.removeAt(0);
    });
  }

  void _addLogEntry(MoveLogEntry entry) {
    setState(() {
      _moveLog.add(entry);
      if (_moveLog.length > 100) _moveLog.removeAt(0);
    });
  }

  void _noteSpecialEffect(List<CardModel> played) {
    for (final c in played) {
      final note = switch (c.effectiveRank) {
        Rank.two => '  ↳ Player 2 draws 2!',
        Rank.jack =>
          c.isBlackJack ? '  ↳ Player 2 draws 5!' : '  ↳ Penalty cancelled!',
        Rank.king => '  ↳ Direction reversed!',
        Rank.queen => '  ↳ Suit locked: ${c.effectiveSuit.displayName}',
        Rank.ace => '  ↳ Suit changed to ${c.effectiveSuit.displayName}!',
        Rank.eight => c == played.first
            ? '  ↳ Skipped!'
            : null, // Prevent spamming log if multi 8s, handled by aggregate log above
        _ => null,
      };
      if (note != null) _addLog(note);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.redAccent,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
