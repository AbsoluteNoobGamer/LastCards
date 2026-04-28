import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/services/audio_service.dart' as game_audio;
import 'package:last_cards/services/game_sound.dart';
import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/models/move_log_merge.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/providers/user_profile_provider.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:flutter/services.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_flight_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/game_move_log_overlay.dart'
    show GameMoveLogPanel;
import 'package:last_cards/features/gameplay/presentation/widgets/hud_overlay_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/ace_suit_picker_sheet.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_hand_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_zone_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/quick_chat_panel.dart'
    show QuickChatPanel;
import 'package:last_cards/features/gameplay/presentation/widgets/turn_indicator_overlay.dart';
import 'package:last_cards/core/services/player_level_service.dart';
import 'package:last_cards/shared/reactions/reaction_catalog.dart';
import 'package:last_cards/features/settings/presentation/widgets/settings_modal.dart';
import 'package:last_cards/shared/rules/move_log_support.dart';

import '../bust_engine.dart';
import '../bust_round_manager.dart';
import '../models/bust_player_view_model.dart';
import '../models/bust_round_state.dart';
import '../widgets/bust_player_rail.dart';
import 'bust_elimination_screen.dart';

/// Bust mode game screen — handles one full round of play.
///
/// A "round" is 2 full rotations (every active player takes exactly 2 turns).
/// When the round ends, navigates to [BustEliminationScreen] with the results.
/// [BustEliminationScreen] either starts the next round (pushes a new
/// [BustGameScreen]) or navigates to [BustWinnerScreen].
class BustGameScreen extends ConsumerStatefulWidget {
  const BustGameScreen({
    super.key,
    required this.totalPlayers,
    this.aiDifficulty = AiDifficulty.medium,
    this.isOnline = false,
    this.resumeState,
  });

  /// Total player count for this game session (5–10).
  final int totalPlayers;

  /// AI difficulty — passed to [AiPlayerConfig].
  /// Ignored when [isOnline] is true.
  final AiDifficulty aiDifficulty;

  /// Online Bust uses [TableScreen] (server); this screen is offline-only (vs AI).
  /// Kept for API compatibility — always `false` in current navigation.
  final bool isOnline;

  /// If non-null, resumes a game already in progress (subsequent rounds).
  final BustResumeState? resumeState;

  @override
  ConsumerState<BustGameScreen> createState() => _BustGameScreenState();
}

/// Passed from [BustEliminationScreen] to a new [BustGameScreen] when
/// continuing to the next round.
class BustResumeState {
  const BustResumeState({
    required this.roundNumber,
    required this.survivorIds,
    required this.playerNames,
    required this.allEliminatedIds,
    required this.cumulativePenaltyPoints,
    required this.aiConfigs,
    required this.eliminationHistory,
    required this.localRoundStats,
  });

  final int roundNumber;
  final List<String> survivorIds;
  final Map<String, String> playerNames;
  final List<String> allEliminatedIds;

  /// Cumulative Bust penalty totals after the last completed round (same keys
  /// as server `_bustPenaltyPoints` across rounds).
  final Map<String, int> cumulativePenaltyPoints;

  final List<AiPlayerConfig> aiConfigs;

  /// Accumulated placement records for every player knocked out so far.
  /// Passed forward each round and handed to [BustWinnerScreen] at game end.
  final List<BustEliminationRecord> eliminationHistory;

  /// Per-round performance stats for the local human player.
  /// Passed forward each round and shown on [BustWinnerScreen].
  final List<BustLocalRoundStat> localRoundStats;
}

// ── State ──────────────────────────────────────────────────────────────────────

class _BustGameScreenState extends ConsumerState<BustGameScreen> {
  late GameState _gameState;
  late List<CardModel> _drawPile;
  final List<CardModel> _discardPile = [];

  late BustRoundManager _roundManager;
  late List<AiPlayerConfig> _aiConfigs;
  late Map<String, String> _playerNames;
  late List<BustEliminationRecord> _eliminationHistory;
  late List<BustLocalRoundStat> _localRoundStats;
  int _localCardsDealtThisRound = 0;

  String? _selectedCardId;
  List<String> _handOrder = [];
  bool _aiThinking = false;
  bool _localActionInProgress = false;
  final math.Random _aiDelayRng = math.Random();
  final ValueNotifier<bool> _reshuffleNotifier = ValueNotifier(false);
  final ValueNotifier<int> _handShakeNotifier = ValueNotifier(0);
  final List<MoveLogEntry> _moveLogEntries = [];

  bool _showQuickChatPanel = false;
  int _quickChatCooldownRemaining = 0;
  Timer? _quickChatCooldownTimer;
  List<
          ({
            String id,
            String playerId,
            String playerName,
            int reactionWireIndex,
            bool isLocal
          })>
      _quickChatBubbles = [];

  bool _isDealing = false;
  bool _bustRoundNavigationQueued = false;
  final Map<String, int> _visibleCardCounts = {};
  final GlobalKey _drawPileKey = GlobalKey();
  final GlobalKey _discardPileKey = GlobalKey();
  final Map<String, GlobalKey> _playerZoneKeys = {};
  final GlobalKey<DealingAnimationOverlayState> _dealingOverlayKey =
      GlobalKey<DealingAnimationOverlayState>();
  final GlobalKey<CardFlightOverlayState> _playFlightKey =
      GlobalKey<CardFlightOverlayState>();
  String? _flyingCardId;
  final Set<String> _skipHighlightPlayerIds = <String>{};
  Timer? _skipHighlightClearTimer;

