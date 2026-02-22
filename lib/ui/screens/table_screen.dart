import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../core/models/demo_game_engine.dart';
import '../../core/models/demo_game_state.dart';
import '../../core/models/game_state.dart';
import '../../core/models/player_model.dart';
import '../../core/providers/connection_provider.dart';
import '../../core/providers/game_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/models/move_log_entry.dart';
import '../../core/network/websocket_client.dart';
import '../widgets/collapsible_game_log.dart';
import '../widgets/discard_pile_widget.dart';
import '../widgets/draw_pile_widget.dart';
import '../widgets/hud_overlay_widget.dart';
import '../widgets/player_hand_widget.dart';
import '../widgets/player_zone_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/status_bar_widget.dart';
import '../widgets/turn_indicator_overlay.dart';

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

  /// Mutable demo state — set by initState via buildWithDeck().
  late GameState _demoState;

  bool _aiThinking = false;

  // ── Move log ──────────────────────────────────────────────────────
  final List<MoveLogEntry> _moveLog = [
    MoveLogEntry(isGameEvent: true, eventText: '🎮 Game started — match suit or rank')
  ];

  // ── Discard tracking for reshuffle ────────────────────────────────
  // Starts at 1 because the initial face-up card is already "discarded".
  int _totalDiscarded = 1;


  // ── Real shuffled draw pile + discard tracking ────────────────────
  late List<CardModel> _drawPile;          // actual remaining cards
  final List<CardModel> _discardPile = []; // tracks all discarded cards

  // ── Turn timer ────────────────────────────────────────────────────
  Timer? _turnTimer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _initNewGame();
  }

  void _initNewGame() {
    final (state, drawPile) = DemoGameState.buildWithDeck(totalPlayers: widget.totalPlayers);
    _demoState     = state;
    _drawPile      = drawPile;
    _discardPile
      ..clear()
      ..add(state.discardTopCard!); // seed discard with starting face-up card
    _totalDiscarded = 1;
    _startTimer();
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
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
          if (_demoState.currentPlayerId == DemoGameState.localId && !_aiThinking) {
            if (_demoState.queenSuitLock != null) {
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
      state: _demoState,
      playerId: DemoGameState.localId,
      count: 1,
      cardFactory: _makeCards,
    );

    setState(() {
      _demoState = newState;
    });

    // Restart timer to give them a chance to play the drawn card or draw again explicitly
    _startTimer();
  }

  void _endTurn() {
    if (_aiThinking) return;
    if (_demoState.currentPlayerId != DemoGameState.localId) return;

    final err = validateEndTurn(_demoState);
    if (err != null) {
      _showError(err);
      return;
    }

    _turnTimer?.cancel();
    _addLog('You ended your turn.');
    setState(() => _selectedCardIds.clear());

    final nextId = nextPlayerId(state: _demoState);
    setState(() {
      _demoState = _demoState.copyWith(
        currentPlayerId: nextId,
        actionsThisTurn: 0,
        lastPlayedThisTurn: null,
        activeSkipCount: 0,
      );
    });

    if (nextId != DemoGameState.localId) {
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
    _demoState = _demoState.copyWith(drawPileCount: _drawPile.length);
    return drawn;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final liveState   = ref.watch(gameStateProvider);
    final connState   = ref.watch(connectionStateProvider).valueOrNull
        ?? WsConnectionState.disconnected;

    final isDemoMode  = liveState == null;
    final gameState   = liveState ?? _demoState;
    final isMyTurn    = isDemoMode
        ? (_demoState.currentPlayerId == DemoGameState.localId && !_aiThinking)
        : ref.watch(isLocalTurnProvider);
    final penaltyCount = isDemoMode
        ? _demoState.activePenaltyCount
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
                  activePlayerName: gameState.playerById(gameState.currentPlayerId)?.displayName ?? '',
                  direction: gameState.direction,
                  upcomingPlayerNames: _getUpcomingPlayerNames(gameState),
                  secondsLeft: _secondsLeft,
                  canEndTurn: isDemoMode
                      ? (validateEndTurn(_demoState) == null)
                      : true,
                  onEndTurn: isDemoMode
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
                    connState: isDemoMode ? WsConnectionState.disconnected : connState,
                    canEndTurn: isDemoMode
                        ? (validateEndTurn(_demoState) == null)
                        : true,
                    onCardTap: _onCardTap,
                    onDrawTap: isDemoMode
                        ? () => _demoDrawCard(DemoGameState.localId)
                        : _onDrawTap,
                    onPlayTap: isDemoMode
                        ? () => _demoPlayCards(DemoGameState.localId)
                        : _onPlayTap,
                    onEndTurnTap: isDemoMode
                        ? _endTurn
                        : () {},
                  ),
                ),
              ],
            ),
          ),

          // ── Demo banner ─────────────────────────────────────────
          if (isDemoMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: _DemoBanner(
                  aiThinking: _aiThinking,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),

          // ── Move log (left edge) ────────────────────────────────
          if (isDemoMode)
            Positioned(
              left: 0,
              top: 72,
              child: CollapsibleGameLog(
                entries: _moveLog,
                activePlayerName: isMyTurn 
                    ? 'YOUR TURN' 
                    : (gameState.playerById(gameState.currentPlayerId)?.displayName ?? 'Unknown'),
                onClear: () => setState(() {
                  _moveLog.clear();
                  _moveLog.add(MoveLogEntry(isGameEvent: true, eventText: '🗑️ Log cleared'));
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ── Card tap ───────────────────────────────────────────────────────

  List<String> _getUpcomingPlayerNames(GameState state) {
    if (state.players.isEmpty) return [];
    
    final int currentIndex = state.players.indexWhere((p) => p.id == state.currentPlayerId);
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
    ref.read(gameNotifierProvider.notifier).playCards(_selectedCardIds.toList());
    setState(() => _selectedCardIds.clear());
  }

  // ── Demo: play cards ───────────────────────────────────────────────

  Future<void> _demoPlayCards(String playerId) async {
    if (_selectedCardIds.isEmpty || _aiThinking) return;
    if (_demoState.currentPlayerId != playerId) return;

    final local = _demoState.players.firstWhere((p) => p.id == playerId);
    final played = local.hand
        .where((c) => _selectedCardIds.contains(c.id))
        .toList();

    // Rule validation
    final err = validatePlay(
      cards: played,
      discardTop: _demoState.discardTopCard!,
      state: _demoState,
    );
    if (err != null) {
      _showError(err);
      setState(() => _selectedCardIds.clear());
      return;
    }

    // Only ask for a suit if the Ace is acting as a wild card.
    // An Ace is a wild card ONLY if it's the very first card played this turn.
    final isWildAce = _demoState.actionsThisTurn == 0 && played.first.effectiveRank == Rank.ace;
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
        state: _demoState,
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
        _demoState = newState;
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
        state: _demoState,
        discardTop: _demoState.discardTopCard!,
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

      var newState = applyPlay(state: _demoState, playerId: playerId, cards: [assignedJoker]);

      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        cards: played,
        isSpecial: true,
      ));
      _noteSpecialEffect([assignedJoker]);

      _totalDiscarded += 1;
      _discardPile.add(assignedJoker);

      setState(() {
        _demoState = newState;
        _selectedCardIds.clear();
      });

      _reshuffleIfNeeded();
      if (_checkWin(playerId, newState)) return;

      // Allow the player to continue their turn (stack more cards if they want).
      return;
    }

    // Apply play + special effects
    var newState = applyPlay(state: _demoState, playerId: playerId, cards: played);

    final skipCounts = _demoState.activeSkipCount;
    if (skipCounts > 0 && playerId != DemoGameState.aiId) {
        _addLog('  ↳ ${skipCounts == 1 ? "1 player" : "$skipCounts players"} skipped! (Applies on End Turn)');
    }

    // Log + track discards
    _addLogEntry(MoveLogEntry(
      player: 'YOU',
      cards: played,
      isSpecial: _isSpecial(played.first),
    ));
    _noteSpecialEffect(played);

    _totalDiscarded += played.length;
    _discardPile.addAll(played);

    setState(() {
      _demoState = newState;
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

  // ── Demo: draw card ────────────────────────────────────────────────

  void _demoDrawCard(String playerId) {
    if (_aiThinking) return;
    if (_demoState.currentPlayerId != playerId) return;

    final isPenaltyDraw = _demoState.activePenaltyCount > 0;
    final drawCount = isPenaltyDraw ? _demoState.activePenaltyCount : 1;

    var newState = applyDraw(
      state: _demoState,
      playerId: playerId,
      count: drawCount,
      cardFactory: _makeCards,
    );

    if (isPenaltyDraw) {
      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        isDraw: true,
        drawCount: drawCount,
        drawReason: '(penalty)',
      ));
      // Penalty draw: turn advances automatically.
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(currentPlayerId: nextId, actionsThisTurn: 0, activeSkipCount: 0);
      setState(() {
        _demoState = newState;
        _selectedCardIds.clear();
      });
      _turnTimer?.cancel();
      if (nextId != DemoGameState.localId) _scheduleAiTurn(nextId);
    } else {
      // Voluntary draw (no valid moves) — auto-end turn per the rules.
      _addLogEntry(MoveLogEntry(
        player: 'YOU',
        isDraw: true,
        drawCount: 1,
        drawReason: '(no moves)',
      ));
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(currentPlayerId: nextId, actionsThisTurn: 0, activeSkipCount: 0);
      setState(() {
        _demoState = newState;
        _selectedCardIds.clear();
      });
      _turnTimer?.cancel();
      if (nextId != DemoGameState.localId) {
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
        state: _demoState,
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
        _demoState = result.state;
        _aiThinking = false;
      });

      if (_checkWin(aiId, result.state)) return;

      final nextId = result.state.currentPlayerId;
      if (nextId != DemoGameState.localId) {
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

    Future.microtask(() {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WinDialog(
          winnerName: winner.displayName,
          isLocalWin: winner.id == DemoGameState.localId,
          onPlayAgain: () {
            Navigator.of(context).pop();
            setState(() {
              _initNewGame();
              _selectedCardIds.clear();
              _aiThinking = false;
              _moveLog
                ..clear()
                ..add(MoveLogEntry(isGameEvent: true, eventText: '🎮 New game started — fresh shuffle!'));
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
      Rank.two, Rank.jack, Rank.queen, Rank.king, Rank.ace, Rank.eight,
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
        Rank.two   => '  ↳ Player 2 draws 2!',
        Rank.jack  => c.isBlackJack ? '  ↳ Player 2 draws 5!' : '  ↳ Penalty cancelled!',
        Rank.king  => '  ↳ Direction reversed!',
        Rank.queen => '  ↳ Suit locked: ${c.effectiveSuit.displayName}',
        Rank.ace   => '  ↳ Suit changed to ${c.effectiveSuit.displayName}!',
        Rank.eight => c == played.first ? '  ↳ Skipped!' : null, // Prevent spamming log if multi 8s, handled by aggregate log above
        _          => null,
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


// ── Table layout ──────────────────────────────────────────────────────────────

class _TableLayout extends StatelessWidget {
  const _TableLayout({
    required this.gameState,
    required this.selectedCardIds,
    required this.isMyTurn,
    required this.secondsLeft,
    required this.penaltyCount,
    required this.connState,
    required this.canEndTurn,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onPlayTap,
    required this.onEndTurnTap,
  });

  final GameState gameState;
  final Set<String> selectedCardIds;
  final bool isMyTurn;
  final int secondsLeft;
  final int penaltyCount;
  final WsConnectionState connState;
  final bool canEndTurn;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final VoidCallback onPlayTap;
  final VoidCallback onEndTurnTap;

  @override
  Widget build(BuildContext context) {
    final players = gameState.players;
    // Local player is always at TablePosition.bottom
    final localPlayer = players.firstWhere(
      (p) => p.tablePosition == TablePosition.bottom,
      orElse: () => players.isNotEmpty ? players.first : _emptyLocal,
    );

    // Classify opponents by table position
    final topOpp = _opponentAt(players, TablePosition.top);
    final leftOpp = _opponentAt(players, TablePosition.left);
    final rightOpp = _opponentAt(players, TablePosition.right);

    // Calculate next turn ID for visual indicator
    String nextId = '';
    if (players.isNotEmpty) {
      final int idx = players.indexWhere((p) => p.id == gameState.currentPlayerId);
      if (idx != -1) {
        final int dir = gameState.direction == PlayDirection.clockwise ? 1 : -1;
        final int count = players.length;
        int nextIdx = (idx + dir) % count;
        if (nextIdx < 0) nextIdx += count;
        nextId = players[nextIdx].id;
      }
    }

    return Column(
      children: [
        // ── Top opponent ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: AppDimensions.md),
          child: topOpp != null
              ? PlayerZoneWidget(player: topOpp, isNextTurn: topOpp.id == nextId)
              : const _EmptyOpponentZone(),
        ),

        // ── Centre row: left opp / piles / right opp ───────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left opponent
              Expanded(
                child: Center(
                  child: leftOpp != null
                      ? RotatedBox(
                          quarterTurns: 1,
                          child: PlayerZoneWidget(player: leftOpp, isNextTurn: leftOpp.id == nextId),
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // Centre piles + HUD
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // HUD row
                  HudOverlayWidget(
                    activeSuit: gameState.suitLock,
                    queenSuitLock: gameState.queenSuitLock,
                    penaltyCount: penaltyCount,
                    connectionState: connState,
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Dealer badge — indicates the dealing entity (not a player)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.sm + 2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldDark.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                      border: Border.all(
                        color: AppColors.goldDark.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      'DEALER',
                      style: TextStyle(
                        color: AppColors.goldPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // Draw pile + Discard pile side by side
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DrawPileWidget(
                        cardCount: gameState.drawPileCount,
                        onTap: onDrawTap,
                        enabled: isMyTurn && (selectedCardIds.isEmpty),
                      ),
                      const SizedBox(width: AppDimensions.lg),
                      DiscardPileWidget(
                        topCard: gameState.discardTopCard,
                        secondCard: gameState.discardSecondCard,
                      ),
                    ],
                  ),


                  // End Turn button removed from here, now in Status Bar
                  // We just show a blank space or keep play button only
                  if (selectedCardIds.isNotEmpty && isMyTurn) ...[
                    const SizedBox(height: AppDimensions.md),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldPrimary,
                        foregroundColor: AppColors.feltDeep,
                      ),
                      onPressed: onPlayTap,
                      child: Text('PLAY CARD${selectedCardIds.length > 1 ? 'S' : ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),

              // Right opponent
              Expanded(
                child: Center(
                  child: rightOpp != null
                      ? RotatedBox(
                          quarterTurns: 3,
                          child: PlayerZoneWidget(player: rightOpp, isNextTurn: rightOpp.id == nextId),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),

        // ── Local player hand ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.md),
          child: PlayerZoneWidget(
                  player: localPlayer,
                  isLocalPlayer: true,
                  isNextTurn: localPlayer.id == nextId,
                  child: PlayerHandWidget(
                    cards: localPlayer.hand,
                    selectedCardIds: selectedCardIds,
                    onCardTap: onCardTap,
                    enabled: isMyTurn,
                  ),
                ),
        ),
      ],
    );
  }

  // Fallback empty local player (should never be needed with demo state)
  static const _emptyLocal = PlayerModel(
    id: 'local',
    displayName: 'You',
    tablePosition: TablePosition.bottom,
    hand: [],
    cardCount: 0,
    isConnected: true,
    isActiveTurn: false,
    isSkipped: false,
  );

  PlayerModel? _opponentAt(List<PlayerModel> players, TablePosition pos) {
    try {
      return players.firstWhere((p) => p.tablePosition == pos);
    } catch (_) {
      return null;
    }
  }
}

// ── Background ────────────────────────────────────────────────────────────────

class _FeltTableBackground extends StatelessWidget {
  const _FeltTableBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _FeltPainter()),
    );
  }
}

class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base felt fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.feltDeep,
    );

    // Subtle micro-texture via semi-transparent noise dots
    final dotPaint = Paint()
      ..color = AppColors.feltMid.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Simple dot grid as texture approximation
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if (((x ~/ 4) + (y ~/ 4)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
        }
      }
    }

    // Vignette — radial darkening toward edges
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide * 0.75;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
          stops: const [0.45, 1.0],
        ).createShader(
          Rect.fromCircle(center: centre, radius: radius),
        ),
    );

    // Faint inner highlight (overhead light)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.5,
          colors: [
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.4),
        ),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter _) => false;
}

// ── Placeholder widgets ───────────────────────────────────────────────────────

class _EmptyOpponentZone extends StatelessWidget {
  const _EmptyOpponentZone();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 80);
  }
}

// ── Demo mode banner ──────────────────────────────────────────────────────────

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onBack, required this.aiThinking});
  final VoidCallback onBack;
  final bool aiThinking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.md,
        vertical: AppDimensions.xs + 2,
      ),
      color: AppColors.goldDark.withValues(alpha: 0.88),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.arrow_back_ios,
                size: 16, color: AppColors.feltDeep),
          ),
          const SizedBox(width: AppDimensions.sm),
          Expanded(
            child: Text(
              aiThinking ? '⏳  Player 2 is thinking…' : 'DEMO — follow suit or rank to play',
              style: TextStyle(
                color: AppColors.feltDeep,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontStyle: aiThinking ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          Text(
            aiThinking ? '' : 'vs Player 2 (AI)  🤖',
            style: const TextStyle(
              color: AppColors.feltDeep,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Win dialog ────────────────────────────────────────────────────────────────

class _WinDialog extends StatelessWidget {
  const _WinDialog({
    required this.winnerName,
    required this.isLocalWin,
    required this.onPlayAgain,
  });

  final String winnerName;
  final bool isLocalWin;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final emoji = isLocalWin ? '🎉' : '🤖';
    final headline = isLocalWin ? 'YOU WIN!' : '$winnerName WINS!';
    final sub = isLocalWin
        ? 'Excellent hand — you beat the Dealer!'
        : 'The Dealer played their last card first.';

    return Dialog(
      backgroundColor: AppColors.feltMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
        side: const BorderSide(color: AppColors.goldPrimary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: AppDimensions.md),
            Text(
              headline,
              style: TextStyle(
                color: isLocalWin ? AppColors.goldPrimary : AppColors.redSoft,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: AppDimensions.sm),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPlayAgain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldPrimary,
                  foregroundColor: AppColors.feltDeep,
                  padding: const EdgeInsets.symmetric(vertical: AppDimensions.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                  ),
                ),
                child: const Text(
                  'PLAY AGAIN',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ace suit picker ─────────────────────────────────────────────────────────

/// Bottom sheet that lets the player choose which suit to lock after playing an Ace.
class _AceSuitPickerSheet extends StatelessWidget {
  const _AceSuitPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2016),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.goldDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Ace icon + title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('A', style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.goldPrimary,
              )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ace Played!',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Choose the new active suit',
                    style: TextStyle(
                      color: AppColors.goldDark.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Suit buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SuitPickButton(
                symbol: '♠', label: 'Spades', suit: Suit.spades, isRed: false),
              _SuitPickButton(
                symbol: '♣', label: 'Clubs', suit: Suit.clubs, isRed: false),
              _SuitPickButton(
                symbol: '♥', label: 'Hearts', suit: Suit.hearts, isRed: true),
              _SuitPickButton(
                symbol: '♦', label: 'Diamonds', suit: Suit.diamonds, isRed: true),
            ],
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SuitPickButton extends StatelessWidget {
  const _SuitPickButton({
    required this.symbol,
    required this.label,
    required this.suit,
    required this.isRed,
  });

  final String symbol;
  final String label;
  final Suit suit;
  final bool isRed;

  @override
  Widget build(BuildContext context) {
    final color = isRed ? AppColors.suitRed : AppColors.suitBlack;
    final borderColor = isRed
        ? AppColors.suitRed.withValues(alpha: 0.6)
        : AppColors.goldDark.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(suit),
      child: Container(
        width: 68,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.cardFace,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              symbol,
              style: TextStyle(fontSize: 32, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.85),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Joker specific role picker ───────────────────────────────────────────────

/// Bottom sheet that lets the player choose exactly which card the Joker will represent.
class _JokerSelectionSheet extends StatelessWidget {
  const _JokerSelectionSheet({required this.options});
  
  final List<CardModel> options;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2016),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.goldDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🃏', style: TextStyle(
                fontSize: 28,
              )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Joker Played!',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Choose the exact card the Joker will become',
                    style: TextStyle(
                      color: AppColors.goldDark.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Build a wrapping grid of PlayingCard visuals
          Wrap(
            spacing: 12,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: options.map((card) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(card),
                child: SizedBox(
                   width: 50,
                   // Wrap PlayingCard in a container to add a slight border on hover/tap
                   child: CardWidget(
                     card: card,
                     isSelected: false, 
                   ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
