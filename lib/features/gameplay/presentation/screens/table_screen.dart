import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stack_and_flow/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';

import '../../domain/entities/card.dart';
import '../../domain/usecases/offline_game_engine.dart';
import '../../data/datasources/offline_game_state_datasource.dart';
import '../../domain/entities/game_state.dart';
import '../../domain/entities/player.dart';
import '../controllers/connection_provider.dart';
import '../controllers/game_provider.dart';
import '../../data/datasources/websocket_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../widgets/discard_pile_widget.dart';
import '../widgets/draw_pile_widget.dart';
import '../widgets/hud_overlay_widget.dart';
import '../widgets/player_hand_widget.dart';
import '../widgets/player_zone_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/status_bar_widget.dart';
import '../widgets/turn_indicator_overlay.dart';
import '../controllers/audio_service.dart';
import '../widgets/last_move_panel_widget.dart';

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
  String? _selectedCardId;

  /// The most recent move made by any player (null until the first move).
  LastMoveInfo? _lastMove;

  /// Local display order of the player's hand (card IDs).
  /// New cards are appended to the right; drag-and-drop updates this list.
  List<String> _handOrder = [];

  bool _isDealing = false;
  final Map<String, int> _visibleCardCounts = {};

  late AudioService _audioService;

  // Animation overlay keys
  final GlobalKey<DealingAnimationOverlayState> _overlayKey =
      GlobalKey<DealingAnimationOverlayState>();
  final GlobalKey _drawPileKey = GlobalKey();
  final Map<String, GlobalKey> _playerZoneKeys = {};

  /// Mutable offline state — set by initState via buildWithDeck().
  late GameState _offlineState;

  bool _aiThinking = false;

  // ── Real shuffled draw pile + discard tracking ────────────────────
  late List<CardModel> _drawPile; // actual remaining cards
  final List<CardModel> _discardPile = []; // tracks all discarded cards
  // ── Turn timer ────────────────────────────────────────────────────
  Timer? _turnTimer;

  /// Toggled (not set) each time a reshuffle fires so DrawPileWidget can
  /// play the shuffle animation even on repeated reshuffles.
  final ValueNotifier<bool> _reshuffleNotifier = ValueNotifier<bool>(false);
  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    _initNewGame();
    // BGM start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _audioService.startBgm();
    });
  }

  void _initNewGame() {
    final (state, drawPile) =
        OfflineGameState.buildWithDeck(totalPlayers: widget.totalPlayers);
    _offlineState = state.copyWith(
      preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
    );
    _drawPile = drawPile;
    _discardPile
      ..clear()
      ..add(state.discardTopCard!); // seed discard with starting face-up card
    _lastMove = null; // reset on new game

    // Assign player keys for animation destinations
    _playerZoneKeys.clear();
    for (var p in state.players) {
      _playerZoneKeys[p.id] = GlobalKey();
    }

    // Initialise hand order from the local player's starting cards
    final localStart = state.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;
    _handOrder = localStart?.hand.map((c) => c.id).toList() ?? [];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startDealAnimation();
    });
  }

  Future<void> _startDealAnimation() async {
    setState(() {
      _isDealing = true;
      _visibleCardCounts.clear();
      for (var p in _offlineState.players) {
        _visibleCardCounts[p.id] = 0;
      }
    });

    final players = _offlineState.players;
    final localIdx =
        players.indexWhere((p) => p.tablePosition == TablePosition.bottom);

    // Order: Clockwise starting from the player to the left of the local player (or top if 2 players),
    // ending with the local player.
    final orderedPlayers = <PlayerModel>[];
    final dir = _offlineState.direction == PlayDirection.clockwise ? 1 : -1;
    for (int i = 1; i <= players.length; i++) {
      int idx = (localIdx + i * dir) % players.length;
      if (idx < 0) idx += players.length;
      orderedPlayers.add(players[idx]);
    }

    final audioService = ref.read(audioServiceProvider);

    for (int i = 0; i < 7; i++) {
      for (final p in orderedPlayers) {
        if (!mounted) return;

        audioService.playClick();
        final overlay = _overlayKey.currentState;
        if (overlay != null) {
          await overlay.animateCardDeal(p.id);
        } else {
          await Future.delayed(const Duration(milliseconds: 150));
        }

        // Wait an extra sliver between cards so they don't overlap too rigidly
        await Future.delayed(const Duration(milliseconds: 50));

        if (mounted) {
          setState(() {
            _visibleCardCounts[p.id] = (_visibleCardCounts[p.id] ?? 0) + 1;
            // Decrement the draw pile counter in real-time as cards are dealt
            _offlineState = _offlineState.copyWith(
              drawPileCount: math.max(0, _offlineState.drawPileCount - 1),
            );
          });
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _isDealing = false;
    });

    _startTimer();
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    _reshuffleNotifier.dispose();
    // BGM stop
    _audioService.stopBgm();
    super.dispose();
  }

  void _startTimer() {
    _turnTimer?.cancel();
    int secondsLeft = 30;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (secondsLeft > 0) {
        secondsLeft--;
      } else {
        // Timer expired
        timer.cancel();
        if (_offlineState.currentPlayerId == OfflineGameState.localId &&
            !_aiThinking) {
          if (_offlineState.queenSuitLock != null) {
            // Timer expired while Queen uncovered -> force 1 draw, keep turn active
            _showError('Timeout! Drew 1 card to find cover.');
            _forcedQueenTimeoutDraw();
          } else {
            _endTurn();
          }
        }
      }
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
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
    });

    // Restart timer to give them a chance to play the drawn card or draw again explicitly
    _startTimer();
  }

  Future<void> _endTurn() async {
    if (_aiThinking) return;
    if (_offlineState.currentPlayerId != OfflineGameState.localId) return;

    final err = validateEndTurn(_offlineState);
    if (err != null) {
      _showError(err);
      return;
    }

    _turnTimer?.cancel();
    setState(() => _selectedCardId = null);

    // Rule 1: Ace played alone triggers the suit selector at End Turn
    if (_offlineState.discardTopCard?.effectiveRank == Rank.ace &&
        _offlineState.cardsPlayedThisTurn == 1 &&
        mounted) {
      final chosenSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AceSuitPickerSheet(),
      );
      if (!mounted) return;

      if (chosenSuit == null) {
        _startTimer(); // Resume the timer if they dismissed the sheet
        return; // Don't end turn yet
      }

      setState(() {
        _offlineState = _offlineState.copyWith(suitLock: chosenSuit);
      });
    }

    final nextId = nextPlayerId(state: _offlineState);
    setState(() {
      _offlineState = _offlineState.copyWith(
        currentPlayerId: nextId,
        actionsThisTurn: 0,
        cardsPlayedThisTurn: 0,
        lastPlayedThisTurn: null,
        activeSkipCount: 0,
        preTurnCentreSuit: _offlineState.discardTopCard?.effectiveSuit,
      );
    });

    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
  }

  /// Pops [n] cards from the real draw pile.
  ///
  /// After removing the requested cards, checks if the pile has dropped to
  /// 5 or fewer — if so, immediately reshuffles the centre pile back in.
  /// Using <=5 (not ==5) ensures a multi-card draw that skips exactly 5
  /// still triggers the reshuffle.
  List<CardModel> _makeCards(int n) {
    final count = math.min(n, _drawPile.length);
    final drawn = _drawPile.sublist(0, count);
    _drawPile.removeRange(0, count);
    // Sync counter immediately after every draw.
    _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
    // Trigger reshuffle whenever pile drops to 5 or below.
    _reshuffleCentrePileIntoDrawPile();
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
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
                        selectedCardId: _selectedCardId,
                        orderedHand: _orderedHand(
                          gameState.players
                                  .where((p) =>
                                      p.tablePosition == TablePosition.bottom)
                                  .firstOrNull
                                  ?.hand ??
                              [],
                        ),
                        isMyTurn: isMyTurn,
                        penaltyCount: penaltyCount,
                        connState: isOfflineMode
                            ? WsConnectionState.disconnected
                            : connState,
                        canEndTurn: isOfflineMode
                            ? (validateEndTurn(_offlineState) == null)
                            : true,
                        isDealing: _isDealing,
                        visibleCardCounts: _visibleCardCounts,
                        drawPileKey: _drawPileKey,
                        playerZoneKeys: _playerZoneKeys,
                        onCardTap: _onCardTap,
                        onDrawTap: isOfflineMode
                            ? () => _offlineDrawCard(OfflineGameState.localId)
                            : _onDrawTap,
                        onHandReorder: _onHandReorder,
                        onEndTurnTap: isOfflineMode ? _endTurn : () {},
                        isOffline: isOfflineMode,
                        discardPileCount: _discardPile.length,
                        lastMove: _lastMove,
                        reshuffleNotifier: _reshuffleNotifier,
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



              // ── Dealing Animation Overlay ──────────────────────────────
              Positioned.fill(
                child: DealingAnimationOverlay(
                  key: _overlayKey,
                  drawPileKey: _drawPileKey,
                  playerKeys: _playerZoneKeys,
                ),
              ),
            ],
          );
        },
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
    final isOfflineMode = ref.read(gameStateProvider) == null;
    if (isOfflineMode) {
      _offlinePlayCards(OfflineGameState.localId, cardId: cardId);
    } else {
      _onPlayTap(cardId: cardId);
    }
  }

  // ── Live server actions ────────────────────────────────────────────

  void _onDrawTap() {
    if (!ref.read(isLocalTurnProvider)) return;
    ref.read(gameNotifierProvider.notifier).drawCard();
    setState(() => _selectedCardId = null);
  }

  void _onPlayTap({required String cardId}) {
    ref.read(gameNotifierProvider.notifier).playCards([cardId]);
    setState(() => _selectedCardId = null);
  }

  // ── Offline mode: play cards ───────────────────────────────────────────────

  Future<void> _offlinePlayCards(String playerId,
      {required String cardId}) async {
    if (_aiThinking) return;
    if (_offlineState.currentPlayerId != playerId) return;

    final local = _offlineState.players.firstWhere((p) => p.id == playerId);
    final played = local.hand.where((c) => c.id == cardId).toList();

    if (played.isEmpty) return;

    // Rule validation — validate before any visual change.
    // If the play is invalid, apply the penalty sequence instead of blocking.
    final err = validatePlay(
      cards: played,
      discardTop: _offlineState.discardTopCard!,
      state: _offlineState,
    );
    if (err != null) {
      _applyInvalidPlayPenalty(playerId, played);
      return;
    }

    // Intercept Joker plays (mirrors Ace popup flow)
    if (played.length == 1 && played.first.isJoker && mounted) {
      final jokerContext =
          jokerPlayContextFromCardsPlayed(_offlineState.actionsThisTurn);
      final jokerAnchor = jokerContext == JokerPlayContext.midTurnContinuance
          ? (_offlineState.lastPlayedThisTurn ?? _offlineState.discardTopCard!)
          : _offlineState.discardTopCard!;

      final activeSequenceSuit = jokerContext == JokerPlayContext.midTurnContinuance
          ? jokerAnchor.effectiveSuit
          : null;

      final validOptions = getValidJokerOptions(
        state: _offlineState,
        discardTop: _offlineState.discardTopCard!,
        context: jokerContext,
        contextTopCard: jokerAnchor,
      );

      if (validOptions.isEmpty) {
        _showError('No valid moves available for the Joker right now.');
        return;
      }

      // Show selection visual while the modal is open
      setState(() => _selectedCardId = cardId);
      final chosenCard = await showModalBottomSheet<CardModel>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _JokerSelectionSheet(
          options: validOptions,
          playContext: jokerContext,
          activeSequenceSuit: activeSequenceSuit,
        ),
      );

      if (!mounted) return;
      if (chosenCard == null) {
        setState(() => _selectedCardId = null);
        return;
      }

      final assignedJoker = played.first.copyWith(
        jokerDeclaredRank: chosenCard.rank,
        jokerDeclaredSuit: chosenCard.suit,
      );

      var newState = applyPlay(
        state: _offlineState,
        playerId: playerId,
        cards: [assignedJoker],
      );

      _discardPile.add(assignedJoker);

      final localInNew = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      final jokerPlayerName = _offlineState.playerById(playerId)?.displayName ?? playerId;
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localInNew != null) _syncHandOrder(localInNew.hand);
        _lastMove = LastMoveInfo(
          playerName: jokerPlayerName,
          cardLabel: assignedJoker.shortLabel,
        );
      });

      _reshuffleCentrePileIntoDrawPile();
      if (_checkWin(playerId, newState)) return;

      // Allow the player to continue their turn (stack more cards if they want).
      return;
    }

    // Apply play + special effects
    var newState =
        applyPlay(state: _offlineState, playerId: playerId, cards: played);


    _discardPile.addAll(played);

    final localInNew = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;
    final playPlayerName = _offlineState.playerById(playerId)?.displayName ?? playerId;
    setState(() {
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localInNew != null) _syncHandOrder(localInNew.hand);
      _lastMove = LastMoveInfo(
        playerName: playPlayerName,
        cardLabel: played.first.shortLabel,
      );
    });

    _reshuffleCentrePileIntoDrawPile();
    if (_checkWin(playerId, newState)) return;

    // Auto-advance if this play guarantees we get another turn immediately and
    // there are no unresolved obligations (like covering a Queen).
    // This happens when playing a Skip (8) or a King in a 2-player game.
    final nextId = nextPlayerId(state: newState);

    if (nextId == playerId && newState.queenSuitLock == null) {
      _endTurn();
    }
  }

  // ── Offline mode: invalid play penalty sequence ────────────────────────────

  /// Fired when the local player attempts to play a card that fails validation.
  ///
  /// Penalty sequence (strictly in this order):
  ///   1. Return card to hand   — already satisfied: [applyPlay] was never called.
  ///   2. Draw up to 2 cards from the draw pile.
  ///   3. End the player's turn immediately.
  void _applyInvalidPlayPenalty(String playerId, List<CardModel> attemptedCards) {
    _showError('Invalid play! Drawing 2 cards as penalty.');

    // Step 2: draw up to 2 cards (respects remaining pile size).
    final drawCount = math.min(2, _drawPile.length);
    var newState = applyDraw(
      state: _offlineState,
      playerId: playerId,
      count: drawCount,
      cardFactory: _makeCards,
    );

    // applyDraw clears activePenaltyCount — restore the pre-existing penalty
    // so an ongoing 2/Jack penalty chain is not inadvertently cancelled.
    newState = newState.copyWith(
      activePenaltyCount: _offlineState.activePenaltyCount,
    );

    // Step 3: end the turn.
    final nextId = nextPlayerId(state: newState);
    newState = newState.copyWith(
      currentPlayerId: nextId,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
      lastPlayedThisTurn: null,
      activeSkipCount: 0,
      preTurnCentreSuit: newState.discardTopCard?.effectiveSuit,
    );

    final localAfter = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    setState(() {
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localAfter != null) _syncHandOrder(localAfter.hand);
    });

    _turnTimer?.cancel();
    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
  }

  // ── Offline mode: draw card ────────────────────────────────────────────────

  void _offlineDrawCard(String playerId) {
    if (_aiThinking) return;
    if (_offlineState.currentPlayerId != playerId) return;

    // RULE: A player's turn consists of ONE action — either playing OR drawing.
    // If they have already played a card this turn, the draw action is blocked.
    // EXCEPTION: If there is a Queen suit lock, they MUST draw if they cannot play.
    if (_offlineState.actionsThisTurn > 0 &&
        _offlineState.queenSuitLock == null) {
      return;
    }

    final isPenaltyDraw = _offlineState.activePenaltyCount > 0;
    final isQueenPenaltyDraw = _offlineState.queenSuitLock != null;
    final drawCount = isPenaltyDraw ? _offlineState.activePenaltyCount : 1;

    var newState = applyDraw(
      state: _offlineState,
      playerId: playerId,
      count: drawCount,
      cardFactory: _makeCards,
    );

    final localAfterDraw = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    if (isQueenPenaltyDraw || isPenaltyDraw) {
      final penaltyPlayerName = _offlineState.playerById(playerId)?.displayName ?? playerId;
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, cardsPlayedThisTurn: 0, activeSkipCount: 0, preTurnCentreSuit: newState.discardTopCard?.effectiveSuit);
      if (isQueenPenaltyDraw) {
        newState = newState.copyWith(queenSuitLock: null);
      }
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
        _lastMove = LastMoveInfo(playerName: penaltyPlayerName);
      });
      _turnTimer?.cancel();
      if (nextId != OfflineGameState.localId) _scheduleAiTurn(nextId);
    } else {
      // Voluntary draw (no valid moves) — auto-end turn per the rules.
      final drawPlayerName = _offlineState.playerById(playerId)?.displayName ?? playerId;
      final nextId = nextPlayerId(state: newState);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, cardsPlayedThisTurn: 0, activeSkipCount: 0, preTurnCentreSuit: newState.discardTopCard?.effectiveSuit);
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
        _lastMove = LastMoveInfo(playerName: drawPlayerName);
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
      final playedByAi = result.playedCards;
      if (playedByAi.isNotEmpty) {
        _discardPile.addAll(playedByAi);
      }

      final aiPlayerName = _offlineState.playerById(aiId)?.displayName ?? aiId;
      final aiLastMove = playedByAi.isNotEmpty
          ? LastMoveInfo(
              playerName: aiPlayerName,
              cardLabel: playedByAi.first.shortLabel,
            )
          : LastMoveInfo(playerName: aiPlayerName); // drew a card

      if (_checkWin(aiId, result.state)) return;

      var finalState = result.state;

      final nextId = finalState.currentPlayerId;
      if (nextId != aiId) {
         // Turn advanced, capture the new centre suit
         finalState = finalState.copyWith(preTurnCentreSuit: finalState.discardTopCard?.effectiveSuit);
      }

      setState(() {
        _offlineState = finalState.copyWith(drawPileCount: _drawPile.length);
        _aiThinking = false;
        _lastMove = aiLastMove;
      });

      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        // AI turn ended, back to local player
        _startTimer();
      }
    });
  }

  // ── Reshuffle centre pile → draw pile ─────────────────────────────────────

  /// Dedicated reshuffle function. Called from [_makeCards] every time cards
  /// leave the draw pile — this covers ALL draw paths: player draws, penalty
  /// draws, invalid-play penalty draws, and AI draws.
  ///
  /// Fires when [_drawPile.length] drops to **5 or fewer** cards so that a
  /// multi-card draw which skips exactly 5 is never missed.
  ///
  /// Behaviour (in order):
  ///   1. Takes all centre-pile cards EXCEPT the current top card.
  ///   2. Shuffles them with Fisher-Yates.
  ///   3. Appends them to [_drawPile].
  ///   4. Calls setState to update [drawPileCount] immediately.
  ///   5. Toggles [_reshuffleNotifier] → DrawPileWidget plays its animation.
  ///   6. Shows a visible "Reshuffling deck..." snackbar.
  ///   7. Prints the new count to the console for confirmation.
  void _reshuffleCentrePileIntoDrawPile() {
    // Gate: only trigger when 5 or fewer remain AND centre pile has spare cards.
    if (_drawPile.length > 5) return;
    if (_discardPile.length <= 1) return; // nothing beyond the top card

    // ── 1. Protect top centre card ──────────────────────────────────────────
    final topCard = _discardPile.last;
    final toShuffle = List<CardModel>.from(
      _discardPile.sublist(0, _discardPile.length - 1),
    );
    _discardPile
      ..clear()
      ..add(topCard); // top card stays; everything else leaves

    // ── 2. Fisher-Yates shuffle ─────────────────────────────────────────────
    final rng = math.Random();
    for (int i = toShuffle.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = toShuffle[i];
      toShuffle[i] = toShuffle[j];
      toShuffle[j] = tmp;
    }

    // ── 3. Add shuffled cards to draw pile ──────────────────────────────────
    _drawPile.addAll(toShuffle);

    // ── 7. Console confirmation ─────────────────────────────────────────────
    // ignore: avoid_print
    print("Draw pile counter after reshuffle: ${_drawPile.length}");
    
    // Add verification print
    int totalHandCount = 0;
    for (var player in _offlineState.players) {
      totalHandCount += player.hand.length;
    }
    // ignore: avoid_print
    print("Total cards in circulation: ${_drawPile.length + _discardPile.length + totalHandCount}");

    if (!mounted) return;

    // ── 4 & 5. Update counter + trigger animation ────────────────────────────
    setState(() {
      _offlineState =
          _offlineState.copyWith(drawPileCount: _drawPile.length);
      _reshuffleNotifier.value = !_reshuffleNotifier.value;
    });

    // ── 6. Visible banner so players know a reshuffle happened ──────────────
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.shuffle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Reshuffling deck...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.goldDark,
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
              _selectedCardId = null;
              _aiThinking = false;
              _initNewGame();
              _selectedCardId = null;
              _aiThinking = false;
            });
          },
        ),
      );
    });
    return true;
  }

  // ── Helpers ────────────────────────────────────────────────────────

  // ── Hand ordering ──────────────────────────────────────────────────

  /// Keeps `_handOrder` in sync with [hand]: removes stale IDs and appends
  /// any new card IDs (newly drawn cards) at the right end.
  void _syncHandOrder(List<CardModel> hand) {
    final ids = {for (final c in hand) c.id};
    final filtered = _handOrder.where((id) => ids.contains(id)).toList();
    final filteredSet = filtered.toSet();
    for (final card in hand) {
      if (!filteredSet.contains(card.id)) filtered.add(card.id);
    }
    _handOrder = filtered;
  }

  /// Returns [hand] sorted according to `_handOrder`.
  /// Cards not yet in `_handOrder` (e.g. just drawn) are appended at the end.
  List<CardModel> _orderedHand(List<CardModel> hand) {
    final idToCard = {for (final c in hand) c.id: c};
    final seen = <String>{};
    final result = <CardModel>[];
    for (final id in _handOrder) {
      final card = idToCard[id];
      if (card != null && seen.add(id)) result.add(card);
    }
    for (final c in hand) {
      if (seen.add(c.id)) result.add(c);
    }
    return result;
  }

  void _onHandReorder(int oldIndex, int newIndex) {
    setState(() {
      // Work on the currently displayed order (stale entries already excluded
      // by _orderedHand), then store as the new canonical order.
      final liveState = ref.read(gameStateProvider);
      final gameState = liveState ?? _offlineState;
      final localPlayer = gameState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      if (localPlayer == null) return;

      final currentOrder =
          _orderedHand(localPlayer.hand).map((c) => c.id).toList();
      if (oldIndex < 0 ||
          oldIndex >= currentOrder.length ||
          newIndex < 0 ||
          newIndex >= currentOrder.length) {
        return;
      }

      final id = currentOrder.removeAt(oldIndex);
      currentOrder.insert(newIndex, id);
      _handOrder = currentOrder;
    });
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