  int get _clampedPlayers => widget.totalPlayers.clamp(2, 10);

  /// Standard bust rounds end after two turns each; the 1v1 finale ends on
  /// empty hand only — never treat turn count as stopping play there.
  bool get _bustStopPlayFromTurnCap =>
      !_roundManager.state.isFinalShowdown &&
      _roundManager.state.isRoundComplete;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    clearSuitInference(_gameState.sessionId);
    _reshuffleNotifier.dispose();
    _handShakeNotifier.dispose();
    _quickChatCooldownTimer?.cancel();
    _skipHighlightClearTimer?.cancel();
    // Match [TableScreen.dispose]: stop shared SFX players so a mid-game exit
    // cannot leave deal/AI audio overlapping the next session (lag, missing SFX).
    unawaited(game_audio.AudioService.instance.stopAll());
    super.dispose();
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProviderScope(
        child: SettingsModal(),
      ),
    );
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  void _initGame() {
    final seed = DateTime.now().millisecondsSinceEpoch;
    final resume = widget.resumeState;
    final localDisplayName = ref.read(displayNameForGameProvider);

    if (resume != null) {
      // ── Subsequent round: reuse existing AI configs + names
      _aiConfigs = resume.aiConfigs;
      _playerNames = resume.playerNames;
      _eliminationHistory = resume.eliminationHistory;
      _localRoundStats = resume.localRoundStats;
      final survivorCount = resume.survivorIds.length;
      final seatPlayerIds = <String>[
        OfflineGameState.localId,
        for (final id in resume.survivorIds)
          if (id != OfflineGameState.localId) id,
      ];
      assert(
        seatPlayerIds.length == survivorCount,
        'resume.survivorIds must list each survivor once (including local)',
      );

      final (:gameState, :drawPile) = BustEngine.buildRound(
        playerCount: survivorCount,
        seatPlayerIds: seatPlayerIds,
        aiNames: {
          for (final id in resume.survivorIds.where((id) => id != OfflineGameState.localId))
            id: resume.playerNames[id] ?? id,
        },
        seed: seed,
        localDisplayName: localDisplayName,
      );

      _drawPile = drawPile;
      _discardPile
        ..clear()
        ..add(gameState.discardTopCard!);
      _gameState = _applyInitialEffects(gameState);
      _moveLogEntries.clear();

      // Seat IDs match prior rounds via [seatPlayerIds]; penalties / eliminated
      // lists use the same keys.
      _roundManager = BustRoundManager.resumed(
        survivorIds: _gameState.players.map((p) => p.id).toList(),
        firstPlayerId: _gameState.currentPlayerId,
        penaltyPoints: {
          for (final id in resume.survivorIds)
            id: resume.cumulativePenaltyPoints[id] ?? 0,
        },
        eliminatedIds: resume.allEliminatedIds,
        roundNumber: resume.roundNumber,
      );
    } else {
      // ── First round: generate fresh AI configs
      _aiConfigs = AiPlayerConfig.generateForGame(
        count: _clampedPlayers - 1,
        seed: seed,
      );

      final aiNameMap = {for (final c in _aiConfigs) c.playerId: c.name};

      final (:gameState, :drawPile) = BustEngine.buildRound(
        playerCount: _clampedPlayers,
        aiNames: aiNameMap,
        seed: seed,
        localDisplayName: localDisplayName,
      );

      _drawPile = drawPile;
      _discardPile
        ..clear()
        ..add(gameState.discardTopCard!);
      _gameState = _applyInitialEffects(gameState);
      _moveLogEntries.clear();

      _playerNames = {
        for (final p in _gameState.players) p.id: p.displayName,
      };

      _roundManager = BustRoundManager(
        initialActivePlayerIds: _gameState.players.map((p) => p.id).toList(),
        firstPlayerId: _gameState.currentPlayerId,
      );
      _eliminationHistory = const [];
      _localRoundStats = const [];
    }

    // Seed hand order and record how many cards the local player started with.
    final local = _localPlayer;
    _handOrder = local?.hand.map((c) => c.id).toList() ?? [];
    _localCardsDealtThisRound = local?.hand.length ?? 0;

    // Assign player zone keys for the dealing animation overlay.
    _playerZoneKeys.clear();
    for (final p in _gameState.players) {
      _playerZoneKeys[p.id] = GlobalKey();
    }

    setState(() {
      _isDealing = true;
      _visibleCardCounts.clear();
      for (final p in _gameState.players) {
        _visibleCardCounts[p.id] = 0;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startDealAnimation();
    });
  }

  /// Runs the visual deal animation: cards fly from draw pile to each player.
  Future<void> _startDealAnimation() async {
    final handSize =
        BustEngine.handSizeFor(_gameState.players.length);

    // Order: opponents first (clockwise from left of local), local last.
    final players = _gameState.players;
    final localIdx =
        players.indexWhere((p) => p.tablePosition == TablePosition.bottom);
    final orderedPlayers = <PlayerModel>[];
    const dir = 1; // clockwise
    for (int i = 1; i <= players.length; i++) {
      final idx = (localIdx + i * dir) % players.length;
      orderedPlayers.add(players[idx]);
    }

    for (int i = 0; i < handSize; i++) {
      for (var pi = 0; pi < orderedPlayers.length; pi++) {
        final p = orderedPlayers[pi];
        if (!mounted) return;

        game_audio.AudioService.instance.playDealCardSoundForPlayer(pi);
        final overlay = _dealingOverlayKey.currentState;
        if (overlay != null) {
          unawaited(overlay.animateCardDeal(p.id));
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        if (mounted) {
          setState(() {
            _visibleCardCounts[p.id] = (_visibleCardCounts[p.id] ?? 0) + 1;
            _gameState = _gameState.copyWith(
              drawPileCount: math.max(0, _gameState.drawPileCount - 1),
            );
          });
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _isDealing = false;
      _gameState = _gameState.copyWith(drawPileCount: _drawPile.length);
    });

    if (_gameState.currentPlayerId != OfflineGameState.localId) {
      _scheduleAiTurn(_gameState.currentPlayerId);
    }
  }

  GameState _applyInitialEffects(GameState state) {
    var s = state.copyWith(
      drawPileCount: _drawPile.length,
      preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
    );
    if (s.activeSkipCount > 0) {
      final nextId = nextPlayerId(state: s);
      s = s.copyWith(currentPlayerId: nextId, activeSkipCount: 0);
    }
    s = s.copyWith(preTurnCentreSuit: s.discardTopCard?.effectiveSuit);
    return s;
  }

  // ── View-model helpers ─────────────────────────────────────────────────────

  PlayerModel? get _localPlayer => _gameState.players
      .where((p) => p.tablePosition == TablePosition.bottom)
      .firstOrNull;

  List<BustPlayerViewModel> get _bustPlayers =>
      _gameState.players.asMap().entries.map((e) {
        final p = e.value;
        final cardCount = _isDealing
            ? (_visibleCardCounts[p.id] ?? 0)
            : p.cardCount;
        return BustPlayerViewModel(
          id: p.id,
          displayName: p.displayName,
          cardCount: cardCount,
          isActive: p.id == _gameState.currentPlayerId,
          isEliminated: _roundManager.state.eliminatedIds.contains(p.id),
          isLocal: p.tablePosition == TablePosition.bottom,
          colorIndex: e.key,
        );
      }).toList();

  List<CardModel> get _orderedHand {
    final local = _localPlayer;
    if (local == null) return [];
    final handMap = {for (final c in local.hand) c.id: c};
    var cards = _handOrder
        .where(handMap.containsKey)
        .map((id) => handMap[id]!)
        .where((c) => c.id != _flyingCardId)
        .toList();
    if (_isDealing) {
      final visible = _visibleCardCounts[local.id] ?? 0;
      cards = cards.take(visible).toList();
    }
    return cards;
  }

  void _syncHandOrder(List<CardModel> newHand) {
    final newIds = newHand.map((c) => c.id).toSet();
    _handOrder = [
      ..._handOrder.where(newIds.contains),
      ...newIds.where((id) => !_handOrder.contains(id)),
    ];
  }

  String _nextActivePlayerId(GameState state) {
    var nextId = nextPlayerId(state: state);
    var guard = state.players.length;
    while (_roundManager.state.eliminatedIds.contains(nextId) && guard > 0) {
      nextId = nextPlayerId(
          state: state.copyWith(currentPlayerId: nextId));
      guard--;
    }
    if (_roundManager.state.eliminatedIds.contains(nextId)) {
      for (final p in state.players) {
        if (!_roundManager.state.eliminatedIds.contains(p.id)) {
          if (kDebugMode) {
            debugPrint(
              'Bust _nextActivePlayerId: fallback — nextId was eliminated ($nextId), '
              'using ${p.id}',
            );
          }
          nextId = p.id;
          break;
        }
      }
    }
    return nextId;
  }

  // ── Draw pile ──────────────────────────────────────────────────────────────

  List<CardModel> _makeCards(int n) {
    final count = math.min(n, _drawPile.length);
    final drawn = _drawPile.sublist(0, count);
    _drawPile.removeRange(0, count);
    _gameState = _gameState.copyWith(drawPileCount: _drawPile.length);
    return drawn;
  }

  void _checkPlacementPileRule() {
    if (!BustEngine.needsPlacementPileReshuffle(_discardPile)) return;

    final topCard = _discardPile.last;
    final result = BustEngine.applyPlacementPileRule(
      discardPile: _discardPile,
      drawPile: _drawPile,
    );

    _discardPile
      ..clear()
      ..add(topCard);
    _drawPile = result.newDrawPile;

    if (!mounted) return;
    setState(() {
      _gameState = _gameState.copyWith(
        drawPileCount: _drawPile.length,
        discardPileHistory: [], // Under-pile was reshuffled into draw
      );
      _reshuffleNotifier.value = !_reshuffleNotifier.value;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.shuffle_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Deck reshuffled',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: AppColors.goldDark,
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Round end detection ────────────────────────────────────────────────────

  /// Called after every turn completes. Records the turn and checks for
  /// round completion.
  void _onTurnComplete(String playerId) {
    _roundManager.recordTurn(playerId);

    if (_maybeFinalizeBustFinalShowdown()) return;
    if (_roundManager.state.isRoundComplete) {
      _finalizeRound();
    }
  }

  /// Returns true if the 1v1 race ended and navigation was triggered.
  bool _maybeFinalizeBustFinalShowdown() {
    if (!_roundManager.state.isFinalShowdown) return false;
    if (_roundManager.checkFinalShowdownWinner(_gameState) == null) {
      return false;
    }
    _finalizeRound();
    return true;
  }

  /// When an Eight card is played, [nextPlayerId] skips one or more players.
  /// Those skipped players never get [_onTurnComplete] called, so their turn
  /// count stalls and [isRoundComplete] is never reached.
  ///
  /// This helper walks the player list from [stateBefore.currentPlayerId]
  /// toward [resolvedNextId] and records a skipped turn for every player that
  /// was jumped over.
  void _recordSkippedTurns(GameState stateBefore, String resolvedNextId) {
    if (stateBefore.activeSkipCount <= 0) return;

    final players = stateBefore.players;
    final currentIdx =
        players.indexWhere((p) => p.id == stateBefore.currentPlayerId);
    if (currentIdx < 0) return;

    final step =
        stateBefore.direction == PlayDirection.clockwise ? 1 : -1;
    var idx = currentIdx;

    for (var safety = players.length; safety > 0; safety--) {
      idx = (idx + step) % players.length;
      if (idx < 0) idx += players.length;
      final pid = players[idx].id;
      if (pid == resolvedNextId) break;
      _roundManager.recordTurn(pid);
    }
  }

  void _finalizeRound() {
    if (_bustRoundNavigationQueued) return;
    _bustRoundNavigationQueued = true;

    final result = _roundManager.finalizeRound(_gameState, _playerNames);

    // Build the local player's stat for this round.
    final localPlayer = _localPlayer;
    final localCardsRemaining = localPlayer?.hand.length ?? 0;
    final localSurvived =
        !result.eliminatedThisRound.contains(OfflineGameState.localId);
    final localStat = BustLocalRoundStat(
      roundNumber: result.roundNumber,
      survived: localSurvived,
      cardsRemaining: localCardsRemaining,
      cardsDealt: _localCardsDealtThisRound,
    );
    final updatedLocalStats = [..._localRoundStats, localStat];

    Future.microtask(() {
      if (!mounted) return;
      Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, __, ___) => BustEliminationScreen(
          result: result,
          playerNames: _playerNames,
          aiConfigs: _aiConfigs,
          eliminationHistory: _eliminationHistory,
          localRoundStats: updatedLocalStats,
          priorEliminatedIds: _roundManager.state.eliminatedIds,
          isOnline: widget.isOnline,
        ),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ));
    });
  }

  // ── Card play ──────────────────────────────────────────────────────────────

  void _onCardTap(String cardId) {
    if (_aiThinking) return;
    if (_gameState.currentPlayerId != OfflineGameState.localId) return;
    _playCard(cardId: cardId);
  }

  Future<void> _playCard({required String cardId}) async {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    final local = _localPlayer;
    if (local == null) return;

    final played = local.hand.where((c) => c.id == cardId).toList();
    if (played.isEmpty) return;

    final discardTop = _gameState.discardTopCard;
    if (discardTop == null) return;

    final err = validatePlay(
      cards: played,
      discardTop: discardTop,
      state: _gameState,
    );
    if (err != null) {
      _applyInvalidPlayPenalty(OfflineGameState.localId);
      return;
    }

    _localActionInProgress = true;
    try {
      final lastFromHand = local.hand.length == played.length;
      setState(() => _flyingCardId = played.first.id);
      await _animateLocalCardToDiscard(played.first, lastCardFromHand: lastFromHand);
      if (!mounted) return;

      final beforeState = _gameState;
      clearSuitInferenceOnPlay(
        sessionId: beforeState.sessionId,
        playerId: OfflineGameState.localId,
        cards: played,
      );
      var newState = applyPlay(
        state: _gameState,
        playerId: OfflineGameState.localId,
        cards: played,
      );
      _discardPile.addAll(played);

      final localInNew = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;

      setState(() {
        _gameState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        _flyingCardId = null;
        if (localInNew != null) _syncHandOrder(localInNew.hand);
        _recordPlayMove(
          playerId: OfflineGameState.localId,
          playerName: local.displayName,
          playedCards: played,
          beforeState: beforeState,
          afterState: newState,
        );
      });

      _checkPlacementPileRule();
        _maybeFinalizeBustFinalShowdown();

      if (newState.activeSkipCount > beforeState.activeSkipCount) {
        game_audio.AudioService.instance.playSound(GameSound.skipApplied);
        _flashSkipHighlight(skippedPlayerIdsForSkipState(newState));
      }
    } finally {
      _localActionInProgress = false;
      if (mounted && _flyingCardId != null) setState(() => _flyingCardId = null);
    }
  }

  Future<void> _animateLocalCardToDiscard(
    CardModel card, {
    bool lastCardFromHand = false,
  }) async {
    final flight = _playFlightKey.currentState;
    final origin = _playerZoneKeys[OfflineGameState.localId];
    if (lastCardFromHand) {
      HapticFeedback.heavyImpact();
    }
    if (flight != null &&
        origin?.currentContext != null &&
        _discardPileKey.currentContext != null) {
      await flight.flyCard(
        originKey: origin,
        targetKey: _discardPileKey,
        card: card,
        faceUp: true,
        lastCardFromHand: lastCardFromHand,
      );
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _applyInvalidPlayPenalty(String playerId) {
    if (playerId == OfflineGameState.localId) {
      _handShakeNotifier.value++;
    }
    final handSizeBefore =
        _gameState.playerById(playerId)?.hand.length ?? 0;
    var newState = applyInvalidPlayPenalty(
      state: _gameState,
      playerId: playerId,
      cardFactory: _makeCards,
    );
    _checkPlacementPileRule();
    final drawCount =
        (newState.playerById(playerId)?.hand.length ?? 0) - handSizeBefore;

    final stateBeforeAdvance = newState;
    final nextId = _nextActivePlayerId(newState);
    newState = advanceTurn(newState, nextId: nextId);

    final localAfter = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    setState(() {
      _gameState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localAfter != null) _syncHandOrder(localAfter.hand);
    });

    _showError('Invalid play — drew $drawCount cards as penalty.');
    _recordSkippedTurns(stateBeforeAdvance, nextId);
    _onTurnComplete(playerId);

    if (nextId != OfflineGameState.localId && !_bustStopPlayFromTurnCap) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── Draw card ──────────────────────────────────────────────────────────────

  void _drawCard() {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    if (_gameState.currentPlayerId != OfflineGameState.localId) return;
    if (_gameState.actionsThisTurn > 0 && _gameState.queenSuitLock == null) {
      return;
    }

    // No draw pile and no valid card → skip turn, no penalty
    if (_drawPile.isEmpty) {
      _skipTurnNoPenalty(OfflineGameState.localId);
      return;
    }

    final isPenaltyDraw = _gameState.activePenaltyCount > 0;
    final drawCount = isPenaltyDraw ? _gameState.activePenaltyCount : 1;
    final local = _localPlayer;

    recordDrawSuitInference(
      state: _gameState,
      drawingPlayerId: OfflineGameState.localId,
    );

    var newState = applyDraw(
      state: _gameState,
      playerId: OfflineGameState.localId,
      count: drawCount,
      cardFactory: _makeCards,
    );
    _checkPlacementPileRule();

    // Play draw sounds (same pattern as TableScreen offline).
    game_audio.AudioService.instance.playSound(GameSound.cardDraw);
    if (isPenaltyDraw) {
      game_audio.AudioService.instance.playSound(GameSound.penaltyDraw);
    }

    final localAfter = newState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    final stateBeforeAdvance = newState;
    final nextId = _nextActivePlayerId(newState);
    newState = advanceTurn(newState, nextId: nextId);

    setState(() {
      _gameState = newState.copyWith(drawPileCount: _drawPile.length);
      _selectedCardId = null;
      if (localAfter != null) _syncHandOrder(localAfter.hand);
      _pushMoveLog(MoveLogEntry.draw(
        playerId: OfflineGameState.localId,
        playerName: local?.displayName ?? 'You',
        drawCount: drawCount,
      ));
    });

    _recordSkippedTurns(stateBeforeAdvance, nextId);
    _onTurnComplete(OfflineGameState.localId);

    if (nextId != OfflineGameState.localId && !_bustStopPlayFromTurnCap) {
      _scheduleAiTurn(nextId);
    }
  }

  /// Handles the "no draw pile + no valid card = skip turn" rule.
  void _skipTurnNoPenalty(String playerId) {
    final stateBeforeSkip = _gameState;
    final nextId = _nextActivePlayerId(_gameState);
    setState(() {
      _gameState = advanceTurn(_gameState, nextId: nextId);
      _selectedCardId = null;
    });
    _recordSkippedTurns(stateBeforeSkip, nextId);
    _onTurnComplete(playerId);

    if (nextId != OfflineGameState.localId && !_bustStopPlayFromTurnCap) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── End turn ───────────────────────────────────────────────────────────────

  Future<void> _endTurn() async {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    if (_gameState.currentPlayerId != OfflineGameState.localId) return;

    setState(() => _selectedCardId = null);

    // Ace suit declaration
    Suit? chosenAceSuit;
    if (_gameState.discardTopCard?.effectiveRank == Rank.ace &&
        _gameState.cardsPlayedThisTurn == 1 &&
        _gameState.suitLock == null &&
        mounted) {
      chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const AceSuitPickerSheet(
          presentation: AceSuitPickerPresentation.bottomSheet,
          title: 'Choose a suit',
          subtitle: '',
        ),
      );
      if (!mounted) return;
      if (chosenAceSuit == null) return;
      setState(() {
        _gameState = _gameState.copyWith(suitLock: chosenAceSuit);
        _applyAceDeclarationToLog(
          playerId: OfflineGameState.localId,
          chosenSuit: chosenAceSuit!,
        );
      });
    }

    final err = validateEndTurn(_gameState);
    if (err != null) {
      _showError(err);
      return;
    }

    final completedId = OfflineGameState.localId;
    final stateBeforeAdvance = _gameState;
    final nextId = _nextActivePlayerId(_gameState);
    setState(() {
      _gameState = advanceTurn(_gameState, nextId: nextId);
    });

    _recordSkippedTurns(stateBeforeAdvance, nextId);
    _onTurnComplete(completedId);

    if (nextId != OfflineGameState.localId && !_bustStopPlayFromTurnCap) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── AI turn ────────────────────────────────────────────────────────────────

  Future<void> _scheduleAiTurn(String aiId) async {
    if (_bustStopPlayFromTurnCap) return;
    if (_roundManager.state.eliminatedIds.contains(aiId)) {
      final nextId = _nextActivePlayerId(
          _gameState.copyWith(currentPlayerId: aiId));
      if (nextId == OfflineGameState.localId || nextId == aiId) return;
      _scheduleAiTurn(nextId);
      return;
    }

    if (!mounted) return;
    setState(() => _aiThinking = true);

    final hasPlayable = aiHasPlayableTurn(
        state: _gameState, aiPlayerId: aiId);
    final diffMult = widget.aiDifficulty.delayMultiplier;
    final delayMs = hasPlayable
        ? ((1000 + _aiDelayRng.nextInt(900)) * diffMult).round()
        : (800 * diffMult).round();

    await Future.delayed(Duration(milliseconds: delayMs));
    if (!mounted) return;

    // No draw pile and no valid card → skip
    if (_drawPile.isEmpty &&
        !aiHasPlayableTurn(state: _gameState, aiPlayerId: aiId)) {
      _skipTurnNoPenalty(aiId);
      setState(() => _aiThinking = false);
      return;
    }

    final aiConfig = _aiConfigs
        .where((c) => c.playerId == aiId)
        .firstOrNull;
    final aiName = _gameState.playerById(aiId)?.displayName ?? aiId;
    final preTurn = _gameState;
    final result = aiTakeTurn(
      state: _gameState,
      aiPlayerId: aiId,
      cardFactory: _makeCards,
      personality: aiConfig?.personality,
      difficulty: widget.aiDifficulty,
    );
    _checkPlacementPileRule();

    if (result.playedCards.isNotEmpty) {
      _discardPile.addAll(result.playedCards);
    }

    var finalState = result.state;
    var nextId = finalState.currentPlayerId;

    if (_roundManager.state.eliminatedIds.contains(nextId)) {
      nextId = _nextActivePlayerId(finalState);
      finalState = finalState.copyWith(
        currentPlayerId: nextId,
        preTurnCentreSuit: finalState.discardTopCard?.effectiveSuit,
      );
    } else if (nextId != aiId) {
      finalState = finalState.copyWith(
        preTurnCentreSuit: finalState.discardTopCard?.effectiveSuit,
      );
    }

    final localInNew = finalState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    if (!mounted) return;
    setState(() {
      _gameState = finalState.copyWith(drawPileCount: _drawPile.length);
      _aiThinking = false;
      if (localInNew != null) _syncHandOrder(localInNew.hand);
      if (result.playedCards.isNotEmpty) {
        _recordPlayMove(
          playerId: aiId,
          playerName: aiName,
          playedCards: result.playedCards,
          beforeState: preTurn,
          afterState: result.state,
        );
      } else {
        final drawnCount =
            (result.state.playerById(aiId)?.cardCount ?? 0) -
            (preTurn.playerById(aiId)?.cardCount ?? 0);
        _pushMoveLog(MoveLogEntry.draw(
          playerId: aiId,
          playerName: aiName,
          drawCount: drawnCount > 0 ? drawnCount : 1,
        ));
      }
    });

    if (result.preTurnAdvanceState.activeSkipCount > preTurn.activeSkipCount) {
      game_audio.AudioService.instance.playSound(GameSound.skipApplied);
      _flashSkipHighlight(
        skippedPlayerIdsForSkipState(result.preTurnAdvanceState),
      );
    }

    // Record any players that were skipped by an Eight effect this turn.
    _recordSkippedTurns(result.preTurnAdvanceState, nextId);
    _onTurnComplete(aiId);

    // AI quick chat: 30% chance after playing cards (same as TableScreen).
    if (result.playedCards.isNotEmpty &&
        _aiDelayRng.nextDouble() < 0.30 &&
        mounted) {
      final pool = kAiQuickReactionIndices;
      final msgIndex = pool[_aiDelayRng.nextInt(pool.length)];
      _showQuickChatBubble(aiId, aiName, msgIndex, isLocal: false);
    }

    if (nextId != OfflineGameState.localId && !_bustStopPlayFromTurnCap) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── Move log helpers ───────────────────────────────────────────────────────

  void _pushMoveLog(MoveLogEntry entry) {
    _moveLogEntries.insert(0, entry);
    if (_moveLogEntries.length > 3) {
      _moveLogEntries.removeRange(3, _moveLogEntries.length);
    }
  }

  void _recordPlayMove({
    required String playerId,
    required String playerName,
    required List<CardModel> playedCards,
    required GameState beforeState,
    required GameState afterState,
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

    final skipped = _skippedPlayersForTurn(afterState);
    final entry = MoveLogEntry.play(
      playerId: playerId,
      playerName: playerName,
      cardActions: actions,
      skippedPlayerNames: skipped,
      turnContinues: afterState.currentPlayerId == playerId,
    );

    mergeOrPrependPlayLog(_moveLogEntries, entry);
  }

  void _applyAceDeclarationToLog({
    required String playerId,
    required Suit chosenSuit,
  }) {
    if (_moveLogEntries.isEmpty) return;
    final top = _moveLogEntries.first;
    if (top.type != MoveLogEntryType.play || top.playerId != playerId) return;
    final updated = [...top.cardActions];
    for (var i = updated.length - 1; i >= 0; i--) {
      if (updated[i].card.effectiveRank == Rank.ace) {
        updated[i] = updated[i].copyWith(aceDeclaredSuit: chosenSuit);
        _moveLogEntries[0] = top.copyWith(cardActions: updated);
        return;
      }
    }
  }

  List<String> _skippedPlayersForTurn(GameState state) {
    if (state.activeSkipCount <= 0) return const [];
    if (state.lastPlayedThisTurn?.effectiveRank != Rank.eight) return const [];
    final players = state.players;
    final idx = players.indexWhere((p) => p.id == state.currentPlayerId);
    if (idx < 0) return const [];
    final step = state.direction == PlayDirection.clockwise ? 1 : -1;
    var cursor = idx;
    final skipped = <String>[];
    for (var i = 0; i < state.activeSkipCount; i++) {
      cursor = (cursor + step) % players.length;
      if (cursor < 0) cursor += players.length;
      skipped.add(players[cursor].displayName);
    }
    return skipped;
  }

  void _onHandReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex--;
      final item = _handOrder.removeAt(oldIndex);
      _handOrder.insert(newIndex, item);
    });
  }

  // ── Quick chat ────────────────────────────────────────────────────────────

  void _showQuickChatBubble(String playerId, String playerName, int messageIndex,
      {bool isLocal = false}) {
    if (!isValidReactionWireIndex(messageIndex)) return;
    final bubbleId =
        '${playerId}_${messageIndex}_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      // Same as [TableScreen._showQuickChatBubble]: one visible bubble per player;
      // a new message replaces the previous bubble for that seat.
      _quickChatBubbles = [
        ..._quickChatBubbles.where((b) => b.playerId != playerId),
        (
          id: bubbleId,
          playerId: playerId,
          playerName: playerName,
          reactionWireIndex: messageIndex,
          isLocal: isLocal,
        ),
      ];
      if (_quickChatBubbles.length > 2) {
        _quickChatBubbles =
            _quickChatBubbles.sublist(_quickChatBubbles.length - 2);
      }
    });
  }

  void _removeQuickChatBubble(String bubbleId) {
    setState(() => _quickChatBubbles.removeWhere((b) => b.id == bubbleId));
  }

  void _flashSkipHighlight(Iterable<String> playerIds) {
    final set = playerIds.toSet();
    if (set.isEmpty) return;
    _skipHighlightClearTimer?.cancel();
    setState(() {
      _skipHighlightPlayerIds
        ..clear()
        ..addAll(set);
    });
    _skipHighlightClearTimer = Timer(const Duration(milliseconds: 720), () {
      _skipHighlightClearTimer = null;
      if (!mounted) return;
      setState(_skipHighlightPlayerIds.clear);
    });
  }

  void _sendQuickChat(int messageIndex) {
    if (_quickChatCooldownRemaining > 0) return;
    final level = PlayerLevelService.instance.currentLevel.value;
    if (!isReactionUnlockedForLevel(messageIndex, level)) return;

    final bottom = _localPlayer;
    final localChatName =
        (bottom != null && bottom.displayName.isNotEmpty)
            ? bottom.displayName
            : ref.read(displayNameForGameProvider);

    _showQuickChatBubble(
      OfflineGameState.localId,
      localChatName,
      messageIndex,
      isLocal: true,
    );

    setState(() {
      _showQuickChatPanel = false;
      _quickChatCooldownRemaining = 10;
    });

    _quickChatCooldownTimer?.cancel();
    _quickChatCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _quickChatCooldownRemaining =
            (_quickChatCooldownRemaining - 1).clamp(0, 10);
      });
      if (_quickChatCooldownRemaining <= 0) {
        _quickChatCooldownTimer?.cancel();
        _quickChatCooldownTimer = null;
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(milliseconds: 2400),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final opponents = _bustPlayers.where((p) => !p.isLocal).toList();
    final localPlayer = _localPlayer;
    final isMyTurn = !_aiThinking &&
        _gameState.currentPlayerId == OfflineGameState.localId;
    final canEndTurn = isMyTurn && canEndTurnButton(_gameState);
    final rs = _roundManager.state;
    final nextTurnLabel = _gameState.phase == GamePhase.playing
        ? nextPlayerAfterTurnLabel(
            state: _gameState,
            viewerPlayerId: OfflineGameState.localId,
          )
        : null;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Background
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [theme.backgroundMid, theme.backgroundDeep],
                    ),
                  ),
                ),
              ),

              // Main column
              SafeArea(
                child: Column(
                  children: [
                    // 1. Opponent rail
                    BustPlayerRail(
                      players: opponents,
                      slotKeyBuilder: (p) => _playerZoneKeys[p.id],
                      skipHighlightPlayerIds: _skipHighlightPlayerIds,
                      quickChatBubblesByPlayer: {
                        for (final b in _quickChatBubbles)
                          b.playerId: (
                              id: b.id,
                              playerName: b.playerName,
                              reactionWireIndex: b.reactionWireIndex,
                              isLocal: b.isLocal,
                            ),
                      },
                      onRemoveQuickChatBubble: _removeQuickChatBubble,
                    ),

                    // 2. Round indicator
                    _RoundIndicator(roundState: rs),

                    // Move log — fixed height reserved always so draw/discard do not jump
                    // when the first entry appears; sits under round badge.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        math.max(12.0, constraints.maxWidth * 0.06),
                        6,
                        math.max(12.0, constraints.maxWidth * 0.06),
                        8,
                      ),
                      child: SizedBox(
                        height: 140,
                        child: _moveLogEntries.isNotEmpty
                            ? GameMoveLogPanel(entries: _moveLogEntries)
                            : null,
                      ),
                    ),

                    // 3. Centre board — top-aligned so the piles stay put (no vertical
                    // re-centering when the move log or other chrome changes).
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                key: _drawPileKey,
                                width: 100,
                                height: 145,
                                child: OverflowBox(
                                  maxWidth: double.infinity,
                                  maxHeight: double.infinity,
                                  child: DrawPileWidget(
                                    cardCount: _gameState.drawPileCount,
                                    cardWidth: 100,
                                    enabled: !_isDealing &&
                                        isMyTurn &&
                                        (_gameState.actionsThisTurn == 0 ||
                                            _gameState.queenSuitLock != null),
                                    onTap: isMyTurn ? _drawCard : null,
                                    reshuffleNotifier: _reshuffleNotifier,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(
                                key: _discardPileKey,
                                width: 100,
                                height: 145,
                                child: OverflowBox(
                                  maxWidth: double.infinity,
                                  maxHeight: double.infinity,
                                  child: DiscardPileWidget(
                                    topCard: _gameState.discardTopCard,
                                    secondCard: _gameState.discardPileHistory.isNotEmpty ? _gameState.discardPileHistory.first : null,
                                    discardPileHistory: _gameState.discardPileHistory,
                                    cardWidth: 100,
                                    discardPileCount: _discardPile.length,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 4. End-turn bar
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.sm,
                        left: AppDimensions.xs,
                        right: AppDimensions.xs,
                      ),
                      child: FloatingActionBarWidget(
                        activePlayerName: _gameState
                                .playerById(_gameState.currentPlayerId)
                                ?.displayName ??
                            '',
                        direction: _gameState.direction,
                        canEndTurn: canEndTurn,
                        onEndTurn: isMyTurn && !_isDealing ? _endTurn : null,
                        pulseLocalTurn: isMyTurn,
                        nextTurnLabel: nextTurnLabel,
                        isLocalTurn: isMyTurn,
                        hasAlreadyDeclared: false,
                        lastCardsEnabled: false,
                        localHandSize: localPlayer?.hand.length ?? 0,
                      ),
                    ),

                    // 5. Local player zone + hand
                    if (localPlayer != null)
                      KeyedSubtree(
                        key: _playerZoneKeys[OfflineGameState.localId],
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppDimensions.sm),
                          child: SizedBox(
                            width: double.infinity,
                            child: PlayerZoneWidget(
                              player:
                                  localPlayer.copyWith(
                                    cardCount: _isDealing
                                        ? (_visibleCardCounts[OfflineGameState.localId] ?? 0)
                                        : localPlayer.cardCount,
                                  ),
                              isLocalPlayer: true,
                              isActiveTurn: isMyTurn,
                              skipSeatHighlight: _skipHighlightPlayerIds
                                  .contains(OfflineGameState.localId),
                              chatBubble: () {
                                final b = _quickChatBubbles
                                    .where((b) => b.playerId == OfflineGameState.localId)
                                    .lastOrNull;
                                return b != null
                                    ? (
                                        id: b.id,
                                        playerName: b.playerName,
                                        reactionWireIndex: b.reactionWireIndex,
                                        isLocal: b.isLocal,
                                      )
                                    : null;
                              }(),
                              onRemoveQuickChatBubble: _removeQuickChatBubble,
                              child: PlayerHandWidget(
                                cards: _orderedHand,
                                selectedCardId: _selectedCardId,
                                onCardTap: isMyTurn ? _onCardTap : null,
                                onReorder: _flyingCardId != null ? null : _onHandReorder,
                                enabled: isMyTurn && !_isDealing,
                                invalidPlayShakeTrigger: _handShakeNotifier,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // HUD overlay
              Positioned(
                top: constraints.maxHeight * 0.63,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: HudOverlayWidget(
                      activeSuit: _gameState.suitLock,
                      queenSuitLock: _gameState.queenSuitLock,
                      penaltyCount: _gameState.activePenaltyCount,
                    ),
                  ),
                ),
              ),

              // Direction indicator
              Positioned.fill(
                child: IgnorePointer(
                  child: TurnIndicatorOverlay(
                    direction: _gameState.direction,
                    bannerAlignment: const Alignment(0, 0.22),
                  ),
                ),
              ),

              // Dealing animation overlay (cards flying from draw pile)
              Positioned.fill(
                child: DealingAnimationOverlay(
                  key: _dealingOverlayKey,
                  drawPileKey: _drawPileKey,
                  playerKeys: _playerZoneKeys,
                ),
              ),

              // Card play flight overlay
              Positioned.fill(
                child: CardFlightOverlay(key: _playFlightKey),
              ),

              // Direction: left slot of [FloatingActionBarWidget] (no Last Cards in Bust).

              // Settings + back
              Positioned(
                bottom: 210,
                left: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.xs),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.30),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Settings',
                            icon: const Icon(
                              Icons.settings_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showSettingsSheet(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        DecoratedBox(
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
                            onPressed: () => Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Emoji reactions toggle and panel (bottom right, opposite back)
              if (!_isDealing && _gameState.phase != GamePhase.ended)
                Positioned(
                  bottom: 210,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.xs),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_showQuickChatPanel)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.55,
                                  maxHeight: 260,
                                ),
                                child: SingleChildScrollView(
                                  child: QuickChatPanel(
                                    onMessageSelected: _sendQuickChat,
                                  ),
                                ),
                              ),
                            ),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _quickChatCooldownRemaining > 0
                                      ? Colors.black.withValues(alpha: 0.50)
                                      : Colors.black.withValues(alpha: 0.30),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  tooltip: _quickChatCooldownRemaining > 0
                                      ? 'Reactions (${_quickChatCooldownRemaining}s)'
                                      : 'Reactions',
                                  icon: const Icon(
                                    Icons.emoji_emotions_outlined,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _quickChatCooldownRemaining > 0
                                      ? null
                                      : () {
                                          setState(() => _showQuickChatPanel = !_showQuickChatPanel);
                                        },
                                ),
                              ),
                              if (_quickChatCooldownRemaining > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.goldDark,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$_quickChatCooldownRemaining',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Round indicator widget ─────────────────────────────────────────────────────

class _RoundIndicator extends ConsumerWidget {
  const _RoundIndicator({required this.roundState});

  final BustRoundState roundState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final rotation = roundState.currentRotation;
    final round = roundState.roundNumber;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.backgroundMid,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.accentPrimary.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Round $round  ·  Rotation $rotation/2',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.accentPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
