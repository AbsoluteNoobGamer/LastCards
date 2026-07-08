import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/features/gameplay/presentation/animations/win_particles.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_flight_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/dealing_animation_overlay.dart';

import '../../domain/usecases/offline_game_engine.dart';
import 'package:last_cards/shared/engine/shuffle_utils.dart';
import 'package:last_cards/shared/rules/move_log_support.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart'
    show lastCardsMaxHandSize, mayDeclareLastCards;
import 'package:last_cards/shared/rules/win_condition_rules.dart'
    show canConfirmPlayerWin, needsUndeclaredLastCardsDraw, wouldConfirmWin;
import '../../data/datasources/offline_game_state_datasource.dart';
import '../../../../shared/engine/game_turn_timer.dart';

import '../controllers/connection_provider.dart';
import '../controllers/game_provider.dart';
import '../../data/datasources/websocket_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/services/ads_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../core/utils/ranked_tier_utils.dart';
import '../../../../core/models/table_position_layout.dart';
import '../../../../core/models/move_log_entry.dart';
import '../../../../core/models/move_log_merge.dart';
import '../../../../core/models/game_event.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/providers/profile_provider.dart';
import '../widgets/multi_card_play_celebration.dart';
import '../widgets/discard_pile_widget.dart';
import '../widgets/draw_pile_widget.dart';
import '../widgets/hud_overlay_widget.dart';
import '../widgets/player_hand_widget.dart';
import '../widgets/ace_suit_picker_sheet.dart';
import '../widgets/player_zone_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/floating_action_bar_widget.dart';
import '../widgets/last_cards_table_strip.dart';
import '../widgets/turn_indicator_overlay.dart';
import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';
import '../widgets/game_move_log_overlay.dart'
    show GameMoveLogPanel;
import '../widgets/quick_chat_panel.dart';
import '../widgets/quick_chat_bubble.dart';
import '../widgets/felt_table_background.dart';

import '../../../../shared/reactions/reaction_catalog.dart';

import '../../../../widgets/turn_timer_bar.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';
import '../../../../features/bust/models/bust_player_view_model.dart';
import '../../../../features/bust/widgets/bust_player_rail.dart';
import '../../../../features/leaderboard/data/leaderboard_stats_writer.dart';
import '../../../../features/leaderboard/data/combo_leaderboard_writer.dart';
import '../../../../features/tournament/providers/tournament_session_provider.dart';
import '../../../../features/social/widgets/other_player_profile_sheet.dart';
import '../../../../features/social/widgets/pending_friend_requests_banner.dart';
import '../../../../features/settings/presentation/widgets/settings_modal.dart';
part 'table_screen_background.dart';
part 'table_screen_layout.dart';
part 'table_screen_overlays.dart';
part 'table_screen_sheets.dart';
part 'table_transient_overlays.dart';

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
  final void Function(String playerId, int finishPosition) onPlayerFinished;
  final Map<String, String> tournamentPlayerNameByTableId;
  final GameState? debugInitialOfflineState;
  final List<CardModel>? debugInitialDrawPile;
  final bool debugSkipDealAnimation;
  final AiDifficulty? aiDifficulty;

  /// Whether this table is a live online session (server-authoritative via
  /// [gameStateProvider]) or a local offline/AI session.
  ///
  /// This MUST be passed explicitly by the caller — it must never be
  /// inferred from whether [gameStateProvider] currently has a value, since
  /// that value arrives asynchronously (websocket snapshot) and checking it
  /// at an arbitrary moment races with that arrival. Every real navigation
  /// site already knows for certain which kind of game it's launching
  /// (lobby/splash → online, single-player loading → offline, tournament
  /// coordinator → tracks its own isOnline) — so there is no legitimate
  /// case where this should be guessed instead of passed.
  final bool isOnline;

  /// When set (e.g. from the opponents splash), reuses the same AI roster.
  final List<AiPlayerConfig>? preloadedAiPlayerConfigs;

  const TableScreen({
    this.totalPlayers = 2,
    this.isTournamentMode = false,
    this.onPlayerFinished = _defaultOnPlayerFinished,
    this.tournamentPlayerNameByTableId = const <String, String>{},
    this.debugInitialOfflineState,
    this.debugInitialDrawPile,
    this.debugSkipDealAnimation = false,
    this.aiDifficulty,
    this.isOnline = false,
    this.preloadedAiPlayerConfigs,
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
    this.isAbandoned = false,
  });

  final List<String> finishedPlayerIds;
  final String eliminatedPlayerId;

  /// User left the table before the round completed (e.g. confirmed Leave).
  final bool isAbandoned;

  /// Returned when the player confirms Leave from the tournament table so the
  /// coordinator can exit the whole tournament instead of replaying the round.
  static const TournamentRoundGameResult abandoned = TournamentRoundGameResult(
    finishedPlayerIds: <String>[],
    eliminatedPlayerId: '',
    isAbandoned: true,
  );
}

@visibleForTesting
bool shouldShowStandardWinOverlay({required bool isTournamentMode}) {
  return !isTournamentMode;
}

class _TableScreenState extends ConsumerState<TableScreen> {
  String? _selectedCardId;
  String? _flyingCardId;

  /// Latest move log entries (newest first, max 3).
  final List<MoveLogEntry> _moveLogEntries = <MoveLogEntry>[];

  /// Local display order of the player's hand (card IDs).
  /// New cards are appended to the right; drag-and-drop updates this list.
  List<String> _handOrder = [];

  bool _isDealing = false;
  final Map<String, int> _visibleCardCounts = {};

  // Animation overlay keys
  final GlobalKey<DealingAnimationOverlayState> _overlayKey =
      GlobalKey<DealingAnimationOverlayState>();
  final GlobalKey<CardFlightOverlayState> _playFlightKey =
      GlobalKey<CardFlightOverlayState>();
  final GlobalKey _drawPileKey = GlobalKey();
  final GlobalKey _discardPileKey = GlobalKey();
  final GlobalKey _hudKey = GlobalKey();
  final Map<String, GlobalKey> _playerZoneKeys = {};
  final Set<String> _skipHighlightPlayerIds = <String>{};
  Timer? _skipHighlightClearTimer;
  Timer? _stackBlockBannerClearTimer;

  /// Mutable offline state — set by initState via buildWithDeck().
  late GameState _offlineState;

  bool _aiThinking = false;

  /// When [_scheduleAiTurn] is re-entered while [_aiThinking] is still true,
  /// the guard used to drop the follow-up entirely (stall). Queue one pending
  /// turn and drain it when the in-flight turn clears the flag in [finally].
  final Queue<({String id, bool simulate})> _pendingOfflineAiTurns =
      Queue<({String id, bool simulate})>();

  /// Guards against concurrent local async actions (play/draw/penalty).
  /// Set true before any await in those methods, reset at every exit.
  bool _localActionInProgress = false;
  final math.Random _aiDelayRng = math.Random();
  final List<String> _tournamentFinishedPlayerIds = <String>[];
  bool _tournamentRoundComplete = false;

  // ── Real shuffled draw pile + discard tracking ────────────────────
  late List<CardModel> _drawPile; // actual remaining cards
  final List<CardModel> _discardPile = []; // tracks all discarded cards
  /// In online mode we don't have the full discard list; track count for stack depth.
  int _onlineDiscardCount = 1;
  bool _onlineWinDialogShown = false;

  /// After the user dismisses the online win dialog with KEEP WATCHING (spectate).
  /// Prevents [ref.listen] from opening the dialog again on unrelated state updates.
  bool _spectating = false;

  /// Prevents overlapping online plays while a last-card flight runs.
  bool _onlineLastCardFlightInProgress = false;

  /// Chains draw-pile → player flights per player so multi-card draws stay sequential.
  final Map<String, Future<void>> _onlineDrawFlightChains = {};
  bool _bustLeaderboardRecorded = false;

  /// True when this session is offline (local/AI, not server-authoritative).
  /// Derived once from [TableScreen.isOnline] in [_initNewGame] — never
  /// re-inferred from [gameStateProvider] elsewhere in this file. Used to
  /// show "Skip" in tournament when qualified.
  bool _isOfflineSession = true;

  /// True only in the rare case where [TableScreen.isOnline] is true but the
  /// first server snapshot hasn't arrived in [gameStateProvider] yet. While
  /// true, [build] shows a lightweight waiting state instead of guessing a
  /// mode and starting local offline logic.
  bool _awaitingFirstOnlineSnapshot = false;

  /// When true, we're fast-forwarding the rest of the round after user tapped Skip.
  bool _tournamentSimulatingRest = false;
  // ── Turn timer ────────────────────────────────────────────────────
  late final GameTurnTimer _engineTimer = GameTurnTimer();
  StreamSubscription<int>? _timerWarningSub;
  StreamSubscription<CardPlayedEvent>? _onlineCardPlaysSub;
  StreamSubscription<CardDrawnEvent>? _onlineCardDrawsSub;
  StreamSubscription<InvalidPlayPenaltyEvent>? _onlineInvalidPlayPenaltySub;
  StreamSubscription<ErrorEvent>? _onlineErrorsSub;
  StreamSubscription<dynamic>? _onlineTurnTimeoutSub;
  StreamSubscription<dynamic>? _onlineReshuffleSub;
  StreamSubscription<QuickChatEvent>? _onlineQuickChatSub;
  StreamSubscription<TurnChangedEvent>? _onlineTurnChangedSub;
  StreamSubscription<LastCardsBluffEvent>? _lastCardsBluffSub;
  StreamSubscription<LastCardsPressedEvent>? _lastCardsPressedSub;
  StreamSubscription<GameMomentEvent>? _gameMomentSub;
  String? _stackBlockBannerText;
  Color? _stackBlockBannerColor;

  int _multiPlayCelebrationTrigger = 0;
  int _multiPlayCelebrationTier = 0;
  /// Null when this celebration is reused for a non-combo beat (e.g. a
  /// stack-cancel flash) that has no real card count to report.
  int? _multiPlayCelebrationCardCount;

  /// Cards the *local* player has played so far this turn, accumulated across
  /// possibly several plays (e.g. stacking same-rank cards one action at a
  /// time) — tracked purely for the longest-combo leaderboard, independent of
  /// [GameState.discardPileHistory] (which is capped and shared/synced).
  List<CardModel> _localComboCardsThisTurn = [];

  String? _lastCardsBluffBannerText;
  String? _lastCardsDeclaredBannerText;

  /// Clears the declare banner only for the latest [_announceLastCardsDeclaration] call.
  int _lastCardsDeclaredBannerSeq = 0;

  /// Offline: [applyOpeningSeatLastCardsSeedIfNeeded] ran at deal — show banner/move log.
  bool _pendingOpeningLastCardsAnnouncement = false;

  /// Tracks [GameState.currentPlayerId] across [turn_changed] events so we can
  /// finalize move-log entries for the player whose turn ended (server
  /// `card_played.turnContinues` is unreliable because applyPlay does not
  /// advance [currentPlayerId]).
  String? _onlineLastKnownCurrentPlayerId;
  bool _timerWarningPlayed = false;
  int? _lastTimerTickSeconds;

  bool _showQuickChatPanel = false;

  /// Incremented to retrigger full-screen edge feedback animations.
  int _turnPulseTrigger = 0;
  int _penaltyFlashTrigger = 0;

  /// Tracks [GameState.currentPlayerId] for your-turn edge pulse (transition onto local).
  String? _prevTurnPlayerIdForEdge;

