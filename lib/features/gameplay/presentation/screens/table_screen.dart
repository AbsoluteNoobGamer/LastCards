import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stack_and_flow/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';

import '../../domain/usecases/offline_game_engine.dart';
import 'package:stack_and_flow/shared/rules/win_condition_rules.dart';
import '../../data/datasources/offline_game_state_datasource.dart';
import '../../domain/entities/player.dart';
import '../../../../shared/engine/game_turn_timer.dart';
import '../controllers/connection_provider.dart';
import '../controllers/game_provider.dart';
import '../../data/datasources/websocket_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/services/card_back_service.dart';
import '../widgets/discard_pile_widget.dart';
import '../widgets/draw_pile_widget.dart';
import '../widgets/hud_overlay_widget.dart';
import '../widgets/player_hand_widget.dart';
import '../widgets/player_zone_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/floating_action_bar_widget.dart';
import '../widgets/turn_indicator_overlay.dart';
import '../controllers/audio_service.dart';
import '../widgets/last_move_panel_widget.dart';
import '../../../../widgets/turn_timer_bar.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';

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
  final bool isTournamentMode;
  final void Function(String playerName, int finishPosition) onPlayerFinished;
  final Map<String, String> tournamentPlayerNameByTableId;
  final GameState? debugInitialOfflineState;
  final List<CardModel>? debugInitialDrawPile;
  final bool debugSkipDealAnimation;
  const TableScreen({
    this.totalPlayers = 2,
    this.isTournamentMode = false,
    this.onPlayerFinished = _defaultOnPlayerFinished,
    this.tournamentPlayerNameByTableId = const <String, String>{},
    this.debugInitialOfflineState,
    this.debugInitialDrawPile,
    this.debugSkipDealAnimation = false,
    super.key,
  });

  static void _defaultOnPlayerFinished(String _, int __) {}

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class TournamentRoundGameResult {
  const TournamentRoundGameResult({
    required this.finishedPlayerIds,
    required this.eliminatedPlayerId,
  });

  final List<String> finishedPlayerIds;
  final String eliminatedPlayerId;
}

