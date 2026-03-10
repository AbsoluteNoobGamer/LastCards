import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';

import '../../domain/usecases/offline_game_engine.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart';
import '../../data/datasources/offline_game_state_datasource.dart';
import '../../domain/entities/player.dart';
import '../../../../shared/engine/game_turn_timer.dart';
import '../controllers/connection_provider.dart';
import '../controllers/game_provider.dart';
import '../../data/datasources/websocket_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/services/card_back_service.dart';
import '../../../../core/models/move_log_entry.dart';
import '../../../../core/models/game_event.dart';
import '../../../../core/providers/theme_provider.dart';
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
import '../../../../features/single_player/providers/single_player_session_provider.dart';

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
  final AiDifficulty? aiDifficulty;

  const TableScreen({
    this.totalPlayers = 2,
    this.isTournamentMode = false,
    this.onPlayerFinished = _defaultOnPlayerFinished,
    this.tournamentPlayerNameByTableId = const <String, String>{},
    this.debugInitialOfflineState,
    this.debugInitialDrawPile,
    this.debugSkipDealAnimation = false,
    this.aiDifficulty,
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

  /// Latest move log entries (newest first, max 3).
  final List<MoveLogEntry> _moveLogEntries = <MoveLogEntry>[];

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
  /// In online mode we don't have the full discard list; track count for stack depth.
  int _onlineDiscardCount = 1;
  bool _onlineWinDialogShown = false;
  // ── Turn timer ────────────────────────────────────────────────────
  late final GameTurnTimer _engineTimer = GameTurnTimer();
  StreamSubscription<int>? _timerWarningSub;
  StreamSubscription<CardPlayedEvent>? _onlineCardPlaysSub;
  StreamSubscription<CardDrawnEvent>? _onlineCardDrawsSub;
  StreamSubscription<ErrorEvent>? _onlineErrorsSub;
  StreamSubscription<dynamic>? _onlineTurnTimeoutSub;
  StreamSubscription<dynamic>? _onlineReshuffleSub;
  bool _timerWarningPlayed = false;
  bool _onlineDealAnimationStarted = false;

  /// Toggled (not set) each time a reshuffle fires so DrawPileWidget can
  /// play the shuffle animation even on repeated reshuffles.
  final ValueNotifier<bool> _reshuffleNotifier = ValueNotifier<bool>(false);

  /// AI opponent configurations for this game session (names, personality,
  /// avatar colors). Regenerated each time [_initNewGame] is called.
  List<AiPlayerConfig> _aiPlayerConfigs = [];

  /// The chat notification currently shown in the center of the screen.
  /// Null when no notification is active.
  ({AiPlayerConfig config, String message})? _activeChatItem;

  /// Keeps the last chat item alive so the fade-out animation can finish
  /// before the widget disappears.
  ({AiPlayerConfig config, String message})? _lastChatItem;

  static const _chatBubbleDuration = Duration(milliseconds: 4000);
  final math.Random _chatRng = math.Random();
  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    _initNewGame();
    _subscribeToOnlineMoveLogIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _audioService.startBgm();
    });
  }

  void _subscribeToOnlineMoveLogIfNeeded() {
    if (ref.read(gameStateProvider) == null) return;
    final handler = ref.read(gameEventHandlerProvider);

    // ── Deal animation: fire once on the first state_snapshot ──────────────
    // The first snapshot signals the game is live and all hands are dealt.
    // We mirror the offline deal animation so online mode feels identical.
    handler.stateSnapshots.first.then((e) {
      if (!mounted || _onlineDealAnimationStarted) return;
      _onlineDealAnimationStarted = true;
      // Sync player zone keys from the live state (may have changed since init)
      setState(() {
        for (final p in e.gameState.players) {
          _playerZoneKeys.putIfAbsent(p.id, () => GlobalKey());
        }
        _offlineState = e.gameState;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDealAnimation();
      });
    });

    _onlineCardPlaysSub = handler.cardPlays.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      final actions = e.cards
          .map((c) => MoveCardAction(card: c))
          .toList();
      setState(() {
        _onlineDiscardCount++;
        _pushMoveLog(MoveLogEntry.play(
          playerId: e.playerId,
          playerName: name,
          cardActions: actions,
          skippedPlayerNames: const [],
          turnContinues: false,
        ));
      });
    });

    _onlineCardDrawsSub = handler.cardDraws.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      setState(() {
        _pushMoveLog(MoveLogEntry.draw(
          playerId: e.playerId,
          playerName: name,
          drawCount: 1,
        ));
      });
    });

    _onlineErrorsSub = handler.errors.listen((e) {
      if (mounted) _showError(e.message);
    });

    // ── Turn timeout ────────────────────────────────────────────────────────
    // Server forced a draw and ended the turn. Show a snackbar and play the
    // timer-expired sound so online mode matches the offline timeout feedback.
    _onlineTurnTimeoutSub = handler.turnTimeouts.listen((e) {
      if (!mounted) return;
      game_audio.AudioService.instance.playSound(GameSound.timerExpired);
      _engineTimer.cancel();
      final state = ref.read(gameStateProvider);
      final name = state?.playerById(e.playerId)?.displayName ?? e.playerId;
      final isLocal = state?.localPlayer?.id == e.playerId;
      final msg = isLocal
          ? 'Timeout! Drew ${e.cardsDrawn} card(s) as penalty.'
          : '$name timed out.';
      _showError(msg);
    });

    // ── Reshuffle ───────────────────────────────────────────────────────────
    // Server reshuffled the deck. Toggle the notifier so DrawPileWidget plays
    // its animation and show the same snackbar as offline mode.
    _onlineReshuffleSub = handler.reshuffles.listen((e) {
      if (!mounted) return;
      game_audio.AudioService.instance.playSound(GameSound.shuffleDeck);
      setState(() {
        _reshuffleNotifier.value = !_reshuffleNotifier.value;
      });
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
    });

    // Start turn timer when it's our turn in online mode (e.g. game just started)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(gameStateProvider) != null &&
          ref.read(isLocalTurnProvider)) {
        _startTimer();
      }
    });
  }

  void _initNewGame() {
    final liveState = ref.read(gameStateProvider);
    if (liveState != null) {
      // Online mode: server already sent state. Don't run deal animation or AI.
      _offlineState = liveState;
      _drawPile = [];
      _discardPile.clear();
      _onlineDiscardCount = 1; // one card already on discard (discardTopCard)
      _onlineWinDialogShown = false;
      if (liveState.discardTopCard != null) {
        _discardPile.add(liveState.discardTopCard!);
      }
      _moveLogEntries.clear();
      _isDealing = false;
      _playerZoneKeys.clear();
      for (final p in liveState.players) {
        _playerZoneKeys[p.id] = GlobalKey();
      }
      final localStart = liveState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      _handOrder = localStart?.hand.map((c) => c.id).toList() ?? [];
      return;
    }

    final hasDebugState = widget.debugInitialOfflineState != null &&
        widget.debugInitialDrawPile != null;
    GameState state;
    List<CardModel> drawPile;

    if (hasDebugState) {
      state = widget.debugInitialOfflineState!;
      drawPile = List<CardModel>.from(widget.debugInitialDrawPile!);
    } else {
      // Generate fresh AI player configs for this session (names, personalities,
      // avatar colours). Always generated — tournament mode uses them for
      // personality scoring, avatars, and chat bubbles.
      _aiPlayerConfigs = AiPlayerConfig.generateForGame(
        count: widget.totalPlayers - 1,
        seed: DateTime.now().millisecondsSinceEpoch,
      );
      _activeChatItem = null;
      _lastChatItem = null;

      final aiNameMap = {
        for (final c in _aiPlayerConfigs) c.playerId: c.name,
      };

      final seeded = OfflineGameState.buildWithDeck(
        totalPlayers: widget.totalPlayers,
        aiNames: aiNameMap,
      );
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
      ..add(
          state.discardTopCard!); // seed discard with post-effect starting card
    _moveLogEntries.clear();
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
    _onlineCardPlaysSub?.cancel();
    _onlineCardDrawsSub?.cancel();
    _onlineErrorsSub?.cancel();
    _onlineTurnTimeoutSub?.cancel();
    _onlineReshuffleSub?.cancel();
    _engineTimer.dispose();
    _reshuffleNotifier.dispose();
    // BGM stop
    _audioService.stopBgm();
    super.dispose();
  }

  void _startTimer({bool playTurnSound = true}) {
    _timerWarningPlayed = false;
    _timerWarningSub?.cancel();
    _timerWarningSub = _engineTimer.timeRemainingStream.listen((secondsLeft) {
      if (!_timerWarningPlayed && secondsLeft > 0 && secondsLeft <= 10) {
        _timerWarningPlayed = true;
        game_audio.AudioService.instance.playSound(GameSound.timerWarning);
      }
    });
    if (playTurnSound) {
      game_audio.AudioService.instance.playSound(GameSound.turnStart);
    }
    _engineTimer.start(() {
      if (!mounted) return;
      // Online mode: server handles timeout authoritatively via its own 60s
      // timer. Just cancel the local timer and let the server's turn_timeout
      // event drive the behavior.
      if (ref.read(gameStateProvider) != null) {
        _engineTimer.cancel();
        return;
      }
      if (widget.isTournamentMode &&
          _tournamentFinishedPlayerIds
              .contains(_offlineState.currentPlayerId)) {
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

    // Play draw sound for timeout penalty.
    game_audio.AudioService.instance.playSound(GameSound.cardDraw);

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
      queenSuitLock: null,
    );

    final localAfter = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    setState(() {
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localAfter != null) _syncHandOrder(localAfter.hand);
      _pushMoveLog(MoveLogEntry.timeoutDraw(
        playerId: OfflineGameState.localId,
        playerName:
            _offlineState.playerById(OfflineGameState.localId)?.displayName ??
                OfflineGameState.localId,
        drawCount: 1,
      ));
    });

    _engineTimer.cancel();
    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId);
    } else {
      _startTimer();
    }
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

    Suit? chosenAceSuit;
    // Rule 1: Ace played alone triggers the suit selector at End Turn
    if (_offlineState.discardTopCard?.effectiveRank == Rank.ace &&
        _offlineState.cardsPlayedThisTurn == 1 &&
        mounted) {
      chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AceSuitPickerSheet(),
      );
      if (!mounted) return;

      if (chosenAceSuit == null) {
        _startTimer(); // Resume the timer if they dismissed the sheet
        return; // Don't end turn yet
      }

      setState(() {
        _offlineState = _offlineState.copyWith(suitLock: chosenAceSuit);
        _applyAceDeclarationToLatestPlay(
          playerId: OfflineGameState.localId,
          chosenSuit: chosenAceSuit!,
        );
      });
    }

    var nextId = nextPlayerId(state: _offlineState);
    nextId = _resolveTournamentNextPlayerId(_offlineState, nextId);
    setState(() {
      _finalizeTurnLogForPlayer(OfflineGameState.localId);
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

    // In online mode, start turn timer when it becomes our turn (e.g. after opponent ends)
    ref.listen(isLocalTurnProvider, (prev, next) {
      if (ref.read(gameStateProvider) == null || !mounted) return;
      if (next == true && prev == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(isLocalTurnProvider)) _startTimer();
        });
      } else if (next == false) {
        _engineTimer.cancel();
      }
    });

    // Online: show win overlay when game ends (same as single-player).
    ref.listen<GameState?>(gameStateProvider, (prev, next) {
      if (next == null || next.phase != GamePhase.ended ||
          _onlineWinDialogShown || !mounted) return;
      // winnerId may be null (not yet set) or empty (player disconnected).
      final hasWinner = next.winnerId != null && next.winnerId!.isNotEmpty;
      final winner = hasWinner ? next.playerById(next.winnerId!) : null;
      setState(() => _onlineWinDialogShown = true);
      final navigator = Navigator.of(context);
      if (hasWinner && winner != null) {
        game_audio.AudioService.instance.playSound(GameSound.playerWin);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _WinDialog(
              winnerName: winner.displayName,
              isLocalWin: next.localPlayer?.id == next.winnerId,
              onPlayAgain: () {
                navigator.pop(); // close dialog
                navigator.pop(); // leave table
              },
              isOnlineMode: true,
            ),
          );
        });
      } else {
        // Game ended without a winner (e.g. player disconnected).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: Colors.grey.shade900,
              title: const Text(
                'Game Ended',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'A player disconnected. The game has ended.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    navigator.pop(); // close dialog
                    navigator.pop(); // leave table
                  },
                  child: const Text('BACK TO MENU'),
                ),
              ],
            ),
          );
        });
      }
    });

    // Online: server requests suit choice after local player played an Ace.
    // Show the same suit picker sheet used by offline mode, then send the choice.
    ref.listen<bool>(pendingSuitChoiceProvider, (prev, next) {
      if (!next || !mounted) return;
      // Only show for the local player's own Ace — server only sends this to
      // the acting player, so no extra guard is needed.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final chosenSuit = await showModalBottomSheet<Suit>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => const _AceSuitPickerSheet(),
        );
        if (!mounted) return;
        if (chosenSuit != null) {
          ref.read(gameNotifierProvider.notifier).declareSuit(chosenSuit.name);
        }
        // If dismissed without a choice the server will eventually time out
        // the turn — no client-side fallback needed.
      });
    });

    // Online: server requests joker declaration after local player played a Joker.
    ref.listen<bool>(pendingJokerResolutionProvider, (prev, next) {
      if (!next || !mounted) return;
      final jokerCardId =
          ref.read(gameNotifierProvider).pendingJokerCardId;
      if (jokerCardId == null) return;
      final gameState = ref.read(gameStateProvider);
      if (gameState == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final jokerContext =
            jokerPlayContextFromCardsPlayed(gameState.cardsPlayedThisTurn);
        final jokerAnchor =
            jokerContext == JokerPlayContext.midTurnContinuance
                ? (gameState.lastPlayedThisTurn ?? gameState.discardTopCard!)
                : gameState.discardTopCard!;
        final validOptions = getValidJokerOptions(
          state: gameState,
          discardTop: gameState.discardTopCard!,
          context: jokerContext,
          contextTopCard: jokerAnchor,
        );
        if (validOptions.isEmpty || !mounted) return;
        final activeSequenceSuit =
            jokerContext == JokerPlayContext.midTurnContinuance
                ? jokerAnchor.effectiveSuit
                : null;
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
        if (chosenCard != null) {
          ref.read(gameNotifierProvider.notifier).declareJoker(
            jokerCardId: jokerCardId,
            suitName: chosenCard.suit.name,
            rankName: chosenCard.rank.name,
          );
        }
      });
    });

    final appTheme = ref.watch(themeProvider).theme;
    return Scaffold(
      appBar: null,
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: appTheme.backgroundDeep,
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
                            : (isMyTurn &&
                                validateEndTurn(gameState) == null),
                        isDealing: _isDealing,
                        visibleCardCounts: _visibleCardCounts,
                        drawPileKey: _drawPileKey,
                        playerZoneKeys: _playerZoneKeys,
                        onCardTap: _onCardTap,
                        onDrawTap: isOfflineMode
                            ? () => _offlineDrawCard(OfflineGameState.localId)
                            : _onDrawTap,
                        onHandReorder: _onHandReorder,
                        onEndTurnTap: isOfflineMode
                            ? _endTurn
                            : () {
                                ref.read(gameNotifierProvider.notifier).endTurn();
                              },
                        isOffline: isOfflineMode,
                        discardPileCount: isOfflineMode
                            ? _discardPile.length
                            : _onlineDiscardCount,
                        reshuffleNotifier: _reshuffleNotifier,
                        timeRemainingStream: _engineTimer.timeRemainingStream,
                        tournamentStatusBadges: _buildTournamentStatusBadges(),
                        finishedPlayerIds: _tournamentFinishedPlayerIds.toSet(),
                        aiConfigs: {
                          for (final c in _aiPlayerConfigs) c.playerId: c,
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── Game log panel (centred, below player avatars) ───────────
              if (_moveLogEntries.isNotEmpty)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 175,
                  left: MediaQuery.of(context).size.width * 0.08,
                  right: MediaQuery.of(context).size.width * 0.08,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: LastMovePanelWidget(entries: _moveLogEntries),
                    ),
                  ),
                ),

              // ── AI chat notification banner ─────────────────────────────
              if (isOfflineMode)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 108,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _activeChatItem != null ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        child: AnimatedSlide(
                          offset: _activeChatItem != null
                              ? Offset.zero
                              : const Offset(0, -0.4),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutBack,
                          child: _lastChatItem != null
                              ? _AiChatBanner(
                                  config: _lastChatItem!.config,
                                  message: _lastChatItem!.message,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Floating back control (single-player and online) ────────────
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
                        tooltip: isOfflineMode ? 'Exit game' : 'Leave game',
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

              // ── HUD overlay (suit badge, penalty, queen lock) ───────────
              // Placed at ~63 % of screen height — the empty gap between the
              // draw/discard pile area and the gold TurnTimerBar.
              // Placed last (before the deal overlay) for highest z-index.
              Positioned(
                top: MediaQuery.of(context).size.height * 0.63,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: HudOverlayWidget(
                      activeSuit: gameState.suitLock,
                      queenSuitLock: gameState.queenSuitLock,
                      penaltyCount: penaltyCount,
                      penaltyTargetPosition: penaltyCount > 0
                          ? gameState.players
                              .where((p) =>
                                  p.id == nextPlayerId(state: gameState))
                              .firstOrNull
                              ?.tablePosition
                          : null,
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

  /// Online play: same rules as single-player — validate, then Joker/Ace flows or send play.
  Future<void> _onPlayTap({required String cardId}) async {
    if (!ref.read(isLocalTurnProvider)) return;
    final gameState = ref.read(gameStateProvider);
    if (gameState == null) return;
    final local = gameState.localPlayer;
    if (local == null) return;
    final card = local.hand.where((c) => c.id == cardId).firstOrNull;
    if (card == null) return;

    final err = validatePlay(
      cards: [card],
      discardTop: gameState.discardTopCard!,
      state: gameState,
    );
    if (err != null) {
      _showError(err);
      return;
    }

    // Joker: show sheet, then send declare_joker (same flow as single-player).
    if (card.isJoker && mounted) {
      final jokerContext =
          jokerPlayContextFromCardsPlayed(gameState.cardsPlayedThisTurn);
      final jokerAnchor =
          jokerContext == JokerPlayContext.midTurnContinuance
              ? (gameState.lastPlayedThisTurn ?? gameState.discardTopCard!)
              : gameState.discardTopCard!;
      final validOptions = getValidJokerOptions(
        state: gameState,
        discardTop: gameState.discardTopCard!,
        context: jokerContext,
        contextTopCard: jokerAnchor,
      );
      if (validOptions.isEmpty) {
        _showError('No valid moves available for the Joker right now.');
        return;
      }
      setState(() => _selectedCardId = cardId);
      final activeSequenceSuit =
          jokerContext == JokerPlayContext.midTurnContinuance
              ? jokerAnchor.effectiveSuit
              : null;
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
      setState(() => _selectedCardId = null);
      if (chosenCard == null) return;
      ref.read(gameNotifierProvider.notifier).declareJoker(
        jokerCardId: cardId,
        suitName: chosenCard.suit.name,
        rankName: chosenCard.rank.name,
      );
      return;
    }

    // Ace as first card of turn: show suit picker, then send play_cards with declaredSuit.
    if (card.effectiveRank == Rank.ace &&
        gameState.actionsThisTurn == 0 &&
        mounted) {
      setState(() => _selectedCardId = cardId);
      final chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AceSuitPickerSheet(),
      );
      if (!mounted) return;
      setState(() => _selectedCardId = null);
      if (chosenAceSuit == null) return;
      ref.read(gameNotifierProvider.notifier).playCards(
        [cardId],
        declaredSuit: chosenAceSuit.name,
      );
      return;
    }

    // Normal play
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

      final activeSequenceSuit =
          jokerContext == JokerPlayContext.midTurnContinuance
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

      final previousState = _offlineState;
      var newState = applyPlay(
        state: _offlineState,
        playerId: playerId,
        cards: [assignedJoker],
      );
      _engineTimer.cancel();

      // Play card sounds for Joker play.
      game_audio.AudioService.instance.playSound(GameSound.cardPlace);
      game_audio.AudioService.instance.playSound(GameSound.specialJoker);

      _discardPile.add(assignedJoker);

      final localInNew = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      final jokerPlayerName =
          _offlineState.playerById(playerId)?.displayName ?? playerId;
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localInNew != null) _syncHandOrder(localInNew.hand);
        _recordPlayMove(
          playerId: playerId,
          playerName: jokerPlayerName,
          playedCards: [assignedJoker],
          beforeState: previousState,
          afterState: newState,
        );
      });

      _reshuffleCentrePileIntoDrawPile();
      if (_checkWin(playerId, newState)) return;

      // Allow the player to continue their turn (stack more cards if they want).
      return;
    }

    // Apply play + special effects
    final previousState = _offlineState;
    var newState =
        applyPlay(state: _offlineState, playerId: playerId, cards: played);
    _engineTimer.cancel();

    // Play card sounds (moved from game_engine to UI layer for server compat).
    game_audio.AudioService.instance.playSound(GameSound.cardPlace);
    for (final c in played) {
      final s = _offlineSpecialSoundFor(c);
      if (s != null) game_audio.AudioService.instance.playSound(s);
    }

    _discardPile.addAll(played);

    final localInNew = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;
    final playPlayerName =
        _offlineState.playerById(playerId)?.displayName ?? playerId;
    setState(() {
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localInNew != null) _syncHandOrder(localInNew.hand);
      _recordPlayMove(
        playerId: playerId,
        playerName: playPlayerName,
        playedCards: played,
        beforeState: previousState,
        afterState: newState,
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
  void _applyInvalidPlayPenalty(
      String playerId, List<CardModel> attemptedCards) {
    _showError('Invalid play! Drawing 2 cards as penalty.');

    // Step 2: draw up to 2 cards (respects remaining pile size).
    final drawCount = math.min(2, _drawPile.length);
    var newState = applyDraw(
      state: _offlineState,
      playerId: playerId,
      count: drawCount,
      cardFactory: _makeCards,
    );

    // Play draw sound for penalty.
    game_audio.AudioService.instance.playSound(GameSound.cardDraw);
    game_audio.AudioService.instance.playSound(GameSound.penaltyDraw);

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

    // Play draw sounds (moved from game_engine to UI layer for server compat).
    game_audio.AudioService.instance.playSound(GameSound.cardDraw);
    if (isPenaltyDraw) {
      game_audio.AudioService.instance.playSound(GameSound.penaltyDraw);
    }

    final localAfterDraw = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    if (isQueenPenaltyDraw || isPenaltyDraw) {
      final penaltyPlayerName =
          _offlineState.playerById(playerId)?.displayName ?? playerId;
      var nextId = nextPlayerId(state: newState);
      nextId = _resolveTournamentNextPlayerId(newState, nextId);
      newState = newState.copyWith(
          currentPlayerId: nextId,
          actionsThisTurn: 0,
          cardsPlayedThisTurn: 0,
          activeSkipCount: 0,
          preTurnCentreSuit: newState.discardTopCard?.effectiveSuit);
      if (isQueenPenaltyDraw) {
        newState = newState.copyWith(queenSuitLock: null);
      }
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
        _pushMoveLog(MoveLogEntry.draw(
          playerId: playerId,
          playerName: penaltyPlayerName,
          drawCount: drawCount,
        ));
      });
      _engineTimer.cancel();
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        _startTimer();
      }
    } else {
      // Voluntary draw (no valid moves) — auto-end turn per the rules.
      final drawPlayerName =
          _offlineState.playerById(playerId)?.displayName ?? playerId;
      var nextId = nextPlayerId(state: newState);
      nextId = _resolveTournamentNextPlayerId(newState, nextId);
      newState = newState.copyWith(
          currentPlayerId: nextId,
          actionsThisTurn: 0,
          cardsPlayedThisTurn: 0,
          activeSkipCount: 0,
          preTurnCentreSuit: newState.discardTopCard?.effectiveSuit);
      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
        _pushMoveLog(MoveLogEntry.draw(
          playerId: playerId,
          playerName: drawPlayerName,
          drawCount: drawCount,
        ));
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
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(aiId)) {
      final nextId = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: aiId,
      );
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId);
      } else {
        // The active player's turn is reached via a skip chain — suppress the
        // redundant turnStart here; the sound will play when the turn genuinely
        // begins through a non-skip path (e.g. end of a real AI turn).
        _startTimer(playTurnSound: false);
      }
      return;
    }
    if (_aiThinking) return;
    setState(() => _aiThinking = true);

    final hasPlayable =
        aiHasPlayableTurn(state: _offlineState, aiPlayerId: aiId);
    final diffMult = widget.aiDifficulty?.delayMultiplier ?? 1.0;
    final baseThinkMs = (_randomAiDelayMs(1200, 2500) * diffMult).round();

    // Forced draw pacing: pause before draw and a brief pause after.
    if (!hasPlayable) {
      final drawPauseMs = (1000 * diffMult).round();
      await Future.delayed(Duration(milliseconds: drawPauseMs));
    } else {
      await Future.delayed(Duration(milliseconds: baseThinkMs));
    }
    if (!mounted) return;

    final stateBeforeAiTurn = _offlineState;
    final aiConfig =
        _aiPlayerConfigs.where((c) => c.playerId == aiId).firstOrNull;
    final result = aiTakeTurn(
      state: _offlineState,
      aiPlayerId: aiId,
      cardFactory: _makeCards,
      personality: aiConfig?.personality,
    );

    final playedByAi = result.playedCards;

    // Add extra thought time for Ace/Joker declaration turns.
    if (playedByAi.isNotEmpty &&
        (playedByAi.first.effectiveRank == Rank.ace ||
            playedByAi.first.isJoker)) {
      await Future.delayed(
          Duration(milliseconds: _randomAiDelayMs(1500, 3000)));
    }

    // Multi-card pacing gap so chained plays are not instantaneous.
    if (playedByAi.length > 1) {
      for (int i = 1; i < playedByAi.length; i++) {
        await Future.delayed(
            Duration(milliseconds: _randomAiDelayMs(400, 700)));
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

    // Chat bubble: trigger on special plays or at random (30% base chance).
    if (aiConfig != null && playedByAi.isNotEmpty) {
      _maybeTriggerChatBubble(
        aiId: aiId,
        config: aiConfig,
        playedCards: playedByAi,
        resultState: result.state,
      );
    }

    setState(() {
      _offlineState = finalState.copyWith(drawPileCount: _drawPile.length);
      _aiThinking = false;
      if (playedByAi.isNotEmpty) {
        _recordPlayMove(
          playerId: aiId,
          playerName: aiPlayerName,
          playedCards: playedByAi,
          beforeState: stateBeforeAiTurn,
          afterState: result.preTurnAdvanceState,
          turnContinuesOverride: false,
        );
      } else {
        _pushMoveLog(MoveLogEntry.draw(
          playerId: aiId,
          playerName: aiPlayerName,
          drawCount: stateBeforeAiTurn.activePenaltyCount > 0
              ? stateBeforeAiTurn.activePenaltyCount
              : 1,
        ));
      }
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

    if (!mounted) return;

    // ── 4 & 5. Update counter + trigger animation ────────────────────────────
    setState(() {
      _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
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
    if (!shouldShowStandardWinOverlay(
        isTournamentMode: widget.isTournamentMode)) {
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
            finishedPlayerIds: List<String>.from(_tournamentFinishedPlayerIds),
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

  void _recordPlayMove({
    required String playerId,
    required String playerName,
    required List<CardModel> playedCards,
    required GameState beforeState,
    required GameState afterState,
    bool? turnContinuesOverride,
  }) {
    final actions = <MoveCardAction>[];
    for (var i = 0; i < playedCards.length; i++) {
      final card = playedCards[i];
      final declaredAceSuit = (card.effectiveRank == Rank.ace &&
              i == 0 &&
              beforeState.actionsThisTurn == 0 &&
              afterState.suitLock != null)
          ? afterState.suitLock
          : null;
      actions.add(MoveCardAction(card: card, aceDeclaredSuit: declaredAceSuit));
    }

    final entry = MoveLogEntry.play(
      playerId: playerId,
      playerName: playerName,
      cardActions: actions,
      skippedPlayerNames: _skippedPlayersForCurrentTurn(afterState),
      turnContinues:
          turnContinuesOverride ?? (afterState.currentPlayerId == playerId),
    );

    if (_moveLogEntries.isNotEmpty) {
      final top = _moveLogEntries.first;
      if (top.type == MoveLogEntryType.play &&
          top.playerId == playerId &&
          top.turnContinues) {
        _moveLogEntries[0] = top.copyWith(
          cardActions: [...top.cardActions, ...entry.cardActions],
          skippedPlayerNames: entry.skippedPlayerNames,
          turnContinues: entry.turnContinues,
        );
        return;
      }
    }
    _pushMoveLog(entry);
  }

  void _applyAceDeclarationToLatestPlay({
    required String playerId,
    required Suit chosenSuit,
  }) {
    if (_moveLogEntries.isEmpty) return;
    final top = _moveLogEntries.first;
    if (top.type != MoveLogEntryType.play || top.playerId != playerId) return;

    final updatedActions = [...top.cardActions];
    for (var i = updatedActions.length - 1; i >= 0; i--) {
      if (updatedActions[i].card.effectiveRank == Rank.ace) {
        updatedActions[i] =
            updatedActions[i].copyWith(aceDeclaredSuit: chosenSuit);
        _moveLogEntries[0] = top.copyWith(cardActions: updatedActions);
        return;
      }
    }
  }

  void _finalizeTurnLogForPlayer(String playerId) {
    if (_moveLogEntries.isEmpty) return;
    final top = _moveLogEntries.first;
    if (top.type == MoveLogEntryType.play && top.playerId == playerId) {
      _moveLogEntries[0] = top.copyWith(turnContinues: false);
    }
  }

  List<String> _skippedPlayersForCurrentTurn(GameState state) {
    final skipCount = state.activeSkipCount;
    if (skipCount <= 0) return const <String>[];
    if (state.lastPlayedThisTurn?.effectiveRank != Rank.eight) {
      return const <String>[];
    }

    final players = state.players;
    final currentIndex =
        players.indexWhere((p) => p.id == state.currentPlayerId);
    if (currentIndex < 0) return const <String>[];

    final step = state.direction == PlayDirection.clockwise ? 1 : -1;
    var cursor = currentIndex;
    final skipped = <String>[];
    for (var i = 0; i < skipCount; i++) {
      cursor = (cursor + step) % players.length;
      if (cursor < 0) cursor += players.length;
      skipped.add(players[cursor].displayName);
    }
    return skipped;
  }

  void _pushMoveLog(MoveLogEntry entry) {
    _moveLogEntries.insert(0, entry);
    if (_moveLogEntries.length > 3) {
      _moveLogEntries.removeRange(3, _moveLogEntries.length);
    }
  }

  static GameSound? _offlineSpecialSoundFor(CardModel card) {
    switch (card.effectiveRank) {
      case Rank.two:
        return GameSound.specialTwo;
      case Rank.jack:
        return card.isBlackJack
            ? GameSound.specialBlackJack
            : GameSound.specialRedJack;
      case Rank.king:
        return GameSound.specialKing;
      case Rank.ace:
        return GameSound.specialAce;
      case Rank.queen:
        return GameSound.specialQueen;
      case Rank.eight:
        return GameSound.specialEight;
      case Rank.joker:
        return GameSound.specialJoker;
      default:
        return null;
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

  // ── AI chat bubbles ────────────────────────────────────────────────────────

  void _maybeTriggerChatBubble({
    required String aiId,
    required AiPlayerConfig config,
    required List<CardModel> playedCards,
    required GameState resultState,
  }) {
    bool shouldChat = false;

    // Last card — AI is about to win.
    final aiAfter = resultState.players.where((p) => p.id == aiId).firstOrNull;
    if (aiAfter != null && aiAfter.cardCount <= 1) {
      shouldChat = true;
    }

    // Aggressive personality fires on penalty cards.
    if (!shouldChat &&
        config.personality == AiPersonality.aggressive &&
        playedCards.any((c) => c.isBlackJack || c.effectiveRank == Rank.two)) {
      shouldChat = true;
    }

    // Tricky personality fires on skips / kings / jokers.
    if (!shouldChat &&
        config.personality == AiPersonality.tricky &&
        playedCards.any((c) =>
            c.effectiveRank == Rank.eight ||
            c.effectiveRank == Rank.king ||
            c.isJoker)) {
      shouldChat = true;
    }

    // 20% random chance for any remaining plays.
    if (!shouldChat && _chatRng.nextDouble() < 0.20) shouldChat = true;

    if (shouldChat) {
      _triggerChatBubble(aiId, config.randomChatLine(_chatRng));
    }
  }

  void _triggerChatBubble(String aiId, String message) {
    final config =
        _aiPlayerConfigs.where((c) => c.playerId == aiId).firstOrNull;
    if (config == null) return;
    final item = (config: config, message: message);
    setState(() {
      _activeChatItem = item;
      _lastChatItem = item;
    });
    Future.delayed(_chatBubbleDuration, () {
      if (mounted) {
        setState(() => _activeChatItem = null);
        // Keep _lastChatItem alive for the fade-out, then clear it.
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _lastChatItem = null);
        });
      }
    });
  }
}

// ── AI chat notification banner ───────────────────────────────────────────────

class _AiChatBanner extends StatelessWidget {
  const _AiChatBanner({required this.config, required this.message});

  final AiPlayerConfig config;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: config.nameColor.withValues(alpha: 0.85),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: config.nameColor.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini avatar circle
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.avatarColor,
              boxShadow: [
                BoxShadow(
                  color: config.avatarColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              config.initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.name,
                  style: TextStyle(
                    color: config.nameColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '"$message"',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
