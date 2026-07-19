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
import 'package:last_cards/core/providers/profile_provider.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:flutter/services.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_flight_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';
import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/felt_table_background.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/stack_block_banner_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/hud_overlay_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/ace_suit_picker_sheet.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/multi_card_play_celebration.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_hand_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_zone_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/quick_chat_panel.dart'
    show QuickChatPanel;
import 'package:last_cards/features/gameplay/presentation/widgets/turn_indicator_overlay.dart';
import 'package:last_cards/core/services/ads_service.dart';
import 'package:last_cards/core/services/avatar_catalog_service.dart';
import 'package:last_cards/core/services/purchase_service.dart';
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
    this.preloadedAiPlayerConfigs,
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

  /// Roster from the pre-game splash (first round only).
  final List<AiPlayerConfig>? preloadedAiPlayerConfigs;

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
  final GlobalKey _hudOverlayKey = GlobalKey();
  final Map<String, GlobalKey> _playerZoneKeys = {};
  final GlobalKey<DealingAnimationOverlayState> _dealingOverlayKey =
      GlobalKey<DealingAnimationOverlayState>();
  final GlobalKey<CardFlightOverlayState> _playFlightKey =
      GlobalKey<CardFlightOverlayState>();
  String? _flyingCardId;
  final Set<String> _skipHighlightPlayerIds = <String>{};
  Timer? _skipHighlightClearTimer;

  int _multiPlayCelebrationTrigger = 0;
  int _multiPlayCelebrationTier = 0;

  String? _stackBlockBannerText;
  Color? _stackBlockBannerColor;
  Timer? _stackBlockBannerClearTimer;

  int get _clampedPlayers => widget.totalPlayers.clamp(2, 10);

  /// Standard bust rounds end after two turns each; the 1v1 finale ends on
  /// empty hand only — never treat turn count as stopping play there.
  bool get _bustStopPlayFromTurnCap =>
      !_roundManager.state.isFinalShowdown &&
      _roundManager.state.isRoundComplete;

  /// When true, AI turns resolve instantly (no delay) — set after the local
  /// player watches a rewarded ad to skip the rest of a round they've
  /// already used both their turns in. See [_onBustSkipTapped].
  bool _bustSimulatingRest = false;

  /// True while the rewarded ad for [_onBustSkipTapped] is loading/showing.
  bool _bustSkipAdShowing = false;

  /// Whether to show the "skip rest of round" chip — see
  /// [BustRoundState.hasFinishedTurnsWaitingOnOthers].
  bool get _bustCanSkipRest {
    if (_bustRoundNavigationQueued) return false;
    return _roundManager.state
        .hasFinishedTurnsWaitingOnOthers(OfflineGameState.localId);
  }

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
    _stackBlockBannerClearTimer?.cancel();
    // Match [TableScreen.dispose]: stop shared SFX players so a mid-game exit
    // cannot leave deal/AI audio overlapping the next session (lag, missing SFX).
    unawaited(game_audio.AudioService.instance.stopAll());
    super.dispose();
  }

  /// Shows [text] in the stack-block banner for a beat, then clears it.
  /// Mirrors [TableScreen]'s helper of the same name — kept screen-local
  /// since it touches this screen's own State fields/Timer.
  void _showStackBlockBanner(String text, Color color) {
    _stackBlockBannerClearTimer?.cancel();
    setState(() {
      _stackBlockBannerText = text;
      _stackBlockBannerColor = color;
    });
    _stackBlockBannerClearTimer =
        Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _stackBlockBannerText = null;
          _stackBlockBannerColor = null;
        });
      }
    });
  }

  /// Shows the stack-block banner for [playedCard] if it warrants one (same
  /// shared rule set [TableScreen] uses — see [stackBlockBannerMessageFor]).
  void _announceStackBlockBanner({
    required GameState beforeState,
    required GameState afterState,
    required CardModel playedCard,
    required String playerId,
    String? playerName,
  }) {
    final message = stackBlockBannerMessageFor(
      beforeState: beforeState,
      afterState: afterState,
      playedCard: playedCard,
      isLocal: playerId == OfflineGameState.localId,
      playerName: playerName,
    );
    if (message == null) return;
    HapticFeedback.mediumImpact();
    _showStackBlockBanner(message.text, message.color);
  }

  void _fireMultiPlayCelebrationIfNeeded(int cardsPlayedThisTurn) {
    if (cardsPlayedThisTurn < kMultiPlayCelebrationMinCards) return;
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final tier = multiPlayCelebrationTierIndex(cardsPlayedThisTurn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tier == 0) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      setState(() {
        _multiPlayCelebrationTrigger++;
        _multiPlayCelebrationTier = tier;
      });
    });
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
    final localAvatarUrl =
        ref.read(userProfileProvider).valueOrNull?.avatarUrl;
    final localCosmetic =
        AvatarCatalogService.instance.equippedCosmeticId;

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
        localAvatarUrl: localAvatarUrl,
        localAvatarCosmeticId: localCosmetic,
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
      _aiConfigs = widget.preloadedAiPlayerConfigs ??
          AiPlayerConfig.generateForGame(
            count: _clampedPlayers - 1,
            seed: seed,
          );

      final aiNameMap = {for (final c in _aiConfigs) c.playerId: c.name};

      final (:gameState, :drawPile) = BustEngine.buildRound(
        playerCount: _clampedPlayers,
        aiNames: aiNameMap,
        seed: seed,
        localDisplayName: localDisplayName,
        localAvatarUrl: localAvatarUrl,
        localAvatarCosmeticId: localCosmetic,
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
          // Fully await each flight (rather than firing unawaited + a short
          // stagger, as table_screen.dart's dealing loop does for a
          // deliberately overlapping "fan deal" look) — with up to 10
          // players here, that pattern can keep several independent
          // AnimationControllers ticking concurrently for several seconds
          // straight, which was crashing with
          // "!semantics.parentDataDirty". No overlap = no concurrent
          // animation-driven rebuilds racing each other.
          await overlay.animateCardDeal(p.id);
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
          avatarUrl: p.avatarUrl,
          localAvatarFilePath:
              p.tablePosition == TablePosition.bottom
                  ? ref.read(profileProvider).avatarPath
                  : null,
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
    _showStackBlockBanner('Deck reshuffled', AppColors.goldDark);
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

    Future.microtask(() async {
      if (!mounted) return;
      // Each Bust round is a completed match in its own right — same hook
      // TableScreen uses for standalone offline/online matches. Awaited so
      // the elimination screen doesn't load underneath the still-visible ad.
      await AdsService.instance.maybeShowInterstitialAfterMatch();
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

  // ── Skip rest of round (rewarded ad) ───────────────────────────────────────

  /// Shows a rewarded ad; only starts fast-forwarding the remaining AI turns
  /// this round if the player watches it to completion (see
  /// [AdsService.showRewardedAd]). The AI turn chain is already running by
  /// the time this is tappable (see [_bustCanSkipRest]) — this just flips
  /// [_bustSimulatingRest] so [_scheduleAiTurn]'s delay collapses to zero.
  Future<void> _onBustSkipTapped() async {
    if (!_bustCanSkipRest || _bustSimulatingRest || _bustSkipAdShowing) return;
    // "Remove Ads" purchasers skip straight to the reward — no ad to watch.
    if (PurchaseService.instance.adsRemoved.value) {
      setState(() => _bustSimulatingRest = true);
      return;
    }
    setState(() => _bustSkipAdShowing = true);
    final shown = await AdsService.instance.showRewardedAd(
      placement: 'bust_skip_reward',
      onEarnedReward: (_) {
        if (mounted) setState(() => _bustSimulatingRest = true);
      },
    );
    if (!mounted) return;
    setState(() => _bustSkipAdShowing = false);
    if (!shown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready yet — try again in a moment.')),
      );
    }
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
      _announceStackBlockBanner(
        beforeState: beforeState,
        afterState: newState,
        playedCard: played.first,
        playerId: OfflineGameState.localId,
        playerName: local.displayName,
      );
      _fireMultiPlayCelebrationIfNeeded(newState.cardsPlayedThisTurn);
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
    final delayMs = _bustSimulatingRest
        // One frame (~16ms), not 0: Duration.zero still resolves far faster
        // than the renderer's frame pacing, so a long simulated chain (up
        // to ~18 turns for 10 players × 2 turns) can fire setState() faster
        // than Flutter's semantics tree can settle between frames, which
        // crashes with "!semantics.parentDataDirty". A real (if tiny) delay
        // forces each turn onto its own frame instead.
        ? 16
        : hasPlayable
            ? ((1000 + _aiDelayRng.nextInt(900)) * diffMult).round()
            : (800 * diffMult).round();

    // Always await this, never skip it for a 0ms case: without a real
    // suspension point here, a long recursive AI-turn chain would run with
    // no yield to the event loop at all, freezing the UI and risking a
    // stack-depth crash.
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

    if (result.playedCards.isNotEmpty) {
      _announceStackBlockBanner(
        beforeState: preTurn,
        afterState: result.state,
        playedCard: result.playedCards.first,
        playerId: aiId,
        playerName: aiName,
      );
    }

    if (result.playedCards.isNotEmpty &&
        result.preTurnAdvanceState.cardsPlayedThisTurn >=
            kMultiPlayCelebrationMinCards) {
      _fireMultiPlayCelebrationIfNeeded(
          result.preTurnAdvanceState.cardsPlayedThisTurn);
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
    if (_moveLogEntries.length > kMoveLogMaxEntries) {
      _moveLogEntries.removeRange(kMoveLogMaxEntries, _moveLogEntries.length);
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

  String? get _thinkingOpponentId {
    if (!_aiThinking) return null;
    final id = _gameState.currentPlayerId;
    if (id == OfflineGameState.localId) return null;
    return id;
  }

  Map<String, QuickChatBubbleData> get _quickChatBubblesByPlayer => {
        for (final b in _quickChatBubbles)
          b.playerId: (
            id: b.id,
            playerName: b.playerName,
            reactionWireIndex: b.reactionWireIndex,
            isLocal: b.isLocal,
          ),
      };

  /// Where this screen's move-log band / stack-block banner floor starts,
  /// derived from Bust's own (non-grid) layout: [BustPlayerRail] height +
  /// [_RoundIndicator]'s approximate height + a small gap. Unlike
  /// [TablePortraitGrid]'s fixed-grid board, Bust's piles sit in a flexible
  /// `Expanded` region with no fixed offset, so [boardTop] is left generous
  /// — the log's own [TablePortraitGrid.moveLogMaxHeight] cap already keeps
  /// it from growing unreasonably tall.
  ({double top, double boardTop}) _bustMoveLogAnchors(
    BuildContext context, {
    required bool landscape,
    double scale = 1.0,
  }) {
    final safeTop = MediaQuery.paddingOf(context).top;
    const railHeight = 96.0;
    const landscapeRailHeight = 72.0;
    const roundIndicatorHeight = 34.0;
    final top = safeTop +
        (landscape ? landscapeRailHeight : railHeight) * scale +
        roundIndicatorHeight * scale +
        TablePortraitGrid.moveLogTopGap * scale;
    final boardTop = top + TablePortraitGrid.moveLogMaxHeight * scale + 200;
    return (top: top, boardTop: boardTop);
  }

  Widget _buildDrawDiscardCluster({
    required Size layoutSize,
    required bool isLandscape,
    required bool isMyTurn,
    double scale = 1.0,
  }) {
    const portraitPileSize = 100.0;
    const portraitPileHeight = 145.0;
    const landscapePileSize = 56.0;
    const landscapePileHeight = 78.0;
    final pileSize = (isLandscape ? landscapePileSize : portraitPileSize) * scale;
    final pileHeight =
        (isLandscape ? landscapePileHeight : portraitPileHeight) * scale;
    final gap = (isLandscape ? 8.0 : 24.0) * scale;

    return Transform.translate(
      offset: !isLandscape && TableChromeLayout.isCompactPhone(layoutSize)
          ? const Offset(0, 0.5)
          : Offset.zero,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: _drawPileKey,
              width: pileSize,
              height: pileHeight,
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: DrawPileWidget(
                  cardCount: _gameState.drawPileCount,
                  cardWidth: pileSize,
                  enabled: !_isDealing &&
                      isMyTurn &&
                      (_gameState.actionsThisTurn == 0 ||
                          _gameState.queenSuitLock != null),
                  onTap: isMyTurn ? _drawCard : null,
                  reshuffleNotifier: _reshuffleNotifier,
                ),
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              key: _discardPileKey,
              width: pileSize,
              height: pileHeight,
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: DiscardPileWidget(
                  topCard: _gameState.discardTopCard,
                  secondCard: _gameState.discardPileHistory.isNotEmpty
                      ? _gameState.discardPileHistory.first
                      : null,
                  discardPileHistory: _gameState.discardPileHistory,
                  cardWidth: pileSize,
                  discardPileCount: _discardPile.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionBar({required bool compact}) {
    final isMyTurn = !_aiThinking &&
        _gameState.currentPlayerId == OfflineGameState.localId;
    final canEndTurn = isMyTurn && canEndTurnButton(_gameState);
    final nextTurnLabel = _gameState.phase == GamePhase.playing
        ? nextPlayerAfterTurnLabel(
            state: _gameState,
            viewerPlayerId: OfflineGameState.localId,
          )
        : null;

    return FloatingActionBarWidget(
      activePlayerName:
          _gameState.playerById(_gameState.currentPlayerId)?.displayName ?? '',
      direction: _gameState.direction,
      canEndTurn: canEndTurn,
      onEndTurn: isMyTurn && !_isDealing ? _endTurn : null,
      pulseLocalTurn: isMyTurn,
      nextTurnLabel: nextTurnLabel,
      isLocalTurn: isMyTurn,
      hasAlreadyDeclared: false,
      lastCardsEnabled: false,
      localHandSize: _localPlayer?.hand.length ?? 0,
      compact: compact,
    );
  }

  Widget _buildLocalHand({
    required PlayerModel localPlayer,
    required double handCardWidth,
    required bool isMyTurn,
    required bool compact,
    double scale = 1.0,
  }) {
    return KeyedSubtree(
      key: _playerZoneKeys[OfflineGameState.localId],
      child: Padding(
        padding: EdgeInsets.only(
          bottom: (compact ? AppDimensions.xs : AppDimensions.sm) * scale,
        ),
        child: SizedBox(
          width: double.infinity,
          child: PlayerZoneWidget(
            player: localPlayer.copyWith(
              cardCount: _isDealing
                  ? (_visibleCardCounts[OfflineGameState.localId] ?? 0)
                  : localPlayer.cardCount,
            ),
            isLocalPlayer: true,
            localAvatarFilePath:
                ref.watch(profileProvider.select((s) => s.avatarPath)),
            isActiveTurn: isMyTurn,
            compact: compact,
            scale: scale,
            skipSeatHighlight:
                _skipHighlightPlayerIds.contains(OfflineGameState.localId),
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
              cardWidth: handCardWidth,
              invalidPlayShakeTrigger: _handShakeNotifier,
              scale: scale,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBustPortraitTable({
    required Size layoutSize,
    required List<BustPlayerViewModel> opponents,
    required PlayerModel localPlayer,
    required bool isMyTurn,
    required double handCardWidth,
    required bool isMobile,
    required BustRoundState roundState,
    double scale = 1.0,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppDimensions.xs : AppDimensions.md,
      ),
      child: Column(
        children: [
          BustPlayerRail(
            slots: List<BustPlayerViewModel?>.from(opponents),
            slotKeyBuilder: (p) => _playerZoneKeys[p.id],
            height: 96,
            scale: scale,
            thinkingPlayerId: _thinkingOpponentId,
            skipHighlightPlayerIds: _skipHighlightPlayerIds,
            quickChatBubblesByPlayer: _quickChatBubblesByPlayer,
            onRemoveQuickChatBubble: _removeQuickChatBubble,
          ),
          _RoundIndicator(roundState: roundState, scale: scale),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 72 * scale),
                  SizedBox(
                    height: (isMobile ? AppDimensions.sm : AppDimensions.md) * scale,
                  ),
                  _buildDrawDiscardCluster(
                    layoutSize: layoutSize,
                    isLandscape: false,
                    isMyTurn: isMyTurn,
                    scale: scale,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: (isMobile ? AppDimensions.sm : AppDimensions.md) * scale,
            ),
            child: _buildFloatingActionBar(compact: false),
          ),
          _buildLocalHand(
            localPlayer: localPlayer,
            handCardWidth: handCardWidth,
            isMyTurn: isMyTurn,
            compact: false,
            scale: scale,
          ),
        ],
      ),
    );
  }

  Widget _buildBustLandscapeTable({
    required Size layoutSize,
    required List<BustPlayerViewModel> opponents,
    required PlayerModel localPlayer,
    required bool isMyTurn,
    required BustRoundState roundState,
    double scale = 1.0,
  }) {
    final handCardWidth = 40.0 * scale;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.xs),
      child: Column(
        children: [
          BustPlayerRail(
            slots: List<BustPlayerViewModel?>.from(opponents),
            slotKeyBuilder: (p) => _playerZoneKeys[p.id],
            height: 72,
            compact: true,
            scale: scale,
            thinkingPlayerId: _thinkingOpponentId,
            skipHighlightPlayerIds: _skipHighlightPlayerIds,
            quickChatBubblesByPlayer: _quickChatBubblesByPlayer,
            onRemoveQuickChatBubble: _removeQuickChatBubble,
          ),
          _RoundIndicator(roundState: roundState, scale: scale),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 2 * scale),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildDrawDiscardCluster(
                  layoutSize: layoutSize,
                  isLandscape: true,
                  isMyTurn: isMyTurn,
                  scale: scale,
                ),
                SizedBox(width: 12 * scale),
                Transform.translate(
                  key: _hudOverlayKey,
                  offset: const Offset(0, -1),
                  child: HudOverlayWidget(
                    activeSuit: _gameState.suitLock,
                    queenSuitLock: _gameState.queenSuitLock,
                    penaltyCount: _gameState.activePenaltyCount,
                    compact: true,
                    scale: scale,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 2 * scale),
          _buildFloatingActionBar(compact: true),
          SizedBox(height: 2 * scale),
          Expanded(
            child: _buildLocalHand(
              localPlayer: localPlayer,
              handCardWidth: handCardWidth,
              isMyTurn: isMyTurn,
              compact: true,
              scale: scale,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final opponents = _bustPlayers.where((p) => !p.isLocal).toList();
    final localPlayer = _localPlayer;
    final isMyTurn = !_aiThinking &&
        _gameState.currentPlayerId == OfflineGameState.localId;
    final rs = _roundManager.state;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          final isMobile = math.min(layoutSize.width, layoutSize.height) <
              AppDimensions.breakpointMobile;
          final isLandscapeMobile =
              TableChromeLayout.isLandscapeMobile(layoutSize);
          // Same shared curve the main table screen uses (TableChromeLayout
          // .scaleFor) — tablets/desktop get chrome scaled toward the
          // available canvas instead of staying phone-sized.
          final bustScale = TableChromeLayout.scaleFor(layoutSize);
          // Move log / banners stay near phone size on tablets so they don't
          // cover the center piles when chrome scales up (shared with Table).
          final overlayScale = TableChromeLayout.overlayScaleFor(layoutSize);
          // See table_screen_layout.dart's identical fix: multiply the
          // width-percentage formula by bustScale too, not just the clamp
          // ceiling, so actual card size keeps pace with the frame height.
          final handCardWidth =
              (layoutSize.width * (isMobile ? 0.12 : 0.1) * (isMobile ? 1.0 : bustScale))
                  .clamp(44.0, 82.0 * bustScale);

          return Stack(
            children: [
              const FeltTableBackground(),

              Positioned.fill(
                child: IgnorePointer(
                  child: MultiCardPlayCelebrationOverlay(
                    trigger: _multiPlayCelebrationTrigger,
                    tierIndex: _multiPlayCelebrationTier,
                  ),
                ),
              ),

              if (localPlayer != null)
                // Excludes the whole gameplay area from the semantics tree
                // while dealing — this is the highest-churn window (rapid
                // setState + card-flight animations updating hand/player
                // widgets every ~100ms) and iOS Simulator runs with
                // accessibility forced on, which is known to expose a
                // longstanding Flutter framework semantics-tree race
                // ("!semantics.parentDataDirty", flutter/flutter#7861) under
                // exactly this kind of rapid concurrent rebuild. Semantics
                // resume normally once dealing finishes.
                ExcludeSemantics(
                  excluding: _isDealing,
                  child: SafeArea(
                    child: isLandscapeMobile
                        ? _buildBustLandscapeTable(
                            layoutSize: layoutSize,
                            opponents: opponents,
                            localPlayer: localPlayer,
                            isMyTurn: isMyTurn,
                            roundState: rs,
                            scale: bustScale,
                          )
                        : _buildBustPortraitTable(
                            layoutSize: layoutSize,
                            opponents: opponents,
                            localPlayer: localPlayer,
                            isMyTurn: isMyTurn,
                            handCardWidth: handCardWidth,
                            isMobile: isMobile,
                            roundState: rs,
                            scale: bustScale,
                          ),
                  ),
                ),

              if (_moveLogEntries.isNotEmpty)
                Builder(builder: (context) {
                  final anchors = _bustMoveLogAnchors(
                    context,
                    landscape: isLandscapeMobile,
                    scale: bustScale,
                  );
                  return MoveLogOverlay(
                    entries: _moveLogEntries,
                    top: anchors.top,
                    boardTop: anchors.boardTop,
                    scale: overlayScale,
                  );
                }),

              if (_stackBlockBannerText != null)
                Builder(builder: (context) {
                  final anchors = _bustMoveLogAnchors(
                    context,
                    landscape: isLandscapeMobile,
                    scale: bustScale,
                  );
                  return StackBlockBannerOverlay(
                    text: _stackBlockBannerText!,
                    color: _stackBlockBannerColor!,
                    appTheme: theme,
                    discardPileKey: _discardPileKey,
                    minTop: moveLogBottomPx(
                      entries: _moveLogEntries,
                      top: anchors.top,
                      boardTop: anchors.boardTop,
                      scale: overlayScale,
                    ),
                    scale: overlayScale,
                  );
                }),

              if (!isLandscapeMobile)
                Positioned(
                  top: MediaQuery.sizeOf(context).height * 0.63 - 1.0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: HudOverlayWidget(
                        key: _hudOverlayKey,
                        activeSuit: _gameState.suitLock,
                        queenSuitLock: _gameState.queenSuitLock,
                        penaltyCount: _gameState.activePenaltyCount,
                        scale: bustScale,
                      ),
                    ),
                  ),
                ),

              // Direction indicator — suit-lock HUD slot, same as table play.
              Positioned.fill(
                child: IgnorePointer(
                  child: Builder(builder: (context) {
                    final anchors = _bustMoveLogAnchors(
                      context,
                      landscape: isLandscapeMobile,
                      scale: bustScale,
                    );
                    return DirectionBannerAtHud(
                      hudKey: _hudOverlayKey,
                      direction: _gameState.direction,
                      kingJustPlayed:
                          _gameState.lastPlayedThisTurn?.effectiveRank == Rank.king,
                      minTop: moveLogBottomPx(
                        entries: _moveLogEntries,
                        top: anchors.top,
                        boardTop: anchors.boardTop,
                        scale: overlayScale,
                      ),
                      scale: overlayScale,
                    );
                  }),
                ),
              ),

              // Dealing animation overlay (cards flying from draw pile) —
              // purely decorative, never needs semantics.
              Positioned.fill(
                child: ExcludeSemantics(
                  child: DealingAnimationOverlay(
                    key: _dealingOverlayKey,
                    drawPileKey: _drawPileKey,
                    playerKeys: _playerZoneKeys,
                  ),
                ),
              ),

              // Card play flight overlay — same, purely decorative.
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CardFlightOverlay(key: _playFlightKey),
                ),
              ),

              // Direction: left slot of [FloatingActionBarWidget] (no Last Cards in Bust).

              // Settings + back
              Positioned(
                bottom: 0,
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
                  bottom: 0,
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

              // ── Bust skip (rewarded ad, once local has used both turns) ─────
              // Always mounted — toggling via `if (...) Positioned(...)`
              // inserts/removes this InkWell/Material subtree (and its
              // semantics nodes) from the Stack exactly when a burst of
              // AI-turn state updates is starting, which reliably crashed
              // with "!semantics.parentDataDirty". Visibility with
              // maintainState/maintainAnimation/maintainSize keeps the
              // Element/RenderObject alive and in place; only paint/hit-test/
              // semantics are toggled, which Flutter handles safely.
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 170,
                left: 0,
                right: 0,
                child: Center(
                  child: Visibility(
                    visible: _bustCanSkipRest &&
                        !_isDealing &&
                        _gameState.phase != GamePhase.ended,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: Builder(
                      builder: (context) {
                        final busy = _bustSimulatingRest || _bustSkipAdShowing;
                        // A loaded rewarded ad isn't guaranteed to be sitting
                        // there when this button renders — don't offer a tap
                        // that can only end in a "try again" snackbar.
                        final adReady = AdsService.instance.isRewardedAdReady;
                        final disabled = busy || !adReady;
                        final label = _bustSimulatingRest
                            ? 'Simulating…'
                            : _bustSkipAdShowing
                                ? 'Loading ad…'
                                : !adReady
                                    ? 'Ad loading…'
                                    : 'Watch ad to skip';
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: disabled
                                ? null
                                : () {
                                    unawaited(_onBustSkipTapped());
                                  },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: disabled
                                    ? Colors.white24
                                    : AppColors.goldPrimary.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: disabled ? Colors.white38 : AppColors.goldDark,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (busy)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.ondemand_video_rounded,
                                      size: 20,
                                      color: Colors.black87,
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: disabled ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
  const _RoundIndicator({required this.roundState, this.scale = 1.0});

  final BustRoundState roundState;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final rotation = roundState.currentRotation;
    final round = roundState.roundNumber;

    return Padding(
      padding: EdgeInsets.only(top: 2 * scale, bottom: 4 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
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
                fontSize: 12 * scale,
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