@visibleForTesting
bool shouldShowStandardWinOverlay({required bool isTournamentMode}) {
  return !isTournamentMode;
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
  final math.Random _aiDelayRng = math.Random();
  final List<String> _tournamentFinishedPlayerIds = <String>[];
  bool _tournamentRoundComplete = false;

  // ── Real shuffled draw pile + discard tracking ────────────────────
  late List<CardModel> _drawPile; // actual remaining cards
  final List<CardModel> _discardPile = []; // tracks all discarded cards
  // ── Turn timer ────────────────────────────────────────────────────
  late final GameTurnTimer _engineTimer = GameTurnTimer();
  StreamSubscription<int>? _timerWarningSub;
  bool _timerWarningPlayed = false;

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
    final hasDebugState = widget.debugInitialOfflineState != null &&
        widget.debugInitialDrawPile != null;
    GameState state;
    List<CardModel> drawPile;

    if (hasDebugState) {
      state = widget.debugInitialOfflineState!;
      drawPile = List<CardModel>.from(widget.debugInitialDrawPile!);
    } else {
      final seeded = OfflineGameState.buildWithDeck(totalPlayers: widget.totalPlayers);
      state = seeded.$1;
      drawPile = seeded.$2;
      if (widget.isTournamentMode &&
          widget.tournamentPlayerNameByTableId.isNotEmpty) {
        state = state.copyWith(
          players: state.players
              .map((player) => player.copyWith(
                    displayName:
                        widget.tournamentPlayerNameByTableId[player.id] ??
                            player.displayName,
                  ))
              .toList(),
        );
      }
      state = state.copyWith(
        preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
      );
      state = applyInitialFaceUpEffect(state: state);
      if (state.activeSkipCount > 0) {
        final nextId = nextPlayerId(state: state);
        state = state.copyWith(
          currentPlayerId: nextId,
          activeSkipCount: 0,
        );
      }
    }

    // During a normal deal animation, show the dealer pile counting down from
    // the pre-deal amount (54 total - 1 face-up centre card = 53).
    _offlineState = hasDebugState || widget.debugSkipDealAnimation
        ? state.copyWith(drawPileCount: drawPile.length)
        : state.copyWith(drawPileCount: 53);
    _drawPile = drawPile;
    _discardPile
      ..clear()
      ..add(state
          .discardTopCard!); // seed discard with post-effect starting card
    _lastMove = null; // reset on new game
    _tournamentFinishedPlayerIds.clear();
    _tournamentRoundComplete = false;

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
      if (!mounted) return;
      if (hasDebugState || widget.debugSkipDealAnimation) {
        _startTimer();
        if (_offlineState.currentPlayerId != OfflineGameState.localId) {
          _scheduleAiTurn(_offlineState.currentPlayerId);
        }
        return;
      }
      _startDealAnimation();
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

        audioService.playDealCard();
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
      // Snap to real remaining pile size after the visual countdown completes.
      _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
    });

    _startTimer();
    if (_offlineState.currentPlayerId != OfflineGameState.localId) {
      _scheduleAiTurn(_offlineState.currentPlayerId);
    }
  }

  @override
  void dispose() {
    _timerWarningSub?.cancel();
    _engineTimer.dispose();
    _reshuffleNotifier.dispose();
    // BGM stop
    _audioService.stopBgm();
    super.dispose();
  }

  void _startTimer() {
    _timerWarningPlayed = false;
    _timerWarningSub?.cancel();
    _timerWarningSub = _engineTimer.timeRemainingStream.listen((secondsLeft) {
      if (!_timerWarningPlayed && secondsLeft > 0 && secondsLeft <= 10) {
        _timerWarningPlayed = true;
        game_audio.AudioService.instance.playSound(GameSound.timerWarning);
      }
    });
    game_audio.AudioService.instance.playSound(GameSound.turnStart);
    _engineTimer.start(() {
      if (!mounted) return;
      if (widget.isTournamentMode &&
          _tournamentFinishedPlayerIds.contains(_offlineState.currentPlayerId)) {
        final nextId = _nextTournamentActivePlayerId(
          state: _offlineState,
          startAfterPlayerId: _offlineState.currentPlayerId,
        );
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
        }
        return;
      }
      if (_offlineState.currentPlayerId == OfflineGameState.localId &&
          !_aiThinking) {
        // Timeout rule: always force a single draw, end the turn, and pass play.
        game_audio.AudioService.instance.playSound(GameSound.timerExpired);
        _forcedTimeoutDrawAndEnd();
      }
    });
  }

  void _forcedTimeoutDrawAndEnd() {
    if (_aiThinking) return;

    _showError('Timeout! Drew 1 card as penalty.');

    var newState = applyDraw(
      state: _offlineState,
      playerId: OfflineGameState.localId,
      count: 1,
      cardFactory: _makeCards,
    );

    // End turn automatically
    var nextId = nextPlayerId(state: newState);
    nextId = _resolveTournamentNextPlayerId(newState, nextId);
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
      _lastMove = LastMoveInfo(
          playerName: _offlineState.playerById(OfflineGameState.localId)?.displayName ?? OfflineGameState.localId,
          cardLabel: 'Timeout Draw'
      );
    });

    _engineTimer.cancel();
    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
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

    _engineTimer.cancel();
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

    var nextId = nextPlayerId(state: _offlineState);
    nextId = _resolveTournamentNextPlayerId(_offlineState, nextId);
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
            !_aiThinking &&
            !_tournamentFinishedPlayerIds.contains(OfflineGameState.localId))
        : ref.watch(isLocalTurnProvider);
    final penaltyCount = isOfflineMode
        ? _offlineState.activePenaltyCount
        : ref.watch(penaltyCountProvider);

    return Scaffold(
      appBar: null,
      extendBodyBehindAppBar: true,
      extendBody: true,
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
                        timeRemainingStream: _engineTimer.timeRemainingStream,
                        tournamentStatusBadges: _buildTournamentStatusBadges(),
                        finishedPlayerIds:
                            _tournamentFinishedPlayerIds.toSet(),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Offline floating back control ───────────────────────────
              if (isOfflineMode)
                Positioned(
                  bottom: 210,
                  left: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.xs),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.30),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: 'Exit game',
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
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
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(playerId)) {
      return;
    }

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
      _engineTimer.cancel();

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
    _engineTimer.cancel();


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
    var nextId = nextPlayerId(state: newState);
    nextId = _resolveTournamentNextPlayerId(newState, nextId);

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

    _engineTimer.cancel();
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
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(playerId)) {
      final nextId = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: playerId,
      );
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        _startTimer();
      }
      return;
    }

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
      var nextId = nextPlayerId(state: newState);
      nextId = _resolveTournamentNextPlayerId(newState, nextId);
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
      _engineTimer.cancel();
      if (nextId != OfflineGameState.localId) _scheduleAiTurn(nextId);
    } else {
      // Voluntary draw (no valid moves) — auto-end turn per the rules.
      final drawPlayerName = _offlineState.playerById(playerId)?.displayName ?? playerId;
      var nextId = nextPlayerId(state: newState);
      nextId = _resolveTournamentNextPlayerId(newState, nextId);
      newState = newState.copyWith(
          currentPlayerId: nextId, actionsThisTurn: 0, cardsPlayedThisTurn: 0, activeSkipCount: 0, preTurnCentreSuit: newState.discardTopCard?.effectiveSuit);
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
        _lastMove = LastMoveInfo(playerName: drawPlayerName);
      });
      _engineTimer.cancel();
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        _startTimer();
      }
    }
  }

  // ── AI turn ────────────────────────────────────────────────────────

  int _randomAiDelayMs(int min, int max) {
    if (max <= min) return min;
    return min + _aiDelayRng.nextInt((max - min) + 1);
  }

  Future<void> _scheduleAiTurn(String aiId) async {
    if (widget.isTournamentMode && _tournamentFinishedPlayerIds.contains(aiId)) {
      final nextId = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: aiId,
      );
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        _startTimer();
      }
      return;
    }
    if (_aiThinking) return;
    setState(() => _aiThinking = true);

    final hasPlayable = aiHasPlayableTurn(state: _offlineState, aiPlayerId: aiId);
    final baseThinkMs = _randomAiDelayMs(1200, 2500);

    // Forced draw pacing: pause before draw and a brief pause after.
    if (!hasPlayable) {
      await Future.delayed(const Duration(milliseconds: 1000));
    } else {
      await Future.delayed(Duration(milliseconds: baseThinkMs));
    }
    if (!mounted) return;

    final result = aiTakeTurn(
      state: _offlineState,
      aiPlayerId: aiId,
      cardFactory: _makeCards,
    );

    final playedByAi = result.playedCards;

    // Add extra thought time for Ace/Joker declaration turns.
    if (playedByAi.isNotEmpty &&
        (playedByAi.first.effectiveRank == Rank.ace || playedByAi.first.isJoker)) {
      await Future.delayed(Duration(milliseconds: _randomAiDelayMs(1500, 3000)));
    }

    // Multi-card pacing gap so chained plays are not instantaneous.
    if (playedByAi.length > 1) {
      for (int i = 1; i < playedByAi.length; i++) {
        await Future.delayed(Duration(milliseconds: _randomAiDelayMs(400, 700)));
        if (!mounted) return;
      }
    }

    if (!hasPlayable) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
    }

    // Track AI-played cards into discard pile.
    if (playedByAi.isNotEmpty) {
      _discardPile.addAll(playedByAi);
    }

    final aiPlayerName = _offlineState.playerById(aiId)?.displayName ?? aiId;
    final aiLastMove = playedByAi.isNotEmpty
        ? LastMoveInfo(
            playerName: aiPlayerName,
            cardLabel: playedByAi.first.shortLabel,
          )
        : LastMoveInfo(playerName: aiPlayerName);

    if (_checkWin(aiId, result.state)) return;

    var finalState = result.state;
    var nextId = finalState.currentPlayerId;
    nextId = _resolveTournamentNextPlayerId(finalState, nextId);
    if (nextId != finalState.currentPlayerId) {
      finalState = finalState.copyWith(currentPlayerId: nextId);
    }
    if (nextId != aiId) {
      finalState = finalState.copyWith(
        preTurnCentreSuit: finalState.discardTopCard?.effectiveSuit,
      );
    }

    setState(() {
      _offlineState = finalState.copyWith(drawPileCount: _drawPile.length);
      _aiThinking = false;
      _lastMove = aiLastMove;
    });

    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
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
    game_audio.AudioService.instance.playSound(GameSound.shuffleDeck);

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
    if (!shouldShowStandardWinOverlay(isTournamentMode: widget.isTournamentMode)) {
      return _handleTournamentPlayerFinished(lastActorId, state);
    }

    if (!wouldConfirmWin(state)) return false;

    final winner = state.players
        .where((p) => p.hand.isEmpty && p.cardCount == 0)
        .firstOrNull!;
    if (winner.id == OfflineGameState.localId) {
      CardBackService.instance.registerWin();
    }
    game_audio.AudioService.instance.playSound(GameSound.playerWin);

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

  bool _handleTournamentPlayerFinished(String playerId, GameState state) {
    if (_tournamentFinishedPlayerIds.contains(playerId)) return false;

    final didFinish = _didPlayerFinish(playerId, state);
    if (!didFinish) return false;

    _tournamentFinishedPlayerIds.add(playerId);
    final finishPosition = _tournamentFinishedPlayerIds.length;
    final playerName = state.playerById(playerId)?.displayName ?? playerId;
    widget.onPlayerFinished(playerName, finishPosition);
    if (_tournamentFinishedPlayerIds.length < state.players.length) {
      game_audio.AudioService.instance.playSound(GameSound.tournamentQualify);
    }

    if (_tournamentFinishedPlayerIds.length == state.players.length) {
      _tournamentRoundComplete = true;
      final eliminatedPlayerId = _tournamentFinishedPlayerIds.last;
      game_audio.AudioService.instance.playSound(GameSound.tournamentEliminate);

      _engineTimer.cancel();
      setState(() {
        _offlineState = state.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        _aiThinking = false;
      });

      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).pop(
          TournamentRoundGameResult(
            finishedPlayerIds:
                List<String>.from(_tournamentFinishedPlayerIds),
            eliminatedPlayerId: eliminatedPlayerId,
          ),
        );
      });
      return true;
    }

    final nextId = _nextTournamentActivePlayerId(
      state: state,
      startAfterPlayerId: playerId,
    );

    _engineTimer.cancel();
    setState(() {
      _offlineState = state.copyWith(
        currentPlayerId: nextId,
        actionsThisTurn: 0,
        cardsPlayedThisTurn: 0,
        lastPlayedThisTurn: null,
        activeSkipCount: 0,
        preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
        drawPileCount: _drawPile.length,
      );
      _selectedCardId = null;
      _aiThinking = false;
    });

    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
    return true;
  }

  bool _didPlayerFinish(String playerId, GameState state) {
    return canConfirmPlayerWin(state: state, playerId: playerId);
  }

  String _nextTournamentActivePlayerId({
    required GameState state,
    required String startAfterPlayerId,
  }) {
    final players = state.players;
    if (players.isEmpty) return startAfterPlayerId;

    var index = players.indexWhere((p) => p.id == startAfterPlayerId);
    if (index < 0) index = 0;

    final step = state.direction == PlayDirection.clockwise ? 1 : -1;
    for (var i = 0; i < players.length; i++) {
      index = (index + step) % players.length;
      if (index < 0) index += players.length;
      final candidateId = players[index].id;
      if (!_tournamentFinishedPlayerIds.contains(candidateId)) {
        return candidateId;
      }
    }

    return startAfterPlayerId;
  }

  String _resolveTournamentNextPlayerId(GameState state, String nextId) {
    if (!widget.isTournamentMode) return nextId;
    if (!_tournamentFinishedPlayerIds.contains(nextId)) return nextId;
    return _nextTournamentActivePlayerId(
      state: state,
      startAfterPlayerId: nextId,
    );
  }

  Map<String, String> _buildTournamentStatusBadges() {
    if (!widget.isTournamentMode) return const <String, String>{};

    final badges = <String, String>{};
    for (final playerId in _tournamentFinishedPlayerIds) {
      final isEliminated = _tournamentRoundComplete &&
          playerId == _tournamentFinishedPlayerIds.last;
      badges[playerId] = isEliminated ? '✗ Eliminated' : '✓ Qualified';
    }
    return badges;
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
