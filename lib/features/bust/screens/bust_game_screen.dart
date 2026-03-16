import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/services/audio_service.dart' as game_audio;
import 'package:last_cards/services/game_sound.dart';
import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/core/theme/app_typography.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/hud_overlay_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/last_move_panel_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_hand_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_zone_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/quick_chat_panel.dart' show kQuickMessages, QuickChatPanel;
import 'package:last_cards/features/gameplay/presentation/widgets/turn_indicator_overlay.dart';
import 'package:last_cards/features/single_player/providers/single_player_session_provider.dart';

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

  /// Whether this is an online Bust session (real players via server)
  /// or an offline session (vs AI).
  ///
  /// **Currently unused** — online Bust is gated behind "Coming Soon" in
  /// [TournamentSubModeSheet] and this flag is only scaffolding for future
  /// online support. When online Bust is implemented, [_initGame] should
  /// branch on this flag to use real player slots instead of AI configs.
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
    required this.aiConfigs,
    required this.eliminationHistory,
    required this.localRoundStats,
  });

  final int roundNumber;
  final List<String> survivorIds;
  final Map<String, String> playerNames;
  final List<String> allEliminatedIds;
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
  final math.Random _aiDelayRng = math.Random();
  final ValueNotifier<bool> _reshuffleNotifier = ValueNotifier(false);
  final List<MoveLogEntry> _moveLogEntries = [];

  bool _showQuickChatPanel = false;
  int _quickChatCooldownRemaining = 0;
  Timer? _quickChatCooldownTimer;
  List<({String id, String playerId, String playerName, String message, bool isLocal})> _quickChatBubbles = [];

  bool _isDealing = false;
  final Map<String, int> _visibleCardCounts = {};
  final GlobalKey _drawPileKey = GlobalKey();
  final Map<String, GlobalKey> _playerZoneKeys = {};
  final GlobalKey<DealingAnimationOverlayState> _dealingOverlayKey =
      GlobalKey<DealingAnimationOverlayState>();

  int get _clampedPlayers => widget.totalPlayers.clamp(2, 10);

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _reshuffleNotifier.dispose();
    _quickChatCooldownTimer?.cancel();
    super.dispose();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  void _initGame() {
    final seed = DateTime.now().millisecondsSinceEpoch;
    final resume = widget.resumeState;

    if (resume != null) {
      // ── Subsequent round: reuse existing AI configs + names
      _aiConfigs = resume.aiConfigs;
      _playerNames = resume.playerNames;
      _eliminationHistory = resume.eliminationHistory;
      _localRoundStats = resume.localRoundStats;
      final survivorCount = resume.survivorIds.length;

      final (:gameState, :drawPile) = BustEngine.buildRound(
        playerCount: survivorCount,
        aiNames: {
          for (final id in resume.survivorIds.where((id) => id != OfflineGameState.localId))
            id: resume.playerNames[id] ?? id,
        },
        seed: seed,
      );

      _drawPile = drawPile;
      _discardPile
        ..clear()
        ..add(gameState.discardTopCard!);
      _gameState = _applyInitialEffects(gameState);
      _moveLogEntries.clear();

      // Do NOT carry over eliminatedIds or penaltyPoints from previous rounds.
      // BustEngine always numbers AIs from player-2 upward, so IDs are reused
      // each round. Passing old eliminated/penalty data would cause the new
      // holders of those IDs to be incorrectly skipped or given wrong scores.
      _roundManager = BustRoundManager.resumed(
        survivorIds: _gameState.players.map((p) => p.id).toList(),
        firstPlayerId: _gameState.currentPlayerId,
        penaltyPoints: const {},
        eliminatedIds: const [],
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
    s = applyInitialFaceUpEffect(state: s);
    if (s.activeSkipCount > 0) {
      final nextId = nextPlayerId(state: s);
      s = s.copyWith(currentPlayerId: nextId, activeSkipCount: 0);
    }
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
    return nextId;
  }

  // ── Draw pile ──────────────────────────────────────────────────────────────

  List<CardModel> _makeCards(int n) {
    final count = math.min(n, _drawPile.length);
    final drawn = _drawPile.sublist(0, count);
    _drawPile.removeRange(0, count);
    _gameState = _gameState.copyWith(drawPileCount: _drawPile.length);
    _checkPlacementPileRule();
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

    if (_roundManager.state.isRoundComplete) {
      _finalizeRound();
    }
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

    // Joker — no jokers in 52-card Bust deck, guard anyway
    if (played.length == 1 && played.first.isJoker) return;

    final beforeState = _gameState;
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
  }

  void _applyInvalidPlayPenalty(String playerId) {
    final handSizeBefore =
        _gameState.playerById(playerId)?.hand.length ?? 0;
    var newState = applyInvalidPlayPenalty(
      state: _gameState,
      playerId: playerId,
      cardFactory: _makeCards,
    );
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

    if (nextId != OfflineGameState.localId &&
        !_roundManager.state.isRoundComplete) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── Draw card ──────────────────────────────────────────────────────────────

  void _drawCard() {
    if (_aiThinking) return;
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

    var newState = applyDraw(
      state: _gameState,
      playerId: OfflineGameState.localId,
      count: drawCount,
      cardFactory: _makeCards,
    );

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

    if (nextId != OfflineGameState.localId &&
        !_roundManager.state.isRoundComplete) {
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

    if (nextId != OfflineGameState.localId &&
        !_roundManager.state.isRoundComplete) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── End turn ───────────────────────────────────────────────────────────────

  Future<void> _endTurn() async {
    if (_aiThinking) return;
    if (_gameState.currentPlayerId != OfflineGameState.localId) return;

    final err = validateEndTurn(_gameState);
    if (err != null) {
      _showError(err);
      return;
    }

    setState(() => _selectedCardId = null);

    // Ace suit declaration
    Suit? chosenAceSuit;
    if (_gameState.discardTopCard?.effectiveRank == Rank.ace &&
        _gameState.cardsPlayedThisTurn == 1 &&
        mounted) {
      chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _BustAceSuitPickerSheet(),
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

    final completedId = OfflineGameState.localId;
    final stateBeforeAdvance = _gameState;
    final nextId = _nextActivePlayerId(_gameState);
    setState(() {
      _gameState = advanceTurn(_gameState, nextId: nextId);
    });

    _recordSkippedTurns(stateBeforeAdvance, nextId);
    _onTurnComplete(completedId);

    if (nextId != OfflineGameState.localId &&
        !_roundManager.state.isRoundComplete) {
      _scheduleAiTurn(nextId);
    }
  }

  // ── AI turn ────────────────────────────────────────────────────────────────

  Future<void> _scheduleAiTurn(String aiId) async {
    if (_roundManager.state.isRoundComplete) return;
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
    final delayMs = hasPlayable
        ? (1000 + _aiDelayRng.nextInt(900))
        : 800;

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
    );

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

    // Record any players that were skipped by an Eight effect this turn.
    _recordSkippedTurns(result.preTurnAdvanceState, nextId);
    _onTurnComplete(aiId);

    // AI quick chat: 30% chance after playing cards (same as TableScreen).
    if (result.playedCards.isNotEmpty &&
        _aiDelayRng.nextDouble() < 0.30 &&
        mounted) {
      final msgIndex = _aiDelayRng.nextInt(kQuickMessages.length);
      _showQuickChatBubble(aiId, aiName, msgIndex, isLocal: false);
    }

    if (nextId != OfflineGameState.localId &&
        !_roundManager.state.isRoundComplete) {
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
    if (messageIndex < 0 || messageIndex >= kQuickMessages.length) return;
    final message = kQuickMessages[messageIndex];
    final bubbleId =
        '${playerId}_${messageIndex}_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _quickChatBubbles = [
        ..._quickChatBubbles,
        (
          id: bubbleId,
          playerId: playerId,
          playerName: playerName,
          message: message,
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

  void _sendQuickChat(int messageIndex) {
    if (_quickChatCooldownRemaining > 0) return;

    _showQuickChatBubble(
      OfflineGameState.localId,
      'You',
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
    final canEndTurn = isMyTurn && validateEndTurn(_gameState) == null;
    final rs = _roundManager.state;

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
                      quickChatBubblesByPlayer: {
                        for (final b in _quickChatBubbles)
                          b.playerId: (id: b.id, playerName: b.playerName, message: b.message, isLocal: b.isLocal),
                      },
                      onRemoveQuickChatBubble: _removeQuickChatBubble,
                    ),

                    // 2. Round indicator
                    _RoundIndicator(roundState: rs),

                    // 3. Centre board
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 24),
                            Row(
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
                          ],
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
                              chatBubble: () {
                                final b = _quickChatBubbles
                                    .where((b) => b.playerId == OfflineGameState.localId)
                                    .lastOrNull;
                                return b != null
                                    ? (id: b.id, playerName: b.playerName, message: b.message, isLocal: b.isLocal)
                                    : null;
                              }(),
                              onRemoveQuickChatBubble: _removeQuickChatBubble,
                              child: PlayerHandWidget(
                                cards: _orderedHand,
                                selectedCardId: _selectedCardId,
                                onCardTap: isMyTurn ? _onCardTap : null,
                                onReorder: _onHandReorder,
                                enabled: isMyTurn && !_isDealing,
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

              // Move log
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
                          horizontal: 10, vertical: 6),
                      child: LastMovePanelWidget(entries: _moveLogEntries),
                    ),
                  ),
                ),

              // Direction indicator
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child:
                        TurnIndicatorOverlay(direction: _gameState.direction),
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

              // Back button
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
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                      ),
                    ),
                  ),
                ),
              ),

              // Quick chat toggle and panel (bottom right, opposite back)
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
                                  maxHeight: 200,
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
                                      ? 'Quick chat (${_quickChatCooldownRemaining}s)'
                                      : 'Quick chat',
                                  icon: const Icon(
                                    Icons.chat_bubble_outline,
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

// ── Ace suit picker ────────────────────────────────────────────────────────────

class _BustAceSuitPickerSheet extends ConsumerWidget {
  const _BustAceSuitPickerSheet();

  static const _suits = [Suit.spades, Suit.clubs, Suit.hearts, Suit.diamonds];
  static const _symbols = ['♠', '♣', '♥', '♦'];
  static const _names = ['Spades', 'Clubs', 'Hearts', 'Diamonds'];
  static const _isRed = [false, false, true, true];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppDimensions.md,
        AppDimensions.md,
        AppDimensions.md,
        AppDimensions.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusModal),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choose a suit', style: AppTypography.heading2),
          const SizedBox(height: AppDimensions.md),
          Row(
            children: List.generate(4, (i) {
              final suitColor =
                  _isRed[i] ? const Color(0xFFE53935) : Colors.white;
              return Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  child: _SuitPickButton(
                    symbol: _symbols[i],
                    label: _names[i],
                    suit: _suits[i],
                    suitColor: suitColor,
                    theme: theme,
                    onTap: () => Navigator.of(context).pop(_suits[i]),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SuitPickButton extends StatefulWidget {
  const _SuitPickButton({
    required this.symbol,
    required this.label,
    required this.suit,
    required this.suitColor,
    required this.theme,
    required this.onTap,
  });

  final String symbol;
  final String label;
  final Suit suit;
  final Color suitColor;
  final dynamic theme;
  final VoidCallback onTap;

  @override
  State<_SuitPickButton> createState() => _SuitPickButtonState();
}

class _SuitPickButtonState extends State<_SuitPickButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.suitColor.withValues(alpha: 0.20)
              : widget.theme.backgroundMid,
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          border: Border.all(
            color: _pressed
                ? widget.suitColor
                : widget.suitColor.withValues(alpha: 0.40),
            width: _pressed ? 2 : 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.symbol,
              style: TextStyle(
                color: widget.suitColor,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.suitColor.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