  /// HUD penalty badge increased — screen-edge red pulse (skipped during
  /// offline tournament fast-forward so skip-to-result stays visually quiet).
  void _bumpPenaltyFlashForHud() {
    if (_tournamentSimulatingRest) return;
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() => _penaltyFlashTrigger++);
  }

  bool _isLocalMomentPlayer(String playerId) {
    if (_isOfflineSession) return playerId == OfflineGameState.localId;
    return ref.read(gameStateProvider)?.localPlayer?.id == playerId;
  }

  void _momentPenaltyHit({required String playerId, required int cardsDrawn}) {
    if (_tournamentSimulatingRest) return;
    if (!_isLocalMomentPlayer(playerId) && cardsDrawn < 4) return;
    _bumpPenaltyFlashForHud();
    if (_isLocalMomentPlayer(playerId)) {
      HapticFeedback.heavyImpact();
    }
  }

  void _announcePenaltyChainAction({
    required GameState beforeState,
    required GameState afterState,
    required CardModel playedCard,
    required String playerId,
    String? playerName,
  }) {
    if (_tournamentSimulatingRest) return;

    final chainWasActive = beforeState.activePenaltyCount > 0 ||
        beforeState.penaltyChainLive;
    final isLocal = _isLocalMomentPlayer(playerId);
    final name = playerName?.split(' ').first ?? 'Player';

    final String bannerText;
    final Color bannerColor;
    if (playedCard.effectiveRank == Rank.two) {
      bannerText = isLocal
          ? '+2 added to the stack!'
          : '$name added +2 to the stack!';
      bannerColor = const Color(0xFFE53935);
    } else if (playedCard.effectiveRank == Rank.jack &&
        !playedCard.suit.isRed) {
      bannerText = isLocal
          ? '+5 added to the stack!'
          : '$name added +5 to the stack!';
      bannerColor = const Color(0xFFE53935);
    } else if (playedCard.effectiveRank == Rank.jack &&
        playedCard.suit.isRed) {
      bannerText = isLocal
          ? 'Pick up cancelled!'
          : '$name cancelled the pick up!';
      bannerColor = AppColors.goldPrimary;
    } else if (chainWasActive &&
        afterState.activePenaltyCount == 0 &&
        !afterState.penaltyChainLive) {
      bannerText =
          isLocal ? 'Stack cancelled!' : '$name cancelled the stack!';
      bannerColor = AppColors.goldPrimary;
    } else {
      return;
    }

    _bumpPenaltyFlashForHud();
    HapticFeedback.mediumImpact();
    setState(() {
      _stackBlockBannerText = bannerText;
      _stackBlockBannerColor = bannerColor;
      _multiPlayCelebrationTier = 1;
      _multiPlayCelebrationCardCount = null;
      _multiPlayCelebrationTrigger++;
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _stackBlockBannerText = null;
          _stackBlockBannerColor = null;
        });
      }
    });
  }

  /// Shows [text] in the stack-block banner for a beat, then clears it.
  /// Generic display helper — unlike [_announcePenaltyChainAction], this
  /// carries no penalty-specific side effects (HUD flash, haptics).
  void _showStackBlockBanner(String text, Color color) {
    if (_tournamentSimulatingRest) return;
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

  void _announceOnlinePenaltyChainFromCardPlay(CardPlayedEvent e) {
    if (e.cards.isEmpty) return;
    final gs = ref.read(gameStateProvider);
    if (gs == null) return;

    // [GameNotifier] may have already patched discard top onto [gs].
    final previousTop =
        gs.discardPileHistory.isNotEmpty ? gs.discardPileHistory.last : null;
    final beforeState = gs.copyWith(
      discardTopCard: previousTop,
      discardPileHistory: gs.discardPileHistory.length > 1
          ? gs.discardPileHistory.sublist(0, gs.discardPileHistory.length - 1)
          : [],
    );
    final afterState = applyPlay(
      state: beforeState,
      playerId: e.playerId,
      cards: e.cards,
    );
    _announcePenaltyChainAction(
      beforeState: beforeState,
      afterState: afterState,
      playedCard: e.cards.first,
      playerId: e.playerId,
      playerName: gs.playerById(e.playerId)?.displayName,
    );
  }

  void _momentLastCardsPulse({required String playerId}) {
    if (_tournamentSimulatingRest) return;
    if (!mounted) return;
    setState(() => _turnPulseTrigger++);
    if (!_isLocalMomentPlayer(playerId)) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Seconds remaining until next quick chat can be sent (10s cooldown).
  int _quickChatCooldownRemaining = 0;
  Timer? _quickChatCooldownTimer;

  /// Reaction bubbles: wire index into shared catalog per entry.
  /// Max 2 visible at once.
  List<
      ({
        String id,
        String playerId,
        String playerName,
        int reactionWireIndex,
        bool isLocal
      })> _quickChatBubbles = [];

  /// When > 0, next N card_drawn for this player are part of an invalid-play
  /// penalty (we already logged them via invalid_play_penalty). Skip adding.
  final Map<String, int> _suppressDrawLogForPlayer = {};

  /// Cached for dispose — cannot use [ref] after widget is disposed.
  WebSocketClient? _wsClientToDisconnectOnDispose;

  /// Cached for dispose — clears stale ranked / snapshot state when leaving an
  /// online table without going through the Leave confirmation (e.g. nav pop).
  GameNotifier? _gameNotifierToClearOnDispose;

  /// Toggled (not set) each time a reshuffle fires so DrawPileWidget can
  /// play the shuffle animation even on repeated reshuffles.
  final ValueNotifier<bool> _reshuffleNotifier = ValueNotifier<bool>(false);

  /// Increment to run a short invalid-play shake on [PlayerHandWidget].
  final ValueNotifier<int> _handShakeNotifier = ValueNotifier<int>(0);

  /// AI opponent configurations for this game session (names, personality,
  /// avatar colors). Regenerated each time [_initNewGame] is called.
  List<AiPlayerConfig> _aiPlayerConfigs = [];

  final math.Random _chatRng = math.Random();

  // ── Post-game stat tracking (offline only, reset each round) ─────────────
  final Map<String, int> _matchCardsPlayed = {};
  final Map<String, int> _matchDrawsTaken = {};
  final Map<String, int> _matchSpecialsPlayed = {};
  final Stopwatch _gameStopwatch = Stopwatch();
  @override
  void initState() {
    super.initState();
    _initNewGame();
    _subscribeToOnlineMoveLogIfNeeded();
  }

  void _subscribeToOnlineMoveLogIfNeeded() {
    if (_isOfflineSession) return;
    final handler = ref.read(gameEventHandlerProvider);
    _onlineLastKnownCurrentPlayerId =
        ref.read(gameStateProvider)?.currentPlayerId;

    // In online mode the server deals cards before the client navigates here.
    // The game state is already initialised in _initNewGame(), so no deal
    // animation is needed. We keep player zone keys and hand order in sync
    // via the provider-driven rebuild (ref.watch(gameStateProvider)).

    _onlineCardPlaysSub = handler.cardPlays.listen((e) async {
      if (!_isOfflineSession) {
        _announceOnlinePenaltyChainFromCardPlay(e);
      }
      final localId = ref.read(gameStateProvider)?.localPlayer?.id;
      final isOpponent = localId != null && e.playerId != localId;
      if (isOpponent) {
        // [GameNotifier] increments _opponentFlightsInFlight synchronously on
        // card_played; we must always decrement (even if unmounted mid-flight)
        // so deferred state_snapshot queues cannot stall forever.
        final notifier = ref.read(gameNotifierProvider.notifier);
        try {
          await _runOnlineOpponentPlayFlights(e);
        } finally {
          notifier.opponentPlayFlightsFinished();
        }
      }
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      final actions = e.cards.map((c) => MoveCardAction(card: c)).toList();
      setState(() {
        _onlineDiscardCount += e.cards.length;
        mergeOrPrependPlayLog(
          _moveLogEntries,
          MoveLogEntry.play(
            playerId: e.playerId,
            playerName: name,
            cardActions: actions,
            skippedPlayerNames: e.skippedPlayers,
            turnContinues: e.turnContinues,
          ),
        );
      });
      if (e.skippedPlayers.isNotEmpty) {
        _flashSkipHighlight(
          _playerIdsForSkippedNames(state, e.skippedPlayers),
        );
      }
      final turnTotal = e.cardsPlayedThisTurnAfter;
      if (turnTotal != null) {
        _trackLocalComboForLeaderboard(
          playerId: e.playerId,
          justPlayed: e.cards,
          cardsPlayedThisTurn: turnTotal,
        );
      }
      if (turnTotal != null &&
          turnTotal >= kMultiPlayCelebrationMinCards) {
        _fireMultiPlayCelebrationIfNeeded(turnTotal);
      }
    });

    _onlineInvalidPlayPenaltySub = handler.invalidPlayPenalties.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      setState(() {
        _suppressDrawLogForPlayer[e.playerId] = e.drawCount;
        _pushMoveLog(MoveLogEntry.invalidPlayDraw(
          playerId: e.playerId,
          playerName: name,
          drawCount: e.drawCount,
        ));
      });
    });

    _onlineCardDrawsSub = handler.cardDraws.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      _enqueueOnlineDrawFlight(e.playerId);
      final suppress = _suppressDrawLogForPlayer[e.playerId] ?? 0;
      if (suppress > 0) {
        setState(() {
          _suppressDrawLogForPlayer[e.playerId] = suppress - 1;
          if (_suppressDrawLogForPlayer[e.playerId] == 0) {
            _suppressDrawLogForPlayer.remove(e.playerId);
          }
        });
        return;
      }
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      setState(() {
        mergeOrPrependDrawLog(
          _moveLogEntries,
          MoveLogEntry.draw(
            playerId: e.playerId,
            playerName: name,
            drawCount: 1,
          ),
        );
      });
    });

    _onlineErrorsSub = handler.errors.listen((e) {
      if (mounted) _showError(e.message);
    });

    // When the turn advances, mark the previous player's play entry as no
    // longer continuing (mirrors offline _finalizeTurnLogForPlayer on end turn).
    _onlineTurnChangedSub = handler.turnChanges.listen((e) {
      if (!mounted) return;
      final endedTurnFor = _onlineLastKnownCurrentPlayerId;
      _onlineLastKnownCurrentPlayerId = e.newCurrentPlayerId;
      if (endedTurnFor == null) return;
      setState(() => _finalizeTurnLogForPlayer(endedTurnFor));
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
    // its animation and show the stack-block banner (same as offline mode).
    _onlineReshuffleSub = handler.reshuffles.listen((e) {
      if (!mounted) return;
      game_audio.AudioService.instance.playSound(GameSound.shuffleDeck);
      setState(() {
        _onlineDiscardCount = 1;
        _reshuffleNotifier.value = !_reshuffleNotifier.value;
      });
      _showStackBlockBanner('Reshuffling deck...', AppColors.goldDark);
    });

    // ── Quick chat ─────────────────────────────────────────────────────────
    // Incoming quick chat from other players (local player's own messages
    // are shown immediately in _sendQuickChat).
    _onlineQuickChatSub = handler.quickChats.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final localPlayer = state.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      if (localPlayer != null && e.playerId == localPlayer.id) return;
      final senderName =
          state.playerById(e.playerId)?.displayName ?? e.playerId;
      _showQuickChatBubble(e.playerId, senderName, e.messageIndex,
          isLocal: false);
    });

    _lastCardsBluffSub = handler.lastCardsBluffs.listen((e) {
      if (!mounted) return;
      _flashLastCardsBluffBanner(
        '"${e.playerName}" bluffed Last Cards! Drew ${e.drawCount} cards.',
      );
    });

    _lastCardsPressedSub = handler.lastCardsPressed.listen((e) {
      if (!mounted) return;
      final state = ref.read(gameStateProvider);
      if (state == null) return;
      final name = state.playerById(e.playerId)?.displayName ?? e.playerId;
      final localId = state.localPlayer?.id;
      if (localId != null && e.playerId == localId) {
        setState(() {
          _pushMoveLog(MoveLogEntry.lastCardsDeclared(
            playerId: e.playerId,
            playerName: name,
          ));
        });
        return;
      }
      _announceLastCardsDeclaration(
        playerId: e.playerId,
        playerName: name,
        pushMoveLog: true,
      );
    });

    _gameMomentSub = handler.gameMoments.listen(_onOnlineGameMoment);

    // Start turn timer when it's our turn in online mode (e.g. game just started)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_isOfflineSession &&
          ref.read(isLocalTurnProvider)) {
        _startTimer();
      }
    });
  }

  void _initNewGame() {
    _pendingOfflineAiTurns.clear();
    _matchCardsPlayed.clear();
    _matchDrawsTaken.clear();
    _matchSpecialsPlayed.clear();
    _pendingOpeningLastCardsAnnouncement = false;

    // [gameNotifierProvider] keeps the last online [GameState] (including
    // lastCardsDeclaredBy) after game_ended until an explicit clear — SP flows
    // often never hit those clears. Drop ended snapshots so new tables don't
    // inherit declaration UI from the previous match.
    var liveState = ref.read(gameStateProvider);
    if (liveState?.phase == GamePhase.ended) {
      ref.read(gameNotifierProvider.notifier).clearOnlineState();
      liveState = null;
    }
    _bustLeaderboardRecorded = false;
    _tournamentSimulatingRest = false;

    if (widget.isOnline && liveState == null) {
      // Server snapshot hasn't landed yet. This shouldn't happen on the
      // normal navigation paths (they gate on the first snapshot before
      // ever constructing TableScreen), but if it ever does, wait for it
      // instead of silently mis-starting as an offline session — that
      // mismatch (widget.isOnline true, but running local offline logic)
      // is exactly what caused desyncs before this flag existed.
      _isOfflineSession = false;
      _awaitingFirstOnlineSnapshot = true;
      return;
    }

    if (widget.isOnline && liveState != null) {
      final snap = liveState;
      _isOfflineSession = false;
      _awaitingFirstOnlineSnapshot = false;
      // Online mode: server sent state. Run visual deal animation then use it.
      _offlineState = snap;
      _drawPile = [];
      _tournamentFinishedPlayerIds.clear();
      _tournamentRoundComplete = false;
      _discardPile.clear();
      _onlineDiscardCount = 1; // one card already on discard (discardTopCard)
      _onlineWinDialogShown = false;
      _spectating = false;

      if (snap.discardTopCard != null) {
        _discardPile.add(snap.discardTopCard!);
      }
      _moveLogEntries.clear();
      _playerZoneKeys.clear();
      for (final p in snap.players) {
        _playerZoneKeys[p.id] = GlobalKey();
      }
      final localStart = snap.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      _handOrder = localStart?.hand.map((c) => c.id).toList() ?? [];

      // Start deal animation: mask hands, show countdown, then animate cards in.
      setState(() {
        _isDealing = true;
        _visibleCardCounts.clear();
        for (final p in snap.players) {
          _visibleCardCounts[p.id] = 0;
        }
        // Pre-deal countdown (54 - 1 face-up = 53), matching offline.
        _offlineState = snap.copyWith(drawPileCount: 53);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startDealAnimation();
      });
      _gameStopwatch
        ..reset()
        ..start();
      AnalyticsService.instance.logGameStarted(
        mode: 'online',
        playerCount: snap.players.length,
      );
      return;
    }

    // widget.isOnline is false here (the two branches above already
    // returned for the online case, snapshot present or not).
    _isOfflineSession = true;
    _awaitingFirstOnlineSnapshot = false;

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
      _aiPlayerConfigs = widget.preloadedAiPlayerConfigs ??
          AiPlayerConfig.generateForGame(
            count: widget.totalPlayers - 1,
            seed: DateTime.now().millisecondsSinceEpoch,
          );
      final aiNameMap = {
        for (final c in _aiPlayerConfigs) c.playerId: c.name,
      };

      final seeded = OfflineGameState.buildWithDeck(
        totalPlayers: widget.totalPlayers,
        aiNames: aiNameMap,
        localDisplayName: ref.read(displayNameForGameProvider),
        localAvatarUrl:
            ref.read(userProfileProvider).valueOrNull?.avatarUrl,
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
      state = state.copyWith(
        preTurnCentreSuit: state.discardTopCard?.effectiveSuit,
      );
      state = initializeFirstTurnClearability(state, isBustMode: false);
      final openingLc = applyOpeningSeatLastCardsSeedIfNeeded(
        state: state,
        isBustMode: false,
      );
      if (openingLc.applied) {
        state = openingLc.state;
        _pendingOpeningLastCardsAnnouncement = true;
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
      if (_pendingOpeningLastCardsAnnouncement) {
        _pendingOpeningLastCardsAnnouncement = false;
        final opener = _offlineState.playerById(_offlineState.currentPlayerId);
        if (opener != null &&
            _offlineState.lastCardsDeclaredBy.contains(opener.id)) {
          _announceLastCardsDeclaration(
            playerId: opener.id,
            playerName: opener.displayName,
            pushMoveLog: true,
          );
        }
      }
      if (hasDebugState || widget.debugSkipDealAnimation) {
        _startTimer();
        if (_offlineState.currentPlayerId != OfflineGameState.localId) {
          _scheduleAiTurn(_offlineState.currentPlayerId);
        }
        return;
      }
      _startDealAnimation();
    });
    _gameStopwatch
      ..reset()
      ..start();
    AnalyticsService.instance.logGameStarted(
      mode: 'offline',
      playerCount: widget.totalPlayers,
    );
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

    final dealCount = _offlineState.players.first.hand.length;
    for (int i = 0; i < dealCount; i++) {
      for (var pi = 0; pi < orderedPlayers.length; pi++) {
        final p = orderedPlayers[pi];
        if (!mounted) return;

        game_audio.AudioService.instance.playDealCardSoundForPlayer(pi);
        final overlay = _overlayKey.currentState;
        if (overlay != null) {
          // Fire the animation but only stagger by 100 ms — cards overlap
          // in flight for a natural fan-deal feel instead of sequential waits.
          unawaited(overlay.animateCardDeal(p.id));
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }

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

    // Use the canonical _isOfflineSession (set once in _initNewGame) instead
    // of re-checking gameStateProvider here — re-deriving mode mid-flight
    // from a live, asynchronously-updated provider is what caused this
    // widget to disagree with itself about which mode it was in.
    final isOnlineMode = !_isOfflineSession;
    final realDrawCount = isOnlineMode
        ? (ref.read(gameStateProvider)?.drawPileCount ?? _drawPile.length)
        : _drawPile.length;

    setState(() {
      _isDealing = false;
      // Snap to real remaining pile size after the visual countdown completes.
      _offlineState = _offlineState.copyWith(drawPileCount: realDrawCount);
    });

    // In online mode the server drives turn advancement — skip local AI
    // scheduling and timer start (the online turn-timer listener handles it).
    if (isOnlineMode) return;

    _startTimer();
    if (_offlineState.currentPlayerId != OfflineGameState.localId) {
      _scheduleAiTurn(_offlineState.currentPlayerId);
    }
  }

  @override
  void dispose() {
    // Drop online notifier state so the next matchmaking / lobby flow does not
    // inherit ended-game snapshots or session flags (Leave dialog also clears).
    if (!_isOfflineSession) {
      _gameNotifierToClearOnDispose?.clearOnlineState();
    }
    // Disconnect from online game so we don't receive stale state_snapshot
    // events when opening LobbyScreen for a private game.
    // Cannot use ref in dispose — use cached value from build.
    _wsClientToDisconnectOnDispose?.disconnect();
    _timerWarningSub?.cancel();
    _onlineCardPlaysSub?.cancel();
    _onlineCardDrawsSub?.cancel();
    _onlineInvalidPlayPenaltySub?.cancel();
    _onlineErrorsSub?.cancel();
    _onlineTurnTimeoutSub?.cancel();
    _onlineReshuffleSub?.cancel();
    _onlineQuickChatSub?.cancel();
    _onlineTurnChangedSub?.cancel();
    _lastCardsBluffSub?.cancel();
    _lastCardsPressedSub?.cancel();
    _gameMomentSub?.cancel();
    _quickChatCooldownTimer?.cancel();
    _skipHighlightClearTimer?.cancel();
    _stackBlockBannerClearTimer?.cancel();
    _engineTimer.dispose();
    _reshuffleNotifier.dispose();
    _handShakeNotifier.dispose();
    clearSuitInference(_offlineState.sessionId);
    unawaited(game_audio.AudioService.instance.stopAll());
    super.dispose();
  }

  Future<void> _animateLocalCardToDiscard(
    CardModel card, {
    bool lastCardFromHand = false,
  }) async {
    final flight = _playFlightKey.currentState;
    final localZoneId = ref.read(gameStateProvider)?.localPlayer?.id ??
        OfflineGameState.localId;
    final origin = _playerZoneKeys[localZoneId];
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

  Future<void> _animateOpponentCardToDiscard(
      String playerId, CardModel card) async {
    final flight = _playFlightKey.currentState;
    final origin = _playerZoneKeys[playerId];
    if (flight != null &&
        origin?.currentContext != null &&
        _discardPileKey.currentContext != null) {
      try {
        await flight
            .flyCard(
              originKey: origin,
              targetKey: _discardPileKey,
              card: card,
              faceUp: true,
            )
            .timeout(const Duration(milliseconds: 1200));
      } on TimeoutException {
        // Fail-open for tournament pacing: never block turn progression on a
        // flight animation that did not complete.
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _fireMultiPlayCelebrationIfNeeded(int cardsPlayedThisTurn) {
    if (cardsPlayedThisTurn < kMultiPlayCelebrationMinCards) return;
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final tier = multiPlayCelebrationTierIndex(cardsPlayedThisTurn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (tier) {
        case 0:
          HapticFeedback.lightImpact();
        case 1:
          HapticFeedback.mediumImpact();
        default:
          HapticFeedback.heavyImpact();
      }
      const comboSounds = [
        GameSound.comboNice,
        GameSound.comboStack,
        GameSound.comboLegendary,
      ];
      unawaited(game_audio.AudioService.instance.playSound(comboSounds[tier]));
      setState(() {
        _multiPlayCelebrationTrigger++;
        _multiPlayCelebrationTier = tier;
        _multiPlayCelebrationCardCount = cardsPlayedThisTurn;
      });
      AnalyticsService.instance.logComboPlayed(
        cardCount: cardsPlayedThisTurn,
        tier: tier,
      );
    });
  }

  /// Tracks the local player's own combo cards for the longest-combo
  /// leaderboard and submits a new record when one is set.
  ///
  /// [cardsPlayedThisTurn] is the authoritative running count from
  /// [GameState]; when it's no bigger than [justPlayed] this is the first
  /// play of a fresh turn, so the accumulator restarts rather than appends —
  /// self-healing without needing to hook every turn-reset site.
  ///
  /// Only ever called for the signed-in/local player — AI and remote
  /// opponents' combos still fire the celebration, but never write a record
  /// under someone else's name.
  void _trackLocalComboForLeaderboard({
    required String playerId,
    required List<CardModel> justPlayed,
    required int cardsPlayedThisTurn,
  }) {
    if (!_isLocalMomentPlayer(playerId)) return;

    _localComboCardsThisTurn = cardsPlayedThisTurn <= justPlayed.length
        ? List.of(justPlayed)
        : [..._localComboCardsThisTurn, ...justPlayed];

    if (cardsPlayedThisTurn < kMultiPlayCelebrationMinCards) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? OfflineGameState.localId;
    final displayName = _isOfflineSession
        ? (_offlineState.playerById(playerId)?.displayName ?? 'You')
        : (ref.read(gameStateProvider)?.playerById(playerId)?.displayName ?? 'You');

    unawaited(
      ComboLeaderboardWriter.instance.recordComboIfBest(
        uid: uid,
        displayName: displayName,
        comboCount: cardsPlayedThisTurn,
        cards: List.of(_localComboCardsThisTurn),
      ),
    );
  }

  Future<void> _animateDrawFlightsToPlayer(String playerId, int count) async {
    final flight = _playFlightKey.currentState;
    final n = math.min(count, 4);
    for (var i = 0; i < n; i++) {
      if (flight != null &&
          _drawPileKey.currentContext != null &&
          _playerZoneKeys[playerId]?.currentContext != null) {
        try {
          await flight
              .flyDrawToPlayer(
                drawPileKey: _drawPileKey,
                playerKey: _playerZoneKeys[playerId],
              )
              .timeout(const Duration(milliseconds: 900));
        } on TimeoutException {
          // Keep gameplay moving even if one draw flight stalls.
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
    }
  }

  /// Queues one draw-pile → zone flight after any in-flight draws for [playerId].
  void _enqueueOnlineDrawFlight(String playerId) {
    final prev = _onlineDrawFlightChains[playerId] ?? Future.value();
    _onlineDrawFlightChains[playerId] = prev.then((_) async {
      if (!mounted) return;
      await _animateDrawFlightsToPlayer(playerId, 1);
    }).catchError((_) {});
  }

  /// Opponent (or non-local) plays: staggered flights matching offline AI pacing.
  Future<void> _runOnlineOpponentPlayFlights(CardPlayedEvent e) async {
    for (var i = 0; i < e.cards.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: _randomAiDelayMs(280, 500)));
        if (!mounted) return;
      }
      await _animateOpponentCardToDiscard(e.playerId, e.cards[i]);
      if (!mounted) return;
    }
  }

  void _maybePulseTurnEdge(GameState gameState) {
    final cur = gameState.currentPlayerId;
    if (gameState.phase != GamePhase.playing) {
      _prevTurnPlayerIdForEdge = cur;
      return;
    }
    final localId = gameState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull
        ?.id;
    final shouldPulse = localId != null &&
        _prevTurnPlayerIdForEdge != null &&
        cur == localId &&
        _prevTurnPlayerIdForEdge != localId;
    _prevTurnPlayerIdForEdge = cur;
    if (shouldPulse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !MediaQuery.disableAnimationsOf(context)) {
          setState(() => _turnPulseTrigger++);
        }
      });
    }
  }

  void _onBackPressed() {
    final isOfflineMode = _isOfflineSession;
    final isRanked = ref.read(isRankedGameProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Leave game?', style: TextStyle(color: Colors.white)),
        content: Text(
          isOfflineMode
              ? 'You will return to the menu and this match will end.\n\n'
                  'Are you sure you want to leave?'
              : 'You will be disconnected and the game will continue without you.'
                  '${isRanked ? '\n\nIn ranked mode, abandoning a match counts as a loss with a larger MMR penalty than a normal defeat (-35).' : ''}'
                  '\n\nAre you sure you want to leave?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              unawaited(game_audio.AudioService.instance.stopAll());
              if (!isOfflineMode) {
                ref.read(gameNotifierProvider.notifier).clearOnlineState();
                ref.read(wsClientProvider).disconnect();
              }
              Navigator.of(context).pop(); // dismiss dialog
              final leaveResult = widget.isTournamentMode
                  ? TournamentRoundGameResult.abandoned
                  : null;
              Navigator.of(context).pop(leaveResult); // leave table
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    AnalyticsService.instance.logSettingsOpened();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProviderScope(
        child: SettingsModal(),
      ),
    );
  }

  /// Must match the turn bar denominator ([turnTimerTotalSeconds]) and timer engine.
  int _turnTimerBudgetSeconds() {
    final gs = ref.read(gameStateProvider);
    final fromState =
        gs?.isHardcore == true || (gs == null && _offlineState.isHardcore);
    final fromSession = ref.read(gameNotifierProvider).isHardcoreSession;
    return (fromState || fromSession)
        ? 30
        : GameTurnTimer.defaultDurationSeconds;
  }

  /// Starts (or restarts) the local turn timer. [resumeFromSeconds] continues a
  /// paused turn without granting extra time (e.g. Ace suit sheet dismissed).
  void _startTimer({
    bool playTurnSound = true,
    int? resumeFromSeconds,
  }) {
    _timerWarningPlayed = resumeFromSeconds != null && resumeFromSeconds < 10;
    _lastTimerTickSeconds = null;
    _timerWarningSub?.cancel();
    if (_isOfflineSession &&
        _offlineState.currentPlayerId == OfflineGameState.localId) {
      _offlineApplyLastCardsBluffPenaltyIfNeeded(OfflineGameState.localId);
    }
    if (playTurnSound) {
      game_audio.AudioService.instance.playSound(GameSound.turnStart);
    }
    final budget = _turnTimerBudgetSeconds();
    var secs =
        resumeFromSeconds != null ? resumeFromSeconds.clamp(0, budget) : budget;
    if (secs <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_isOfflineSession) return;
        if (_offlineState.currentPlayerId == OfflineGameState.localId &&
            !_aiThinking) {
          game_audio.AudioService.instance.playSound(GameSound.timerExpired);
          _forcedTimeoutDrawAndEnd();
        }
      });
      return;
    }
    // Start the timer BEFORE subscribing so Stream.multi delivers a fresh countdown.
    _engineTimer.start(
      () {
        if (!mounted) return;
        // Online mode: server handles timeout authoritatively. Cancel local timer;
        // server's turn_timeout drives behavior.
        if (!_isOfflineSession) {
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
              queenSuitLock: null,
              preTurnCentreSuit: _offlineState.discardTopCard?.effectiveSuit,
            );
          });
          if (nextId != OfflineGameState.localId) {
            _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
          }
          return;
        }
        if (_offlineState.currentPlayerId == OfflineGameState.localId &&
            !_aiThinking) {
          // Timeout rule: draw penalty chain (or 1 card), end the turn, pass play.
          game_audio.AudioService.instance.playSound(GameSound.timerExpired);
          _forcedTimeoutDrawAndEnd();
        }
      },
      durationSeconds: secs,
    );
    // Subscribe AFTER start() so the synchronous initial value matches [secs].
    _timerWarningSub = _engineTimer.timeRemainingStream.listen((secondsLeft) {
      final prevTick = _lastTimerTickSeconds;
      _lastTimerTickSeconds = secondsLeft;
      if (prevTick != null && secondsLeft < prevTick && secondsLeft > 0) {
        game_audio.AudioService.instance.playSound(GameSound.timerTick);
      }
      if (!_timerWarningPlayed && secondsLeft > 0 && secondsLeft <= 10) {
        _timerWarningPlayed = true;
        game_audio.AudioService.instance.playSound(GameSound.timerWarning);
      }
    });
  }

  void _forcedTimeoutDrawAndEnd() {
    if (_aiThinking) return;
    if (_localActionInProgress) return;

    final count = _offlineState.activePenaltyCount > 0
        ? _offlineState.activePenaltyCount
        : 1;
    _showError('Timeout! Drew $count card(s) as penalty.');

    var newState = applyDraw(
      state: _offlineState,
      playerId: OfflineGameState.localId,
      count: count,
      cardFactory: _makeCards,
    );
    if (mounted) {
      _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
    }

    // Play draw sound for timeout penalty.
    game_audio.AudioService.instance.playSound(GameSound.cardDraw);

    final afterDraw = newState.copyWith(drawPileCount: _drawPile.length);

    final localAfter = afterDraw.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;

    setState(() {
      _offlineState = afterDraw;
      _selectedCardId = null;
      if (localAfter != null) _syncHandOrder(localAfter.hand);
      _pushMoveLog(MoveLogEntry.timeoutDraw(
        playerId: OfflineGameState.localId,
        playerName:
            _offlineState.playerById(OfflineGameState.localId)?.displayName ??
                OfflineGameState.localId,
        drawCount: count,
      ));
    });

    // Match server [_handleDrawCard]: win / undeclared Last Cards before turn advance.
    if (_checkWin(OfflineGameState.localId, afterDraw)) {
      return;
    }

    final nextId = nextPlayerId(state: afterDraw);
    final resolvedNextId = _resolveTournamentNextPlayerId(afterDraw, nextId);
    final advanced = advanceTurn(afterDraw, nextId: resolvedNextId).copyWith(
      drawPileCount: _drawPile.length,
    );

    setState(() {
      _offlineState = advanced;
    });

    _engineTimer.cancel();
    if (resolvedNextId != OfflineGameState.localId) {
      _scheduleAiTurn(resolvedNextId, simulate: _tournamentSimulatingRest);
    } else {
      _startTimer();
    }
  }

  Future<void> _endTurn() async {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    if (_offlineState.currentPlayerId != OfflineGameState.localId) return;

    _engineTimer.cancel();
    final resumeTurnSeconds = _engineTimer.secondsRemaining;
    setState(() => _selectedCardId = null);

    int pauseSecondsBudget() => _turnTimerBudgetSeconds();

    int remainingAfterUiPause(int pauseSeconds) =>
        (resumeTurnSeconds - pauseSeconds).clamp(0, pauseSecondsBudget());

    var uiPauseSeconds = 0;
    Suit? chosenAceSuit;
    // Rule 1: Ace played alone triggers the suit selector at End Turn
    if (_offlineState.discardTopCard?.effectiveRank == Rank.ace &&
        _offlineState.cardsPlayedThisTurn == 1 &&
        _offlineState.suitLock == null &&
        mounted) {
      final sheetStopwatch = Stopwatch()..start();
      chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const AceSuitPickerSheet(),
      );
      sheetStopwatch.stop();
      // Count any partial second toward the pause so the sheet can't stall for free.
      uiPauseSeconds = (sheetStopwatch.elapsedMilliseconds + 999) ~/ 1000;
      if (!mounted) return;

      if (chosenAceSuit == null) {
        _startTimer(
          playTurnSound: false,
          resumeFromSeconds: remainingAfterUiPause(uiPauseSeconds),
        );
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

    final err = validateEndTurn(_offlineState);
    if (err != null) {
      _showError(err);
      _startTimer(
        playTurnSound: false,
        resumeFromSeconds: remainingAfterUiPause(uiPauseSeconds),
      );
      return;
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
        queenSuitLock: null,
        preTurnCentreSuit: _offlineState.discardTopCard?.effectiveSuit,
      );
    });

    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
    } else {
      _startTimer();
    }
  }

  /// Online: match offline — Ace suit picker runs on End Turn, then [declareSuit]
  /// before [endTurn] (server already accepted the Ace play without [declaredSuit]).
  Future<void> _onlineEndTurn() async {
    final gameState = ref.read(gameStateProvider);
    if (gameState == null || !mounted) return;

    if (gameState.discardTopCard?.effectiveRank == Rank.ace &&
        gameState.cardsPlayedThisTurn == 1 &&
        gameState.suitLock == null) {
      final chosenAceSuit = await showModalBottomSheet<Suit>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const AceSuitPickerSheet(),
      );
      if (!mounted) return;
      if (chosenAceSuit == null) return;
      ref.read(gameNotifierProvider.notifier).declareSuit(chosenAceSuit.name);
      await _waitForOnlineSuitLock();
      if (!mounted) return;
    }

    final err = validateEndTurn(ref.read(gameStateProvider) ?? gameState);
    if (err != null) {
      _showError(err);
      return;
    }
    ref.read(gameNotifierProvider.notifier).endTurn();
  }

  Future<void> _waitForOnlineSuitLock() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = ref.read(gameStateProvider);
      if (s?.suitLock != null) return;
    }
  }

  /// Pops [n] cards from the real draw pile and syncs [drawPileCount].
  ///
  /// Call [_reshuffleCentrePileIntoDrawPile] after each [applyDraw] /
  /// [applyInvalidPlayPenalty] / [aiTakeTurn] that uses this factory — not
  /// inside the factory — so [setState] does not run during engine callbacks.
  List<CardModel> _makeCards(int n) {
    final count = math.min(n, _drawPile.length);
    final drawn = _drawPile.sublist(0, count);
    _drawPile.removeRange(0, count);
    _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
    return drawn;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(gameStateProvider);
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        WsConnectionState.disconnected;

    // Rare race guard: widget.isOnline but the first snapshot hasn't landed
    // in gameStateProvider yet (see _initNewGame). As soon as it does, this
    // watch triggers a rebuild, we notice it here, and kick off the real
    // init on the next frame — rather than ever guessing a mode and running
    // local offline logic while actually online.
    if (_awaitingFirstOnlineSnapshot) {
      if (liveState != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(_initNewGame);
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Cache for dispose — ref is invalid during dispose. Online sessions must
    // always disconnect/clear even if the first build ran before a snapshot.
    if (!_isOfflineSession) {
      _wsClientToDisconnectOnDispose = ref.read(wsClientProvider);
      _gameNotifierToClearOnDispose = ref.read(gameNotifierProvider.notifier);
    }

    final isOfflineMode = _isOfflineSession;
    final socketDisconnectedPlayerIds = isOfflineMode
        ? const <String>{}
        : ref.watch(gameNotifierProvider).socketDisconnectedPlayerIds;
    final gameState = liveState ?? _offlineState;
    final turnTimerTotalSeconds = _turnTimerBudgetSeconds();
    final isMyTurn = isOfflineMode
        ? (_offlineState.currentPlayerId == OfflineGameState.localId &&
            !_aiThinking &&
            !_tournamentFinishedPlayerIds.contains(OfflineGameState.localId))
        : ref.watch(isLocalTurnProvider);
    final penaltyCount = isOfflineMode
        ? _offlineState.activePenaltyCount
        : ref.watch(penaltyCountProvider);

    _maybePulseTurnEdge(gameState);

    final viewerPlayerId = gameState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull
        ?.id;
    // Online state reorders players (local at index 0); nextPlayerId walks by index — wrong for 3+.
    // Tournament: resolve past finished players so "Next:" matches actual advance.
    String? nextTurnLabel;
    if (isOfflineMode &&
        gameState.phase == GamePhase.playing &&
        viewerPlayerId != null &&
        viewerPlayerId.isNotEmpty) {
      final rawNextId = nextPlayerId(state: gameState);
      final resolvedNextId =
          _resolveTournamentNextPlayerId(gameState, rawNextId);
      String label(String id) {
        if (id == viewerPlayerId) {
          return gameState.playerById(id)?.displayName ?? 'You';
        }
        return gameState.playerById(id)?.displayName ?? id;
      }

      nextTurnLabel = resolvedNextId == gameState.currentPlayerId
          ? '${label(resolvedNextId)} again'
          : label(resolvedNextId);
    }

    final localPlayerForLc = gameState.players
        .where((p) => p.tablePosition == TablePosition.bottom)
        .firstOrNull;
    final localPidLc = localPlayerForLc?.id;
    final localHandSize = localPlayerForLc?.hand.length ?? 0;
    final alreadyDeclaredLastCards = localPidLc != null &&
        gameState.lastCardsDeclaredBy.contains(localPidLc);

    // In online mode, start turn timer when it becomes our turn (e.g. after opponent ends)
    ref.listen(isLocalTurnProvider, (prev, next) {
      if (_isOfflineSession || !mounted) return;
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
      if (next == null ||
          next.phase != GamePhase.ended ||
          _onlineWinDialogShown ||
          _spectating ||
          !mounted) {
        return;
      }
      // winnerId may be null (not yet set) or empty (player disconnected).
      final hasWinner = next.winnerId != null && next.winnerId!.isNotEmpty;
      final winner = hasWinner ? next.playerById(next.winnerId!) : null;
      setState(() => _onlineWinDialogShown = true);
      final navigator = Navigator.of(context);

      // Online Bust: local leaderboard mirror for instant UI. Firestore
      // `leaderboard_bust_online` is written only by the game server.
      if (!_bustLeaderboardRecorded &&
          !widget.isTournamentMode &&
          ref.read(tournamentSessionProvider).subMode == GameSubMode.bust &&
          ref.read(tournamentSessionProvider).format == null) {
        final localPlayerId = next.localPlayer?.id;
        final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
        if (firebaseUid != null && localPlayerId != null) {
          _bustLeaderboardRecorded = true;
          final localWon = hasWinner && next.winnerId == localPlayerId;
          final displayName = next.localPlayer?.displayName ?? 'You';

          unawaited(
            LeaderboardStatsWriter.instance.recordModeResult(
              collectionName: 'leaderboard_bust_online',
              uid: firebaseUid,
              displayName: displayName,
              deltaWins: localWon ? 1 : 0,
              deltaLosses: localWon ? 0 : 1,
              deltaGamesPlayed: 1,
            ),
          );
        }
      }

      if (hasWinner && winner != null) {
        final isLocalWin = next.localPlayer?.id == next.winnerId;
        game_audio.AudioService.instance
            .playSound(isLocalWin ? GameSound.playerWin : GameSound.playerLose);
        // Retrieve ranked rating delta for the local player, if any.
        final localPlayerId = next.localPlayer?.id;
        final ratingChanges = ref.read(rankedRatingChangesProvider);
        final int? ratingDelta =
            (localPlayerId != null && ratingChanges != null)
                ? ratingChanges[localPlayerId]
                : null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          HapticFeedback.heavyImpact();
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _WinDialog(
              winnerName: winner.displayName,
              isLocalWin: isLocalWin,
              onPlayAgain: () {
                ref.read(gameNotifierProvider.notifier).clearOnlineState();
                ref.read(wsClientProvider).disconnect();
                navigator.pop(); // close dialog
                navigator.pop(); // leave table
              },
              isOnlineMode: true,
              ratingDelta: ratingDelta,
              onSpectate:
                  !isLocalWin && ref.read(gameNotifierProvider).isPrivateSession
                      ? () {
                          navigator.pop();
                          setState(() => _spectating = true);
                        }
                      : null,
            ),
          );
        });
      } else {
        // Game ended without a winner (all other players left).
        scheduleMicrotask(() {
          if (!mounted) return;
          final t = ref.read(themeProvider).theme;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: t.surfacePanel,
              title: Text(
                'Everyone else left',
                style: TextStyle(color: t.textPrimary),
              ),
              content: Text(
                'You are the only one still here. Returning to the menu.',
                style: TextStyle(color: t.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    ref.read(gameNotifierProvider.notifier).clearOnlineState();
                    ref.read(wsClientProvider).disconnect();
                    navigator.pop(); // close dialog
                    navigator.pop(); // leave table
                  },
                  child: Text(
                    'BACK TO MENU',
                    style: TextStyle(color: t.accentPrimary),
                  ),
                ),
              ],
            ),
          );
        });
      }
    });

    // Online tournament: sync _tournamentFinishedPlayerIds from server state,
    // play qualify/eliminate sounds, and show qualified badges (5+ players).
    ref.listen<GameState?>(gameStateProvider, (prev, next) {
      if (next == null || !widget.isTournamentMode || !mounted) return;
      // Skip when game has ended — handled by game_ended listener.
      if (next.phase == GamePhase.ended) return;

      final finishedIds = next.players
          .where((p) => canConfirmPlayerWin(state: next, playerId: p.id))
          .map((p) => p.id)
          .toList();

      if (prev == null) {
        // Initial load: sync finished list without playing sounds.
        if (finishedIds.length != _tournamentFinishedPlayerIds.length ||
            finishedIds.toSet() != _tournamentFinishedPlayerIds.toSet()) {
          setState(() {
            _tournamentFinishedPlayerIds
              ..clear()
              ..addAll(finishedIds);
            _tournamentRoundComplete =
                finishedIds.length == next.players.length;
          });
        }
        return;
      }

      final prevFinished = prev.players
          .where((p) => canConfirmPlayerWin(state: prev, playerId: p.id))
          .map((p) => p.id)
          .toSet();
      final newlyFinished =
          finishedIds.where((id) => !prevFinished.contains(id));
      if (newlyFinished.isEmpty) return;

      final finishedCallbacks = <(String playerId, int pos)>[];
      setState(() {
        for (final id in newlyFinished) {
          if (!_tournamentFinishedPlayerIds.contains(id)) {
            _tournamentFinishedPlayerIds.add(id);
            final pos = _tournamentFinishedPlayerIds.length;
            finishedCallbacks.add((id, pos));
            if (_tournamentFinishedPlayerIds.length < next.players.length) {
              game_audio.AudioService.instance
                  .playSound(GameSound.tournamentQualify);
            }
          }
        }
        if (_tournamentFinishedPlayerIds.length == next.players.length) {
          _tournamentRoundComplete = true;
          game_audio.AudioService.instance
              .playSound(GameSound.tournamentEliminate);
        }
      });
      for (final (playerId, pos) in finishedCallbacks) {
        widget.onPlayerFinished(playerId, pos);
      }
    });

    // Online: Ace suit is chosen at End Turn (see [_onlineEndTurn]), not on play.
    // [pendingSuitChoiceProvider] may still be set by the server for diagnostics.

    // Online: server requests joker declaration after local player played a Joker.
    ref.listen<bool>(pendingJokerResolutionProvider, (prev, next) {
      if (!next || !mounted) return;
      final jokerCardId = ref.read(gameNotifierProvider).pendingJokerCardId;
      if (jokerCardId == null) return;
      final gameState = ref.read(gameStateProvider);
      if (gameState == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final jokerIn = resolveJokerPlayInputs(
          state: gameState,
          discardTop: gameState.discardTopCard!,
        );
        // Raw context for [getValidJokerOptions] only — that function upgrades
        // 2p King to turn-starter internally.
        final validOptions = getValidJokerOptions(
          state: gameState,
          discardTop: gameState.discardTopCard!,
          context: jokerIn.resolvedContext,
          contextTopCard: jokerIn.anchor,
        );
        if (validOptions.isEmpty || !mounted) return;
        final chosenCard = await showModalBottomSheet<CardModel>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _JokerSelectionSheet(
            options: validOptions,
            playContext: jokerIn.effectivePlayContext,
            activeSequenceSuit: jokerIn.activeSequenceSuit,
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
          final layoutSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          final isLandscapeMobile =
              TableChromeLayout.isLandscapeMobile(layoutSize);
          final isPortraitGrid = !isLandscapeMobile;
          final mediaPadding = MediaQuery.paddingOf(context);
          final portraitSkipChipBottom = mediaPadding.bottom +
              TablePortraitGrid.handRegionHeight +
              TablePortraitGrid.actionBarHeight +
              TablePortraitGrid.skipChipGapAboveHand;
          final landscapeSkipChipBottom =
              TablePortraitGrid.landscapeSkipChipBottom(mediaPadding.bottom);
          final buttonBottom = isLandscapeMobile
              ? mediaPadding.bottom +
                  TablePortraitGrid.landscapeHandRegionHeight +
                  TablePortraitGrid.landscapeActionBarHeight +
                  AppDimensions.sm
              : mediaPadding.bottom +
                  TablePortraitGrid.handRegionHeight +
                  TablePortraitGrid.actionBarHeight +
                  AppDimensions.sm;
          final overlayQuickChatBubbles = {
            for (final b in _quickChatBubbles)
              b.playerId: (
                id: b.id,
                playerName: b.playerName,
                reactionWireIndex: b.reactionWireIndex,
                isLocal: b.isLocal
              ),
          };
          final overlayUseRail = gameState.players.length > 4;
          final overlayHasTournamentBadges =
              _buildTournamentStatusBadges().isNotEmpty;
          final overlayIsRanked = ref.watch(isRankedGameProvider);
          final overlayOpponentRowHeight = isLandscapeMobile
              ? TablePortraitGrid.landscapeOpponentRowHeight(
                  useRail: overlayUseRail,
                  hasBadges: overlayHasTournamentBadges,
                )
              : TablePortraitGrid.opponentRowHeight(
                  useRail: overlayUseRail,
                  hasBadges: overlayHasTournamentBadges,
                );
          final kingJustPlayed =
              gameState.lastPlayedThisTurn?.effectiveRank == Rank.king;

          final stack = Stack(
            children: [
              const FeltTableBackground(),

              Positioned.fill(
                child: IgnorePointer(
                  child: _ScreenEdgePulse(
                    trigger: _turnPulseTrigger,
                    color: appTheme.accentPrimary,
                    totalDuration: const Duration(milliseconds: 800),
                    fadeInDuration: const Duration(milliseconds: 200),
                    maxOpacity: 0.22,
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: _ScreenEdgePulse(
                    trigger: _penaltyFlashTrigger,
                    color: const Color(0xFFE53935),
                    totalDuration: const Duration(milliseconds: 400),
                    fadeInDuration: const Duration(milliseconds: 100),
                    maxOpacity: 0.32,
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    if (!isOfflineMode) const PendingFriendRequestsBanner(),
                    Expanded(
                      child: _TableLayout(
                        gameState: gameState,
                        socketDisconnectedPlayerIds:
                            socketDisconnectedPlayerIds,
                        selectedCardId: _selectedCardId,
                        orderedHand: _orderedHand(
                          gameState.players
                                  .where((p) =>
                                      p.tablePosition == TablePosition.bottom)
                                  .firstOrNull
                                  ?.hand ??
                              [],
                        ).where((c) => c.id != _flyingCardId).toList(),
                        isMyTurn: isMyTurn,
                        penaltyCount: penaltyCount,
                        connState: isOfflineMode
                            ? WsConnectionState.disconnected
                            : connState,
                        canEndTurn: isOfflineMode
                            ? canEndTurnButton(_offlineState)
                            : (isMyTurn && canEndTurnButton(gameState)),
                        isDealing: _isDealing,
                        visibleCardCounts: _visibleCardCounts,
                        drawPileKey: _drawPileKey,
                        discardPileKey: _discardPileKey,
                        hudKey: _hudKey,
                        thinkingOpponentId: isOfflineMode && _aiThinking
                            ? _offlineState.currentPlayerId
                            : (!isOfflineMode &&
                                    gameState.players.any(
                                      (p) =>
                                          p.id == gameState.currentPlayerId &&
                                          p.isAi,
                                    ))
                                ? gameState.currentPlayerId
                                : null,
                        playerZoneKeys: _playerZoneKeys,
                        onCardTap: _onCardTap,
                        onDrawTap: isOfflineMode
                            ? () {
                                _offlineDrawCard(OfflineGameState.localId);
                              }
                            : _onDrawTap,
                        onHandReorder:
                            _flyingCardId != null ? null : _onHandReorder,
                        onEndTurnTap: isOfflineMode
                            ? _endTurn
                            : () {
                                unawaited(_onlineEndTurn());
                              },
                        isOffline: isOfflineMode,
                        discardPileCount: isOfflineMode
                            ? _discardPile.length
                            : _onlineDiscardCount,
                        reshuffleNotifier: _reshuffleNotifier,
                        timeRemainingStream: _engineTimer.timeRemainingStream,
                        turnTimerTotalSeconds: turnTimerTotalSeconds,
                        tournamentStatusBadges: _buildTournamentStatusBadges(),
                        finishedPlayerIds: _tournamentFinishedPlayerIds.toSet(),
                        aiConfigs: {
                          for (final c in _aiPlayerConfigs) c.playerId: c,
                        },
                        isRanked: ref.watch(isRankedGameProvider),
                        quickChatBubblesByPlayer: {
                          for (final b in _quickChatBubbles)
                            b.playerId: (
                              id: b.id,
                              playerName: b.playerName,
                              reactionWireIndex: b.reactionWireIndex,
                              isLocal: b.isLocal
                            ),
                        },
                        onRemoveQuickChatBubble: _removeQuickChatBubble,
                        nextTurnLabel: nextTurnLabel,
                        isLocalTurn: isMyTurn,
                        hasAlreadyDeclaredLastCards: alreadyDeclaredLastCards,
                        localHandSize: localHandSize,
                        handShakeTrigger: _handShakeNotifier,
                        onLastCardsTap: _onDeclareLastCards,
                        onPenaltyIncreased: _bumpPenaltyFlashForHud,
                        skipHighlightPlayerIds: _skipHighlightPlayerIds,
                        onOpponentProfileTap:
                            isOfflineMode ? null : _showOpponentProfileSheet,
                        localAvatarFilePath:
                            ref.watch(profileProvider.select((s) => s.avatarPath)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Multi-card combo celebration — above the table so the badge
              // and embers aren't hidden behind the piles ────────────────────
              Positioned.fill(
                child: IgnorePointer(
                  child: MultiCardPlayCelebrationOverlay(
                    trigger: _multiPlayCelebrationTrigger,
                    tierIndex: _multiPlayCelebrationTier,
                    cardCount: _multiPlayCelebrationCardCount,
                  ),
                ),
              ),

              // ── Portrait transient overlay (chat, direction) ─────────────
              if (isPortraitGrid)
                Positioned.fill(
                  child: _PortraitTransientOverlayLayer(
                    gameState: gameState,
                    kingJustPlayed: kingJustPlayed,
                    playerZoneKeys: _playerZoneKeys,
                    hudKey: _hudKey,
                    discardPileKey: _discardPileKey,
                    opponentRowHeight: overlayOpponentRowHeight,
                    hasRankedBadge: overlayIsRanked,
                    moveLogEntries: _moveLogEntries,
                    quickChatBubblesByPlayer: overlayQuickChatBubbles,
                    onRemoveQuickChatBubble: _removeQuickChatBubble,
                    appTheme: appTheme,
                    stackBlockBannerText: _stackBlockBannerText,
                    stackBlockBannerColor: _stackBlockBannerColor,
                  ),
                ),

              // ── Landscape transient overlay (chat, direction) ─────────────
              if (isLandscapeMobile)
                Positioned.fill(
                  child: _LandscapeTransientOverlayLayer(
                    gameState: gameState,
                    kingJustPlayed: kingJustPlayed,
                    playerZoneKeys: _playerZoneKeys,
                    hudKey: _hudKey,
                    discardPileKey: _discardPileKey,
                    opponentRowHeight: overlayOpponentRowHeight,
                    hasRankedBadge: overlayIsRanked,
                    moveLogEntries: _moveLogEntries,
                    quickChatBubblesByPlayer: overlayQuickChatBubbles,
                    onRemoveQuickChatBubble: _removeQuickChatBubble,
                    appTheme: appTheme,
                    stackBlockBannerText: _stackBlockBannerText,
                    stackBlockBannerColor: _stackBlockBannerColor,
                  ),
                ),

              // ── Tournament Skip (offline, when qualified) ───────────────────
              if (widget.isTournamentMode &&
                  _isOfflineSession &&
                  _tournamentFinishedPlayerIds
                      .contains(OfflineGameState.localId) &&
                  !_tournamentRoundComplete &&
                  gameState.phase != GamePhase.ended)
                Positioned(
                  bottom: isLandscapeMobile
                      ? landscapeSkipChipBottom
                      : portraitSkipChipBottom,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _tournamentSimulatingRest
                              ? null
                              : () {
                                  unawaited(_onTournamentSkipTapped());
                                },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tournamentSimulatingRest
                                  ? Colors.white24
                                  : AppColors.goldPrimary
                                      .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _tournamentSimulatingRest
                                    ? Colors.white38
                                    : AppColors.goldDark,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_tournamentSimulatingRest)
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.fast_forward_rounded,
                                    size: 20,
                                    color: Colors.black87,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  _tournamentSimulatingRest
                                      ? 'Simulating…'
                                      : 'Skip to result',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _tournamentSimulatingRest
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Settings + back (single-player and online) ──────────────────
              Positioned(
                bottom: buttonBottom,
                left: 0,
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
                          tooltip: isOfflineMode ? 'Exit game' : 'Leave game',
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _onBackPressed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Emoji reactions toggle and panel (bottom right, opposite back)
              if (!_isDealing && gameState.phase != GamePhase.ended)
                Positioned(
                  bottom: buttonBottom,
                  right: 0,
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
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.55,
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
                                          setState(() => _showQuickChatPanel =
                                              !_showQuickChatPanel);
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

              if (_lastCardsDeclaredBannerText != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: appTheme.surfacePanel.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: appTheme.accentPrimary.withValues(alpha: 0.95),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: appTheme.accentPrimary
                                  .withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          _lastCardsDeclaredBannerText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: appTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (_lastCardsBluffBannerText != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: appTheme.surfacePanel.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            // Bad news for the bluffer — same red as a penalty
                            // escalation, not the theme accent.
                            color: const Color(0xFFE53935).withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          _lastCardsBluffBannerText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: appTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Card flight (play / draw arcs) ─────────────────────────
              Positioned.fill(
                child: CardFlightOverlay(key: _playFlightKey),
              ),

              // ── Dealing Animation Overlay ──────────────────────────────
              Positioned.fill(
                child: DealingAnimationOverlay(
                  key: _overlayKey,
                  drawPileKey: _drawPileKey,
                  playerKeys: _playerZoneKeys,
                ),
              ),

              // ── Connection lost / reconnecting (blocks interaction) ───────
              if (!isOfflineMode)
                Positioned.fill(
                  child: ValueListenableBuilder<WsConnectionState>(
                    valueListenable: ref.read(wsClientProvider).connectionState,
                    builder: (context, connState, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable:
                            ref.read(wsClientProvider).reconnectExhausted,
                        builder: (context, exhausted, _) {
                          if (connState == WsConnectionState.connected &&
                              !exhausted) {
                            return const SizedBox.shrink();
                          }
                          final message = exhausted
                              ? "Couldn't reconnect. Check your network or leave the table."
                              : 'Reconnecting…';
                          return Material(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          );
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _onBackPressed();
            },
            child: stack,
          );
        },
      ),
    );
  }

  // ── Card tap ───────────────────────────────────────────────────────

  void _onCardTap(String cardId) {
    if (_aiThinking) return;
    final isOfflineMode = _isOfflineSession;
    if (isOfflineMode) {
      _offlinePlayCards(OfflineGameState.localId, cardId: cardId);
    } else {
      _onPlayTap(cardId: cardId);
    }
  }

  // ── Live server actions ────────────────────────────────────────────

  void _onDrawTap() {
    if (!ref.read(isLocalTurnProvider)) return;
    HapticFeedback.lightImpact();
    ref.read(gameNotifierProvider.notifier).drawCard();
    setState(() => _selectedCardId = null);
  }

  /// Online: flight from hand to discard, then [send] (play / declare_joker).
  ///
  /// Matches offline: every card animates before the action is sent; the last
  /// card uses [lastCardFromHand] for haptics only.
  Future<void> _onlineMaybeLastCardFlightThen({
    required CardModel cardToFly,
    required bool lastCardFromHand,
    required void Function() send,
  }) async {
    _onlineLastCardFlightInProgress = true;
    setState(() => _flyingCardId = cardToFly.id);
    try {
      await _animateLocalCardToDiscard(
        cardToFly,
        lastCardFromHand: lastCardFromHand,
      );
      if (!mounted) return;
      send();
    } finally {
      _onlineLastCardFlightInProgress = false;
      if (mounted) {
        setState(() => _flyingCardId = null);
      }
    }
  }

  /// Online play: Joker/Ace flows or send play. Server validates and applies
  /// penalty for invalid plays (client does not block invalid attempts).
  Future<void> _onPlayTap({required String cardId}) async {
    if (!ref.read(isLocalTurnProvider)) return;
    if (_onlineLastCardFlightInProgress) return;
    final gameState = ref.read(gameStateProvider);
    if (gameState == null) return;
    final local = gameState.localPlayer;
    if (local == null) return;
    final card = local.hand.where((c) => c.id == cardId).firstOrNull;
    if (card == null) return;
    final isLastCardFromHand = local.hand.length == 1;

    // Joker: show sheet, then send declare_joker (same flow as single-player).
    if (card.isJoker && mounted) {
      final jokerIn = resolveJokerPlayInputs(
        state: gameState,
        discardTop: gameState.discardTopCard!,
      );
      // Raw context for [getValidJokerOptions] only — that function upgrades
      // 2p King to turn-starter internally.
      final validOptions = getValidJokerOptions(
        state: gameState,
        discardTop: gameState.discardTopCard!,
        context: jokerIn.resolvedContext,
        contextTopCard: jokerIn.anchor,
      );
      if (validOptions.isEmpty) {
        _showError('No valid moves available for the Joker right now.');
        return;
      }
      setState(() => _selectedCardId = cardId);
      final chosenCard = await showModalBottomSheet<CardModel>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _JokerSelectionSheet(
          options: validOptions,
          playContext: jokerIn.effectivePlayContext,
          activeSequenceSuit: jokerIn.activeSequenceSuit,
        ),
      );
      if (!mounted) return;
      setState(() => _selectedCardId = null);
      if (chosenCard == null) return;
      final assignedJoker = card.copyWith(
        jokerDeclaredRank: chosenCard.rank,
        jokerDeclaredSuit: chosenCard.suit,
      );
      await _onlineMaybeLastCardFlightThen(
        cardToFly: assignedJoker,
        lastCardFromHand: isLastCardFromHand,
        send: () => ref.read(gameNotifierProvider.notifier).declareJoker(
              jokerCardId: cardId,
              suitName: chosenCard.suit.name,
              rankName: chosenCard.rank.name,
            ),
      );
      return;
    }

    // Ace as first card: play without declaredSuit — server sends suit_choice_required;
    // the player declares at End Turn ([_onlineEndTurn]), matching offline.

    // Normal play
    await _onlineMaybeLastCardFlightThen(
      cardToFly: card,
      lastCardFromHand: isLastCardFromHand,
      send: () {
        ref.read(gameNotifierProvider.notifier).playCards([cardId]);
        setState(() => _selectedCardId = null);
      },
    );
  }

  // ── Offline mode: play cards ───────────────────────────────────────────────

  Future<void> _offlinePlayCards(String playerId,
      {required String cardId}) async {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    if (_offlineState.currentPlayerId != playerId) return;
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(playerId)) {
      return;
    }
    _localActionInProgress = true;
    try {
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
        await _applyInvalidPlayPenalty(playerId, played);
        return;
      }

      // Intercept Joker plays (mirrors Ace popup flow — timer paused for sheet)
      if (played.length == 1 && played.first.isJoker && mounted) {
        final jokerIn = resolveJokerPlayInputs(
          state: _offlineState,
          discardTop: _offlineState.discardTopCard!,
        );

        // Raw context for [getValidJokerOptions] only — that function upgrades
        // 2p King to turn-starter internally.
        final validOptions = getValidJokerOptions(
          state: _offlineState,
          discardTop: _offlineState.discardTopCard!,
          context: jokerIn.resolvedContext,
          contextTopCard: jokerIn.anchor,
        );

        if (validOptions.isEmpty) {
          _showError('No valid moves available for the Joker right now.');
          return;
        }

        _engineTimer.cancel();
        final frozenRemaining = _engineTimer.secondsRemaining;
        final budget = _turnTimerBudgetSeconds();
        int resumeAfterPauses(int sheetSec, int animSec) =>
            (frozenRemaining - sheetSec - animSec).clamp(0, budget);

        // Show selection visual while the modal is open
        setState(() => _selectedCardId = cardId);
        final sheetStopwatch = Stopwatch()..start();
        final chosenCard = await showModalBottomSheet<CardModel>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _JokerSelectionSheet(
            options: validOptions,
            playContext: jokerIn.effectivePlayContext,
            activeSequenceSuit: jokerIn.activeSequenceSuit,
          ),
        );
        sheetStopwatch.stop();
        final sheetSec = (sheetStopwatch.elapsedMilliseconds + 999) ~/ 1000;

        if (!mounted) return;
        if (chosenCard == null) {
          setState(() => _selectedCardId = null);
          _startTimer(
            playTurnSound: false,
            resumeFromSeconds: resumeAfterPauses(sheetSec, 0),
          );
          return;
        }

        final assignedJoker = played.first.copyWith(
          jokerDeclaredRank: chosenCard.rank,
          jokerDeclaredSuit: chosenCard.suit,
        );

        final lastFromHand = local.hand.length == 1;
        final animStopwatch = Stopwatch()..start();
        setState(() => _flyingCardId = assignedJoker.id);
        await _animateLocalCardToDiscard(assignedJoker,
            lastCardFromHand: lastFromHand);
        animStopwatch.stop();
        final animSec = (animStopwatch.elapsedMilliseconds + 999) ~/ 1000;
        if (!mounted) return;
        if (!lastFromHand) {
          HapticFeedback.mediumImpact();
        }

        final previousState = _offlineState;
        clearSuitInferenceOnPlay(
          sessionId: previousState.sessionId,
          playerId: playerId,
          cards: [assignedJoker],
        );
        var newState = applyPlay(
          state: _offlineState,
          playerId: playerId,
          cards: [assignedJoker],
          declaredSuit: assignedJoker.effectiveRank == Rank.ace
              ? assignedJoker.effectiveSuit
              : null,
        );

        // Play card sounds for Joker play.
        game_audio.AudioService.instance.playSound(GameSound.cardPlace);
        game_audio.AudioService.instance.playSound(GameSound.specialJoker);

        _discardPile.add(assignedJoker);

        // Update state before _checkWin so the hand is already correct if the
        // finally block clears _flyingCardId on a win/early-return path.
        final localInNew = newState.players
            .where((p) => p.tablePosition == TablePosition.bottom)
            .firstOrNull;
        final jokerPlayerName =
            _offlineState.playerById(playerId)?.displayName ?? playerId;
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        if (localInNew != null) _syncHandOrder(localInNew.hand);

        // Win / tournament round-end may pop this route — run before any setState
        // so we never call setState after dispose (_dependents.isEmpty).
        _trackMatchPlay(playerId, [assignedJoker]);
        _trackLocalComboForLeaderboard(
          playerId: playerId,
          justPlayed: [assignedJoker],
          cardsPlayedThisTurn: newState.cardsPlayedThisTurn,
        );
        _fireMultiPlayCelebrationIfNeeded(newState.cardsPlayedThisTurn);
        if (_checkWin(playerId, newState)) return;

        setState(() {
          _selectedCardId = null;
          _flyingCardId = null;
          _recordPlayMove(
            playerId: playerId,
            playerName: jokerPlayerName,
            playedCards: [assignedJoker],
            beforeState: previousState,
            afterState: newState,
          );
        });

        _reshuffleCentrePileIntoDrawPile();

        _announcePenaltyChainAction(
          beforeState: previousState,
          afterState: newState,
          playedCard: assignedJoker,
          playerId: playerId,
          playerName: previousState.playerById(playerId)?.displayName,
        );

        // Allow the player to continue their turn (stack more cards if they want).
        if (newState.currentPlayerId == playerId) {
          _startTimer(
            playTurnSound: false,
            resumeFromSeconds: resumeAfterPauses(sheetSec, animSec),
          );
        }
        return;
      }

      final lastFromHand = local.hand.length == played.length;
      setState(() => _flyingCardId = played.first.id);
      await _animateLocalCardToDiscard(played.first,
          lastCardFromHand: lastFromHand);
      if (!mounted) return;
      if (!lastFromHand) {
        HapticFeedback.mediumImpact();
      }

      // Apply play + special effects
      final previousState = _offlineState;
      clearSuitInferenceOnPlay(
        sessionId: previousState.sessionId,
        playerId: playerId,
        cards: played,
      );
      var newState =
          applyPlay(state: _offlineState, playerId: playerId, cards: played);
      _announcePenaltyChainAction(
        beforeState: previousState,
        afterState: newState,
        playedCard: newState.discardTopCard!,
        playerId: playerId,
        playerName: previousState.playerById(playerId)?.displayName,
      );
      _engineTimer.cancel();
      final resumeMidTurn = _engineTimer.secondsRemaining;

      // Play card sounds: every card uses card_place.wav; special cards also get their effect sound.
      for (final c in played) {
        game_audio.AudioService.instance.playSound(GameSound.cardPlace);
        final s = soundForCard(c);
        if (s != null) game_audio.AudioService.instance.playSound(s);
      }

      // Direction reversed by King
      if (newState.direction != previousState.direction) {
        game_audio.AudioService.instance.playSound(GameSound.directionReversed);
      }
      // Skip accumulated by Eight
      if (newState.activeSkipCount > previousState.activeSkipCount) {
        game_audio.AudioService.instance.playSound(GameSound.skipApplied);
        _flashSkipHighlight(skippedPlayerIdsForSkipState(newState));
      }

      _discardPile.addAll(played);

      // Update state before _checkWin so the hand is already correct if the
      // finally block clears _flyingCardId on a win/early-return path.
      final localInNew = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;
      final playPlayerName =
          _offlineState.playerById(playerId)?.displayName ?? playerId;
      _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
      if (localInNew != null) _syncHandOrder(localInNew.hand);

      // Win / tournament round-end may pop this route — run before setState.
      _trackMatchPlay(playerId, played);
      _trackLocalComboForLeaderboard(
        playerId: playerId,
        justPlayed: played,
        cardsPlayedThisTurn: newState.cardsPlayedThisTurn,
      );
      _fireMultiPlayCelebrationIfNeeded(newState.cardsPlayedThisTurn);
      if (_checkWin(playerId, newState)) return;

      setState(() {
        _selectedCardId = null;
        _flyingCardId = null;
        _recordPlayMove(
          playerId: playerId,
          playerName: playPlayerName,
          playedCards: played,
          beforeState: previousState,
          afterState: newState,
        );
      });

      _reshuffleCentrePileIntoDrawPile();

      // Auto-advance if this play guarantees we get another turn immediately and
      // there are no unresolved obligations (like covering a Queen).
      // This happens when playing a Skip (8) or a King in a 2-player game.
      // NOTE: We inline the turn-advance logic here instead of calling _endTurn()
      // because _localActionInProgress is still true (we're inside the try block).
      // _endTurn() would be blocked by the guard. The auto-advance case is simpler
      // anyway: no Ace suit picker needed (the card is a Skip/King).
      var nextId = nextPlayerId(state: newState);
      nextId = _resolveTournamentNextPlayerId(newState, nextId);

      if (nextId == playerId && newState.queenSuitLock == null) {
        setState(() {
          _finalizeTurnLogForPlayer(playerId);
          _offlineState = _offlineState.copyWith(
            currentPlayerId: nextId,
            actionsThisTurn: 0,
            cardsPlayedThisTurn: 0,
            lastPlayedThisTurn: null,
            activeSkipCount: 0,
            queenSuitLock: null,
            preTurnCentreSuit: _offlineState.discardTopCard?.effectiveSuit,
          );
        });

        if (nextId != OfflineGameState.localId) {
          _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
        } else {
          _startTimer();
        }
      } else if (newState.currentPlayerId == playerId) {
        // Still our turn (e.g. Queen suit lock, or any extra play this turn) —
        // resume the same budget (flight ran while the timer ticked; cancel
        // snapshot is post-animation).
        _startTimer(
          playTurnSound: false,
          resumeFromSeconds: resumeMidTurn,
        );
      }
    } finally {
      _localActionInProgress = false;
      if (mounted && _flyingCardId != null) {
        setState(() => _flyingCardId = null);
      }
    }
  }

  // ── Offline mode: invalid play penalty sequence ────────────────────────────

  /// Fired when the local player attempts to play a card that fails validation.
  ///
  /// Penalty sequence (strictly in this order):
  ///   1. Return card to hand   — already satisfied: [applyPlay] was never called.
  ///   2. Draw 2 cards, or the full stacked pick-up count if one is active.
  ///   3. End the player's turn immediately.
  Future<void> _applyInvalidPlayPenalty(
      String playerId, List<CardModel> attemptedCards) async {
    final penaltyDrawCount = _offlineState.activePenaltyCount > 0
        ? _offlineState.activePenaltyCount
        : 2;
    _showError(
      _offlineState.activePenaltyCount == 0
          ? 'Invalid play! Drawing 2 cards as penalty.'
          : 'Invalid play! Drawing $penaltyDrawCount cards (stacked pick-up).',
    );

    try {
      if (playerId == OfflineGameState.localId) {
        _handShakeNotifier.value++;
        _momentPenaltyHit(playerId: playerId, cardsDrawn: penaltyDrawCount);
        HapticFeedback.lightImpact();
        await _animateDrawFlightsToPlayer(playerId, penaltyDrawCount);
        if (!mounted) return;
      }

      // Step 2: apply shared invalid-play penalty (matches online server).
      var newState = applyInvalidPlayPenalty(
        state: _offlineState,
        playerId: playerId,
        cardFactory: _makeCards,
      );
      if (mounted) {
        _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
      }

      // Play draw sound for penalty.
      game_audio.AudioService.instance.playSound(GameSound.cardDraw);
      game_audio.AudioService.instance.playSound(GameSound.penaltyDraw);

      // Step 3: end the turn.
      newState = advanceTurn(newState);

      final localAfter = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;

      setState(() {
        _offlineState = newState.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        if (localAfter != null) _syncHandOrder(localAfter.hand);
      });

      _engineTimer.cancel();
      if (newState.currentPlayerId != OfflineGameState.localId) {
        _scheduleAiTurn(newState.currentPlayerId,
            simulate: _tournamentSimulatingRest);
      } else {
        _startTimer();
      }
    } finally {
      _localActionInProgress = false;
      if (mounted && _flyingCardId != null) {
        setState(() => _flyingCardId = null);
      }
    }
  }

  // ── Offline mode: draw card ────────────────────────────────────────────────

  Future<void> _offlineDrawCard(String playerId) async {
    if (_aiThinking) return;
    if (_localActionInProgress) return;
    if (_offlineState.currentPlayerId != playerId) return;
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(playerId)) {
      final nextId = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: playerId,
      );
      if (nextId != OfflineGameState.localId) {
        _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
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

    _localActionInProgress = true;
    try {
      final isPenaltyDraw = _offlineState.activePenaltyCount > 0;
      final drawCount = isPenaltyDraw ? _offlineState.activePenaltyCount : 1;

      if (playerId == OfflineGameState.localId) {
        HapticFeedback.lightImpact();
        await _animateDrawFlightsToPlayer(playerId, drawCount);
        if (!mounted) return;
      }

      recordDrawSuitInference(
        state: _offlineState,
        drawingPlayerId: playerId,
      );

      var newState = applyDraw(
        state: _offlineState,
        playerId: playerId,
        count: drawCount,
        cardFactory: _makeCards,
      );
      if (mounted) {
        _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
      }

      // Play draw sounds (moved from game_engine to UI layer for server compat).
      game_audio.AudioService.instance.playSound(GameSound.cardDraw);
      if (isPenaltyDraw) {
        game_audio.AudioService.instance.playSound(GameSound.penaltyDraw);
      }

      final localAfterDraw = newState.players
          .where((p) => p.tablePosition == TablePosition.bottom)
          .firstOrNull;

      final playerName =
          _offlineState.playerById(playerId)?.displayName ?? playerId;
      _finalizeDrawAndAdvance(
        playerId: playerId,
        playerName: playerName,
        drawCount: drawCount,
        newState: newState,
        localAfterDraw: localAfterDraw,
      );
    } finally {
      _localActionInProgress = false;
    }
  }

  /// Shared helper for draw-and-advance logic used by _offlineDrawCard.
  void _finalizeDrawAndAdvance({
    required String playerId,
    required String playerName,
    required int drawCount,
    required GameState newState,
    required PlayerModel? localAfterDraw,
  }) {
    final afterDraw = newState.copyWith(drawPileCount: _drawPile.length);

    _trackMatchDraw(playerId, drawCount);
    if (drawCount > 1) {
      _momentPenaltyHit(playerId: playerId, cardsDrawn: drawCount);
    }
    setState(() {
      _offlineState = afterDraw;
      _selectedCardId = null;
      if (localAfterDraw != null) _syncHandOrder(localAfterDraw.hand);
      _pushMoveLog(MoveLogEntry.draw(
        playerId: playerId,
        playerName: playerName,
        drawCount: drawCount,
      ));
    });

    // Match server [_handleDrawCard]: win / undeclared Last Cards before turn advance.
    if (_checkWin(playerId, afterDraw)) {
      return;
    }

    var nextId = nextPlayerId(state: afterDraw);
    nextId = _resolveTournamentNextPlayerId(afterDraw, nextId);
    final advanced = advanceTurn(afterDraw, nextId: nextId).copyWith(
      drawPileCount: _drawPile.length,
    );

    setState(() {
      _offlineState = advanced;
    });

    _engineTimer.cancel();
    if (nextId != OfflineGameState.localId) {
      _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
    } else {
      _startTimer();
    }
  }

  // ── AI turn ────────────────────────────────────────────────────────

  int _randomAiDelayMs(int min, int max) {
    if (max <= min) return min;
    return min + _aiDelayRng.nextInt((max - min) + 1);
  }

  /// Extra delay before an offline AI move so the human can tap Last Cards on
  /// the opponent's turn. Hard difficulty shortens base "think" time a lot; this
  /// keeps declaration feasible without changing shared game rules.
  int _offlineLocalLastCardsReactionGraceMs({required String aiId}) {
    if (aiId == OfflineGameState.localId) return 0;
    final localId = OfflineGameState.localId;
    if (_offlineState.lastCardsDeclaredBy.contains(localId)) return 0;
    final local = _offlineState.playerById(localId);
    if (local == null) return 0;
    if (local.hand.length > lastCardsMaxHandSize &&
        !canClearHandInOneTurn(state: _offlineState, playerId: localId)) {
      return 0;
    }
    return _randomAiDelayMs(700, 1300);
  }

  /// Whether each AI-played card can be applied one-at-a-time (same end state).
  bool _offlineAiPlayedCardsReplaySequentially(
    GameState start,
    String aiId,
    List<CardModel> played,
    Suit? aceDeclaredSuit,
  ) {
    if (played.isEmpty) return true;
    var s = start;
    for (final c in played) {
      final top = s.discardTopCard;
      if (top == null) return false;
      if (validatePlay(cards: [c], discardTop: top, state: s) != null) {
        return false;
      }
      final decl = s.actionsThisTurn == 0 && c.effectiveRank == Rank.ace
          ? aceDeclaredSuit
          : null;
      s = applyPlay(
        state: s,
        playerId: aiId,
        cards: [c],
        declaredSuit: decl,
      );
    }
    return true;
  }

  void _drainPendingOfflineAiTurns() {
    if (!mounted || _aiThinking || _pendingOfflineAiTurns.isEmpty) return;
    if (!_isOfflineSession || _tournamentRoundComplete) {
      _pendingOfflineAiTurns.clear();
      return;
    }
    final item = _pendingOfflineAiTurns.removeFirst();
    unawaited(_scheduleAiTurn(item.id, simulate: item.simulate));
  }

  Future<void> _scheduleAiTurn(String aiId, {bool simulate = false}) async {
    if (widget.isTournamentMode &&
        _tournamentFinishedPlayerIds.contains(aiId)) {
      final nextId = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: aiId,
      );
      if (nextId != _offlineState.currentPlayerId && mounted) {
        setState(() {
          _offlineState = _offlineState.copyWith(
            currentPlayerId: nextId,
            actionsThisTurn: 0,
            cardsPlayedThisTurn: 0,
            lastPlayedThisTurn: null,
            activeSkipCount: 0,
            queenSuitLock: null,
            preTurnCentreSuit: _offlineState.discardTopCard?.effectiveSuit,
            drawPileCount: _drawPile.length,
          );
        });
      }
      if (nextId != OfflineGameState.localId &&
          !_tournamentFinishedPlayerIds.contains(nextId)) {
        _scheduleAiTurn(nextId,
            simulate: simulate || _tournamentSimulatingRest);
      } else {
        if (!_tournamentSimulatingRest) {
          _startTimer(playTurnSound: false);
        } else {
          // All players finished — round should be complete.
          if (!_autoEliminateLastTournamentPlayer(_offlineState)) {
            setState(() => _tournamentSimulatingRest = false);
          }
        }
      }
      return;
    }
    if (_aiThinking) {
      _pendingOfflineAiTurns.addLast((id: aiId, simulate: simulate));
      return;
    }
    _offlineApplyLastCardsBluffPenaltyIfNeeded(aiId);
    setState(() => _aiThinking = true);

    var scheduledNext = false;
    var drainPendingAfterTurn = true;
    try {
      bool offlineTournamentInstantPacing() =>
          _isOfflineSession &&
          widget.isTournamentMode &&
          (simulate || _tournamentSimulatingRest);

      final hasPlayable =
          aiHasPlayableTurn(state: _offlineState, aiPlayerId: aiId);
      final diffMult = widget.aiDifficulty?.delayMultiplier ?? 1.0;
      final baseThinkMs = offlineTournamentInstantPacing()
          ? 0
          : (_randomAiDelayMs(1200, 2500) * diffMult).round();

      final lastCardsReactionGraceMs =
          _offlineLocalLastCardsReactionGraceMs(aiId: aiId);
      if (!offlineTournamentInstantPacing() && lastCardsReactionGraceMs > 0) {
        await Future.delayed(Duration(milliseconds: lastCardsReactionGraceMs));
        if (!mounted) return;
      }

      // Forced draw pacing: pause before draw and a brief pause after.
      if (!hasPlayable) {
        final drawPauseMs =
            offlineTournamentInstantPacing() ? 0 : (1000 * diffMult).round();
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
        difficulty: widget.aiDifficulty,
      );
      final newlyDeclaredLastCards = result.state.lastCardsDeclaredBy
          .difference(stateBeforeAiTurn.lastCardsDeclaredBy);
      if (newlyDeclaredLastCards.isNotEmpty) {
        if (offlineTournamentInstantPacing()) {
          if (mounted) {
            setState(() {
              for (final declId in newlyDeclaredLastCards) {
                final declName =
                    result.state.playerById(declId)?.displayName ?? declId;
                _pushMoveLog(MoveLogEntry.lastCardsDeclared(
                  playerId: declId,
                  playerName: declName,
                ));
              }
            });
          }
        } else {
          for (final declId in newlyDeclaredLastCards) {
            final declName =
                result.state.playerById(declId)?.displayName ?? declId;
            _announceLastCardsDeclaration(
              playerId: declId,
              playerName: declName,
              pushMoveLog: true,
            );
          }
        }
      }
      if (mounted) {
        _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
      }

      final playedByAi = result.playedCards;
      final sequentialReplay = playedByAi.isNotEmpty &&
          _offlineAiPlayedCardsReplaySequentially(
            stateBeforeAiTurn,
            aiId,
            playedByAi,
            result.aceDeclaredSuit,
          );

      // Add extra thought time for Ace/Joker declaration turns.
      if (!offlineTournamentInstantPacing() &&
          playedByAi.isNotEmpty &&
          (playedByAi.first.effectiveRank == Rank.ace ||
              playedByAi.first.isJoker)) {
        await Future.delayed(
            Duration(milliseconds: _randomAiDelayMs(1500, 3000)));
        if (!mounted) return;
      }

      if (!hasPlayable) {
        await Future.delayed(
            Duration(milliseconds: offlineTournamentInstantPacing() ? 0 : 600));
        if (!mounted) return;
      }

      if (offlineTournamentInstantPacing()) {
        // Instant path: engine + draw pile already updated via aiTakeTurn / _makeCards.
        if (playedByAi.isNotEmpty) {
          _discardPile.addAll(playedByAi);
        }
      } else if (playedByAi.isNotEmpty) {
        if (sequentialReplay) {
          var working = stateBeforeAiTurn;
          for (var i = 0; i < playedByAi.length; i++) {
            if (i > 0) {
              await Future.delayed(
                  Duration(milliseconds: _randomAiDelayMs(280, 500)));
              if (!mounted) return;
            }
            await _animateOpponentCardToDiscard(aiId, playedByAi[i]);
            if (!mounted) return;
            game_audio.AudioService.instance.playSound(GameSound.cardPlace);
            final snd = soundForCard(playedByAi[i]);
            if (snd != null) game_audio.AudioService.instance.playSound(snd);

            final c = playedByAi[i];
            final decl =
                working.actionsThisTurn == 0 && c.effectiveRank == Rank.ace
                    ? result.aceDeclaredSuit
                    : null;
            final dirBefore = working.direction;
            final skipBefore = working.activeSkipCount;
            final beforeCard = working;
            working = applyPlay(
              state: working,
              playerId: aiId,
              cards: [c],
              declaredSuit: decl,
            );
            _announcePenaltyChainAction(
              beforeState: beforeCard,
              afterState: working,
              playedCard: c,
              playerId: aiId,
              playerName:
                  _offlineState.playerById(aiId)?.displayName ?? aiId,
            );
            _discardPile.add(c);
            if (mounted) {
              setState(() {
                _offlineState =
                    working.copyWith(drawPileCount: _drawPile.length);
              });
            }
            if (working.direction != dirBefore) {
              game_audio.AudioService.instance
                  .playSound(GameSound.directionReversed);
            }
            if (working.activeSkipCount != skipBefore) {
              game_audio.AudioService.instance.playSound(GameSound.skipApplied);
              _flashSkipHighlight(skippedPlayerIdsForSkipState(working));
            }
          }
          if (mounted) HapticFeedback.mediumImpact();
        } else {
          for (var i = 0; i < playedByAi.length; i++) {
            if (i > 0) {
              await Future.delayed(
                  Duration(milliseconds: _randomAiDelayMs(280, 500)));
              if (!mounted) return;
            }
            await _animateOpponentCardToDiscard(aiId, playedByAi[i]);
            if (!mounted) return;
            game_audio.AudioService.instance.playSound(GameSound.cardPlace);
            final snd = soundForCard(playedByAi[i]);
            if (snd != null) game_audio.AudioService.instance.playSound(snd);
          }
          if (mounted) HapticFeedback.mediumImpact();
          _discardPile.addAll(playedByAi);
          _announcePenaltyChainAction(
            beforeState: stateBeforeAiTurn,
            afterState: result.preTurnAdvanceState,
            playedCard: playedByAi.first,
            playerId: aiId,
            playerName: _offlineState.playerById(aiId)?.displayName ?? aiId,
          );
          if (result.state.direction != stateBeforeAiTurn.direction) {
            game_audio.AudioService.instance
                .playSound(GameSound.directionReversed);
          }
          // preTurnAdvanceState — result.state has activeSkipCount cleared by advanceTurn.
          if (result.preTurnAdvanceState.activeSkipCount >
              stateBeforeAiTurn.activeSkipCount) {
            game_audio.AudioService.instance.playSound(GameSound.skipApplied);
            _flashSkipHighlight(
              skippedPlayerIdsForSkipState(result.preTurnAdvanceState),
            );
          }
        }
      } else if (!offlineTournamentInstantPacing()) {
        final drawN = stateBeforeAiTurn.activePenaltyCount > 0
            ? stateBeforeAiTurn.activePenaltyCount
            : 1;
        await _animateDrawFlightsToPlayer(aiId, drawN);
        if (mounted) {
          HapticFeedback.lightImpact();
          if (drawN > 1) {
            _momentPenaltyHit(playerId: aiId, cardsDrawn: drawN);
          }
        }
      }

      if (!offlineTournamentInstantPacing() &&
          playedByAi.isNotEmpty &&
          result.preTurnAdvanceState.cardsPlayedThisTurn >=
              kMultiPlayCelebrationMinCards) {
        _fireMultiPlayCelebrationIfNeeded(
            result.preTurnAdvanceState.cardsPlayedThisTurn);
      }

      final aiPlayerName = _offlineState.playerById(aiId)?.displayName ?? aiId;

      // Do not setState here when _checkWin returns true: tournament round-end
      // pops this route from _handleTournamentPlayerFinished; partial finishes
      // already clear _aiThinking inside _handleTournamentPlayerFinished.
      if (playedByAi.isNotEmpty) _trackMatchPlay(aiId, playedByAi);
      if (_checkWin(
        aiId,
        result.state,
        onNestedAiScheduled: () => scheduledNext = true,
      )) {
        drainPendingAfterTurn = false;
        _pendingOfflineAiTurns.clear();
        return;
      }

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

      // AI quick chat: use preset messages like human players (30% chance).
      if (!offlineTournamentInstantPacing() &&
          aiConfig != null &&
          playedByAi.isNotEmpty &&
          _chatRng.nextDouble() < 0.30) {
        final pool = kAiQuickReactionIndices;
        final msgIndex = pool[_chatRng.nextInt(pool.length)];
        _showQuickChatBubble(aiId, aiPlayerName, msgIndex, isLocal: false);
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
          // Queen cover draw: AI played a Queen but couldn't cover, had to draw.
          if (result.queenCoverDrawCount > 0) {
            _trackMatchDraw(aiId, result.queenCoverDrawCount);
            _pushMoveLog(MoveLogEntry.draw(
              playerId: aiId,
              playerName: aiPlayerName,
              drawCount: result.queenCoverDrawCount,
            ));
          }
        } else {
          final aiDrawCount = stateBeforeAiTurn.activePenaltyCount > 0
              ? stateBeforeAiTurn.activePenaltyCount
              : 1;
          if (aiDrawCount > 1) {
            _momentPenaltyHit(playerId: aiId, cardsDrawn: aiDrawCount);
          }
          _trackMatchDraw(aiId, aiDrawCount);
          _pushMoveLog(MoveLogEntry.draw(
            playerId: aiId,
            playerName: aiPlayerName,
            drawCount: aiDrawCount,
          ));
        }
      });

      // Yield to the event loop between instant-paced turns so the UI can
      // paint and remain responsive.
      if (offlineTournamentInstantPacing()) {
        await Future.delayed(Duration.zero);
        if (!mounted) return;
      }

      if (nextId != OfflineGameState.localId) {
        scheduledNext = true;
        _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
      } else {
        if (_tournamentSimulatingRest) {
          // Local player is finished — skip to next active AI.
          final skipToId = _nextTournamentActivePlayerId(
            state: _offlineState,
            startAfterPlayerId: nextId,
          );
          if (skipToId != OfflineGameState.localId &&
              !_tournamentFinishedPlayerIds.contains(skipToId)) {
            scheduledNext = true;
            if (mounted && skipToId != _offlineState.currentPlayerId) {
              setState(() {
                _offlineState = _offlineState.copyWith(
                  currentPlayerId: skipToId,
                  actionsThisTurn: 0,
                  cardsPlayedThisTurn: 0,
                  lastPlayedThisTurn: null,
                  activeSkipCount: 0,
                  queenSuitLock: null,
                  preTurnCentreSuit:
                      _offlineState.discardTopCard?.effectiveSuit,
                  drawPileCount: _drawPile.length,
                );
              });
            }
            _scheduleAiTurn(skipToId, simulate: true);
          } else {
            // All players finished — round should be complete.
            if (!_autoEliminateLastTournamentPlayer(_offlineState)) {
              setState(() => _tournamentSimulatingRest = false);
            }
          }
        } else {
          _startTimer();
        }
      }
    } finally {
      if (_aiThinking && mounted && !scheduledNext) {
        setState(() => _aiThinking = false);
      }
      if (drainPendingAfterTurn) {
        _drainPendingOfflineAiTurns();
      }
    }
  }

  Future<void> _onTournamentSkipTapped() async {
    if (!widget.isTournamentMode ||
        !_isOfflineSession ||
        _tournamentRoundComplete ||
        _tournamentSimulatingRest) {
      return;
    }
    if (!_tournamentFinishedPlayerIds.contains(OfflineGameState.localId)) {
      return;
    }
    _startTournamentSimulation();
  }

  /// Starts fast-forward simulation of the rest of the round when the local
  /// player is already qualified (offline tournament only). Schedules the
  /// current (AI) player's turn with no delays or card flights until the round
  /// completes. Works for any player count (2+).
  ///
  /// If an AI turn is already in progress, sets the fast-forward flag so the
  /// rest of that turn and all following turns use instant pacing.
  void _startTournamentSimulation() {
    if (!widget.isTournamentMode ||
        !_isOfflineSession ||
        _tournamentRoundComplete ||
        _tournamentSimulatingRest) {
      return;
    }
    if (!_tournamentFinishedPlayerIds.contains(OfflineGameState.localId)) {
      return;
    }
    setState(() => _tournamentSimulatingRest = true);
    _engineTimer.cancel();
    if (_aiThinking) {
      return;
    }
    var id = _offlineState.currentPlayerId;
    if (_tournamentFinishedPlayerIds.contains(id) ||
        id == OfflineGameState.localId) {
      id = _nextTournamentActivePlayerId(
        state: _offlineState,
        startAfterPlayerId: id,
      );
    }
    if (id != OfflineGameState.localId &&
        !_tournamentFinishedPlayerIds.contains(id)) {
      _scheduleAiTurn(id, simulate: true);
    } else {
      // Defensive: no active player found.
      if (!_autoEliminateLastTournamentPlayer(_offlineState)) {
        setState(() => _tournamentSimulatingRest = false);
      }
    }
  }

  // ── Reshuffle centre pile → draw pile ─────────────────────────────────────

  /// Dedicated reshuffle function. Invoke after each draw path completes
  /// (timeout draw, invalid-play penalty, player draw, AI turn) — this covers
  /// all draw paths that mutate [_drawPile].
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
  ///   6. Shows a "Reshuffling deck..." stack-block banner.
  ///   7. Prints the new count to the console for confirmation.
  ///
  /// When [silent] is true (offline tournament fast-forward), skips sound,
  /// pile animation notifier, and banner so simulation stays instant.
  void _reshuffleCentrePileIntoDrawPile({bool silent = false}) {
    // Called after draw paths complete (see [_makeCards] doc) — not from the
    // factory during [applyDraw].
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
    fisherYatesShuffle(toShuffle);

    // ── 3. Add shuffled cards to draw pile ──────────────────────────────────
    _drawPile.addAll(toShuffle);
    if (!silent) {
      game_audio.AudioService.instance.playSound(GameSound.shuffleDeck);
    }

    if (!mounted) return;

    // ── 4 & 5. Update counter + trigger animation ────────────────────────────
    setState(() {
      _offlineState = _offlineState.copyWith(drawPileCount: _drawPile.length);
      if (!silent) {
        _reshuffleNotifier.value = !_reshuffleNotifier.value;
      }
    });

    // ── 6. Visible banner so players know a reshuffle happened ──────────────
    if (!silent) {
      _showStackBlockBanner('Reshuffling deck...', AppColors.goldDark);
    }
  }

  /// Pops the table route on the **next** frame so Riverpod [Consumer]
  /// dependents and other [InheritedWidget]s finish their update cycle before
  /// this route is removed. Synchronous [Navigator.pop] here caused
  /// `'_dependents.isEmpty': is not true` when leaving the table after round 1.
  void _scheduleTournamentTablePop(TournamentRoundGameResult result) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.maybeOf(context);
      if (nav == null || !nav.canPop()) return;
      nav.pop(result);
    });
  }

  /// Auto-eliminates the last remaining tournament player when all other
  /// players have already qualified. This mirrors [TournamentEngine]'s rule
  /// that the final player is eliminated immediately once everyone else has
  /// finished, so the round cannot get stuck with a single player.
  ///
  /// Returns true when an elimination pop was scheduled.
  bool _autoEliminateLastTournamentPlayer(GameState state) {
    if (!widget.isTournamentMode) return false;
    // Only trigger when at least one player has already finished.
    if (_tournamentFinishedPlayerIds.isEmpty) return false;

    final remaining = state.players
        .where((p) => !_tournamentFinishedPlayerIds.contains(p.id))
        .toList(growable: false);
    if (remaining.length != 1) return false;

    final lastId = remaining.first.id;
    _tournamentFinishedPlayerIds.add(lastId);
    final finishPosition = _tournamentFinishedPlayerIds.length;
    widget.onPlayerFinished(lastId, finishPosition);
    _tournamentRoundComplete = true;
    final eliminatedPlayerId = lastId;
    game_audio.AudioService.instance.playSound(GameSound.tournamentEliminate);

    _engineTimer.cancel();
    if (mounted) {
      _scheduleTournamentTablePop(
        TournamentRoundGameResult(
          finishedPlayerIds: List<String>.from(_tournamentFinishedPlayerIds),
          eliminatedPlayerId: eliminatedPlayerId,
        ),
      );
    }
    return true;
  }

  // ── Win detection ──────────────────────────────────────────────────

  void _offlineApplyLastCardsBluffPenaltyIfNeeded(String playerId) {
    if (!_isOfflineSession) return;
    if (!_offlineState.lastCardsDeclaredBy.contains(playerId)) return;
    final player = _offlineState.playerById(playerId);
    if (player == null) return;
    final hasJoker = player.hand.any((c) => c.isJoker);
    // Bluff is determined fresh, right as this player's turn begins — not at
    // declare time. The discard pile keeps changing while other players take
    // their turns in between declaring and this player's turn actually
    // arriving, so a check locked in at declare-time can go stale and
    // wrongly flag a hand that becomes genuinely clearable by the time play
    // reaches them. lastCardsHandWasClearableAtTurnStart is recomputed live
    // by advanceTurn() for whichever seat is about to play, using the real
    // board state at that moment — that's the correct signal to use here.
    if (hasJoker || player.lastCardsHandWasClearableAtTurnStart) return;
    setState(() {
      _offlineState = _offlineState.copyWith(
        lastCardsDeclaredBy: {..._offlineState.lastCardsDeclaredBy}
          ..remove(playerId),
      );
      _offlineState = applyLastCardsBluffPenaltyDraw(
        state: _offlineState,
        playerId: playerId,
        count: 2,
        cardFactory: _makeCards,
      ).copyWith(drawPileCount: _drawPile.length);
    });
    final name = _offlineState.playerById(playerId)?.displayName ?? playerId;
    _pushMoveLog(MoveLogEntry.lastCardsBluff(
      playerId: playerId,
      playerName: name,
      drawCount: 2,
    ));
    _flashLastCardsBluffBanner(
      '"$name" bluffed Last Cards! Drew 2 cards.',
    );
    if (mounted) {
      _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
    }
  }

  /// Returns true when undeclared empty-hand draw was applied (offline only).
  bool _tryApplyOfflineUndeclaredLastCardsDraw(GameState state) {
    if (!_isOfflineSession) return false;
    for (final p in state.players) {
      if (!needsUndeclaredLastCardsDraw(
        state: state,
        playerId: p.id,
        isBustMode: false,
      )) {
        continue;
      }
      var ns = applyUndeclaredLastCardsDraw(
        state: state,
        playerId: p.id,
        isBustMode: false,
        cardFactory: _makeCards,
      );
      final offenderName = state.playerById(p.id)?.displayName ?? p.id;
      if (p.id == OfflineGameState.localId) {
        _showError('You must declare Last Cards before winning!');
      } else {
        _showError(
          '$offenderName tried to win without declaring Last Cards.',
        );
      }
      if (mounted) {
        _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
      }
      final nextId = nextPlayerId(state: ns);
      final resolved = _resolveTournamentNextPlayerId(ns, nextId);
      ns = advanceTurn(ns, nextId: resolved);
      setState(() {
        _offlineState = ns.copyWith(drawPileCount: _drawPile.length);
        _selectedCardId = null;
        final local = _offlineState.players
            .where((x) => x.tablePosition == TablePosition.bottom)
            .firstOrNull;
        if (local != null) _syncHandOrder(local.hand);
      });
      _engineTimer.cancel();
      // Defer so this does not run synchronously during the same stack as
      // [_scheduleAiTurn] (microtask runs after [_aiThinking] clears).
      final followUpId = ns.currentPlayerId;
      final simRest = _tournamentSimulatingRest;
      Future.microtask(() {
        if (!mounted) return;
        if (followUpId != OfflineGameState.localId) {
          _scheduleAiTurn(followUpId, simulate: simRest);
        } else {
          _startTimer();
        }
      });
      return true;
    }
    return false;
  }

  bool _checkWin(
    String lastActorId,
    GameState state, {
    void Function()? onNestedAiScheduled,
  }) {
    if (!shouldShowStandardWinOverlay(
        isTournamentMode: widget.isTournamentMode)) {
      // Collect all newly-confirmable finishers in one pass.
      final newFinishers = <String>[];
      for (final p in state.players) {
        if (_tournamentFinishedPlayerIds.contains(p.id)) continue;
        if (canConfirmPlayerWin(state: state, playerId: p.id)) {
          newFinishers.add(p.id);
        }
      }
      if (newFinishers.isEmpty) {
        // No new finishers — still check auto-eliminate in case the last
        // remaining player was already stuck.
        if (_autoEliminateLastTournamentPlayer(state)) return true;
        return false;
      }

      // ── Batch-record all finishers before making any scheduling decision ──
      // Recording inside the loop used to call _scheduleAiTurn once per
      // finisher, creating concurrent AI turns that corrupted _offlineState.
      for (final playerId in newFinishers) {
        _tournamentFinishedPlayerIds.add(playerId);
        final finishPosition = _tournamentFinishedPlayerIds.length;
        widget.onPlayerFinished(playerId, finishPosition);
        // Play qualify sound for every finisher except the last one in the
        // round (the last finisher triggers eliminate sound below).
        if (_tournamentFinishedPlayerIds.length < state.players.length) {
          game_audio.AudioService.instance
              .playSound(GameSound.tournamentQualify);
        }
      }

      // ── After all finishers are recorded, decide what happens next ────────

      // Check if the round is now fully complete (all players accounted for).
      if (_tournamentFinishedPlayerIds.length == state.players.length) {
        _tournamentRoundComplete = true;
        final eliminatedPlayerId = _tournamentFinishedPlayerIds.last;
        game_audio.AudioService.instance
            .playSound(GameSound.tournamentEliminate);
        _engineTimer.cancel();
        if (mounted) {
          _scheduleTournamentTablePop(
            TournamentRoundGameResult(
              finishedPlayerIds:
                  List<String>.from(_tournamentFinishedPlayerIds),
              eliminatedPlayerId: eliminatedPlayerId,
            ),
          );
        }
        return true;
      }

      // Auto-eliminate if only one unfinished player remains.
      if (_autoEliminateLastTournamentPlayer(state)) return true;

      // Round is still in progress — advance to the next active player and
      // schedule exactly ONE AI turn (or start the human timer). Use the last
      // recorded finisher as the "start after" anchor.
      final lastFinisher = newFinishers.last;
      final nextId = _nextTournamentActivePlayerId(
        state: state,
        startAfterPlayerId: lastFinisher,
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

      if (mounted) {
        _reshuffleCentrePileIntoDrawPile(silent: _tournamentSimulatingRest);
      }

      if (nextId != OfflineGameState.localId) {
        onNestedAiScheduled?.call();
        _scheduleAiTurn(nextId, simulate: _tournamentSimulatingRest);
      } else {
        _startTimer();
      }
      return true;
    }

    if (shouldShowStandardWinOverlay(
        isTournamentMode: widget.isTournamentMode)) {
      if (_tryApplyOfflineUndeclaredLastCardsDraw(state)) {
        return true;
      }
    }

    if (!wouldConfirmWin(state)) return false;

    final winner = state.players
        .where((p) => p.hand.isEmpty && p.cardCount == 0)
        .firstOrNull!;
    if (winner.id == OfflineGameState.localId) {
      unawaited(PlayerLevelService.instance.awardWinXP());
      game_audio.AudioService.instance.playSound(GameSound.playerWin);
    } else {
      unawaited(PlayerLevelService.instance.awardLossXP());
      game_audio.AudioService.instance.playSound(GameSound.playerLose);
    }

    _gameStopwatch.stop();
    AnalyticsService.instance.logGameCompleted(
      mode: _isOfflineSession ? 'offline' : 'online',
      isWin: winner.id == OfflineGameState.localId,
      durationSeconds: _gameStopwatch.elapsed.inSeconds,
    );

    Future.microtask(() {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WinDialog(
          winnerName: winner.displayName,
          isLocalWin: winner.id == OfflineGameState.localId,
          onPlayAgain: () {
            Navigator.of(context).pop();
            unawaited(AdsService.instance.maybeShowInterstitialAfterMatch());
            setState(() {
              _initNewGame();
              _selectedCardId = null;
              _flyingCardId = null;
              _aiThinking = false;
            });
          },
          xpAwarded: winner.id == OfflineGameState.localId ? 50 : 10,
          matchStats: _buildMatchStats(),
        ),
      );
    });
    return true;
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

      final currentOrder = _orderedHand(localPlayer.hand)
          .where((c) => c.id != _flyingCardId)
          .map((c) => c.id)
          .toList();
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

  static bool _isSpecialCardStat(CardModel c) {
    const specialRanks = {
      Rank.two,
      Rank.jack,
      Rank.queen,
      Rank.king,
      Rank.ace,
      Rank.eight,
    };
    return specialRanks.contains(c.effectiveRank) || c.isJoker;
  }

  void _trackMatchPlay(String playerId, List<CardModel> cards) {
    if (!_isOfflineSession) return;
    _matchCardsPlayed[playerId] =
        (_matchCardsPlayed[playerId] ?? 0) + cards.length;
    final specials = cards.where(_isSpecialCardStat).length;
    if (specials > 0) {
      _matchSpecialsPlayed[playerId] =
          (_matchSpecialsPlayed[playerId] ?? 0) + specials;
    }
  }

  void _trackMatchDraw(String playerId, int count) {
    if (!_isOfflineSession) return;
    _matchDrawsTaken[playerId] = (_matchDrawsTaken[playerId] ?? 0) + count;
  }

  List<MatchPlayerStat> _buildMatchStats() {
    final stats = <MatchPlayerStat>[];
    for (final p in _offlineState.players) {
      stats.add(MatchPlayerStat(
        displayName: p.displayName,
        isLocal: p.id == OfflineGameState.localId,
        cardsPlayed: _matchCardsPlayed[p.id] ?? 0,
        drawsTaken: _matchDrawsTaken[p.id] ?? 0,
        specialsPlayed: _matchSpecialsPlayed[p.id] ?? 0,
      ));
    }
    stats.sort((a, b) => a.isLocal ? -1 : (b.isLocal ? 1 : 0));
    return stats;
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

    mergeOrPrependPlayLog(_moveLogEntries, entry);
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
    return skippedPlayerDisplayNamesForSkipState(state);
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

  /// Resolves server [CardPlayedEvent.skippedPlayers] names to session IDs.
  Set<String> _playerIdsForSkippedNames(
    GameState? state,
    List<String> skippedNames,
  ) {
    if (state == null || skippedNames.isEmpty) return {};
    final out = <String>{};
    for (final p in state.players) {
      if (skippedNames.contains(p.displayName)) out.add(p.id);
    }
    return out;
  }

  void _pushMoveLog(MoveLogEntry entry) {
    _moveLogEntries.insert(0, entry);
    if (_moveLogEntries.length > 3) {
      _moveLogEntries.removeRange(3, _moveLogEntries.length);
    }
  }

  void _onOnlineGameMoment(GameMomentEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case 'penalty_hit':
        _momentPenaltyHit(
          playerId: e.playerId,
          cardsDrawn: e.cardsDrawn ?? 0,
        );
        break;
      case 'last_cards':
        _momentLastCardsPulse(playerId: e.playerId);
        break;
      case 'stack_block':
        // Penalty chain banners are derived from card_played + applyPlay replay
        // in [_announceOnlinePenaltyChainFromCardPlay] so all scenarios work.
        break;
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

  void _announceLastCardsDeclaration({
    required String playerId,
    required String playerName,
    required bool pushMoveLog,
  }) {
    if (_isOfflineSession) {
      _momentLastCardsPulse(playerId: playerId);
    }
    HapticFeedback.mediumImpact();
    game_audio.AudioService.instance.playSound(GameSound.tournamentQualify);
    final seq = ++_lastCardsDeclaredBannerSeq;
    setState(() {
      _lastCardsDeclaredBannerText = '"$playerName" declared Last Cards!';
      _lastCardsBluffBannerText = null;
      if (pushMoveLog) {
        _pushMoveLog(MoveLogEntry.lastCardsDeclared(
          playerId: playerId,
          playerName: playerName,
        ));
      }
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted && seq == _lastCardsDeclaredBannerSeq) {
        setState(() => _lastCardsDeclaredBannerText = null);
      }
    });
  }

  void _flashLastCardsBluffBanner(String text) {
    _lastCardsDeclaredBannerSeq++;
    setState(() {
      _lastCardsBluffBannerText = text;
      _lastCardsDeclaredBannerText = null;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _lastCardsBluffBannerText = null);
    });
  }

  void _showOpponentProfileSheet(PlayerModel player) {
    final uid = player.firebaseUid;
    if (uid == null || uid.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OtherPlayerProfileSheet(
        firebaseUid: uid,
        fallbackDisplayName: player.displayName,
      ),
    );
  }

  void _onDeclareLastCards() {
    final live = ref.read(gameStateProvider);
    if (live != null) {
      ref.read(gameNotifierProvider.notifier).declareLastCards();
      AnalyticsService.instance.logLastCardsDeclared(mode: 'online');
      return;
    }
    final localId = OfflineGameState.localId;
    if (!mayDeclareLastCards(
        currentPlayerId: _offlineState.currentPlayerId, playerId: localId)) {
      _showError('Declare Last Cards when it is not your turn.');
      return;
    }
    if (_offlineState.lastCardsDeclaredBy.contains(localId)) return;
    final p = _offlineState.playerById(localId);
    final name = p?.displayName ?? localId;
    // Bluff status is intentionally NOT determined here. The discard pile
    // keeps changing as opponents take their turns between now and when it
    // actually becomes this player's turn, so any check run at declare-time
    // would be evaluating a board state that's already stale by the time it
    // matters. See _offlineApplyLastCardsBluffPenaltyIfNeeded, which checks
    // freshly (using the live board) right as this player's turn begins.
    setState(() {
      _offlineState = _offlineState.copyWith(
        lastCardsDeclaredBy: {..._offlineState.lastCardsDeclaredBy, localId},
      );
    });
    _pushMoveLog(MoveLogEntry.lastCardsDeclared(
      playerId: localId,
      playerName: name,
    ));
    AnalyticsService.instance.logLastCardsDeclared(mode: 'offline');
  }

  // ── Quick chat ──────────────────────────────────────────────────────────

  void _showQuickChatBubble(
      String playerId, String playerName, int messageIndex,
      {bool isLocal = false}) {
    if (!isValidReactionWireIndex(messageIndex)) return;
    final bubbleId =
        '${playerId}_${messageIndex}_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
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

  void _sendQuickChat(int messageIndex) {
    if (_quickChatCooldownRemaining > 0) return;
    final level = PlayerLevelService.instance.currentLevel.value;
    if (!isReactionUnlockedForLevel(messageIndex, level)) return;

    final isOfflineMode = _isOfflineSession;

    final localPlayerId = ref
            .read(gameStateProvider)
            ?.players
            .where((p) => p.tablePosition == TablePosition.bottom)
            .firstOrNull
            ?.id ??
        OfflineGameState.localId;

    final bottomPlayer = ref
            .read(gameStateProvider)
            ?.players
            .where((p) => p.tablePosition == TablePosition.bottom)
            .firstOrNull ??
        _offlineState.players
            .where((p) => p.tablePosition == TablePosition.bottom)
            .firstOrNull;
    final localChatName =
        (bottomPlayer != null && bottomPlayer.displayName.isNotEmpty)
            ? bottomPlayer.displayName
            : ref.read(displayNameForGameProvider);

    _showQuickChatBubble(
      localPlayerId,
      localChatName,
      messageIndex,
      isLocal: true,
    );

    if (!isOfflineMode) {
      final handler = ref.read(gameEventHandlerProvider);
      if (!handler.sendQuickChat(QuickChatAction(messageIndex: messageIndex))) {
        ref.read(gameNotifierProvider.notifier).connectionSendFailed();
      }
    }

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
}
