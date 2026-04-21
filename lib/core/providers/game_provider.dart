import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/services/audio_service.dart';
import 'package:last_cards/services/game_sound.dart' show GameSound, soundForCard;
import 'package:last_cards/shared/rules/win_condition_rules.dart';

import '../models/card_model.dart';
import '../models/game_event.dart';
import '../models/game_state.dart';
import '../network/game_event_handler.dart';
import 'connection_provider.dart';
import 'online_rejoin_provider.dart';

// ── Notifier state wrapper ────────────────────────────────────────────────────

/// Wraps [GameState] with extra UI-facing fields that are not part of the
/// server-authoritative game state but are needed for reactive UI updates.
class GameNotifierState {
  const GameNotifierState({
    this.gameState,
    this.pendingSuitChoice = false,
    this.pendingSuitChoiceCardId,
    this.pendingJokerResolution = false,
    this.pendingJokerCardId,
    this.lastError,
    this.rankedRatingChanges,
    this.isRanked = false,
    this.isHardcoreSession = false,
    this.isPrivateSession = false,
    this.isBustSession = false,
    this.isKnockoutTournamentSession = false,
    this.socketDisconnectedPlayerIds = const <String>{},
  });

  /// The authoritative server game state. Null until the first snapshot arrives.
  final GameState? gameState;

  /// Online: [PlayerSocketLostEvent] — hide opponent avatars until restored or
  /// [GameEndedEvent]. Does not include the local player (they do not receive
  /// this event while disconnected).
  final Set<String> socketDisconnectedPlayerIds;

  /// True while the server is waiting for the local player to pick a suit
  /// (after playing an Ace). Cleared when [SuitChoiceAction] is sent.
  final bool pendingSuitChoice;

  /// Card ID of the Ace that triggered the pending suit choice.
  final String? pendingSuitChoiceCardId;

  /// True while the server is waiting for the local player to declare a Joker's
  /// identity. Cleared when [DeclareJokerAction] is sent.
  final bool pendingJokerResolution;

  /// Card ID of the Joker awaiting declaration.
  final String? pendingJokerCardId;

  /// Most recent server error message, or null if no error is pending.
  /// Cleared automatically when a new [StateSnapshotEvent] arrives.
  final String? lastError;

  /// Per-player rating deltas from the last ranked game_ended event.
  ///
  /// Key is server player ID. Null when the completed game was not ranked.
  final Map<String, int>? rankedRatingChanges;

  /// True when the current session is a ranked match (from session_config).
  final bool isRanked;

  /// Hardcore session (from session_config); mirrors [GameState.isHardcore] once snapshots arrive.
  final bool isHardcoreSession;

  /// Private friend room ([session_config.isPrivate]).
  final bool isPrivateSession;

  /// Bust mode session ([session_config.isBustMode]).
  final bool isBustSession;

  /// Knockout tournament UX ([session_config.isKnockoutTournament]).
  final bool isKnockoutTournamentSession;

  GameNotifierState copyWith({
    GameState? gameState,
    bool? pendingSuitChoice,
    String? pendingSuitChoiceCardId,
    bool? pendingJokerResolution,
    String? pendingJokerCardId,
    String? lastError,
    Map<String, int>? rankedRatingChanges,
    bool? isRanked,
    bool? isHardcoreSession,
    bool? isPrivateSession,
    bool? isBustSession,
    bool? isKnockoutTournamentSession,
    Set<String>? socketDisconnectedPlayerIds,
    bool clearError = false,
    bool clearSuitChoice = false,
    bool clearJokerResolution = false,
    bool clearSocketDisconnected = false,
  }) {
    return GameNotifierState(
      gameState: gameState ?? this.gameState,
      pendingSuitChoice:
          clearSuitChoice ? false : (pendingSuitChoice ?? this.pendingSuitChoice),
      pendingSuitChoiceCardId: clearSuitChoice
          ? null
          : (pendingSuitChoiceCardId ?? this.pendingSuitChoiceCardId),
      pendingJokerResolution: clearJokerResolution
          ? false
          : (pendingJokerResolution ?? this.pendingJokerResolution),
      pendingJokerCardId: clearJokerResolution
          ? null
          : (pendingJokerCardId ?? this.pendingJokerCardId),
      lastError: clearError ? null : (lastError ?? this.lastError),
      rankedRatingChanges: rankedRatingChanges ?? this.rankedRatingChanges,
      isRanked: isRanked ?? this.isRanked,
      isHardcoreSession: isHardcoreSession ?? this.isHardcoreSession,
      isPrivateSession: isPrivateSession ?? this.isPrivateSession,
      isBustSession: isBustSession ?? this.isBustSession,
      isKnockoutTournamentSession:
          isKnockoutTournamentSession ?? this.isKnockoutTournamentSession,
      socketDisconnectedPlayerIds: clearSocketDisconnected
          ? const <String>{}
          : (socketDisconnectedPlayerIds ?? this.socketDisconnectedPlayerIds),
    );
  }
}

// ── Game State Notifier ───────────────────────────────────────────────────────

class GameNotifier extends StateNotifier<GameNotifierState> {
  GameNotifier(this._eventHandler, this._onlineRejoin) : super(const GameNotifierState()) {
    _subscribe();
  }

  final GameEventHandler _eventHandler;
  final OnlineRejoinNotifier _onlineRejoin;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// One [GameSound.cardDraw] per draw action (not per `card_drawn` line).
  /// Reset on [TurnChangedEvent], [GameEndedEvent], and [clearOnlineState] —
  /// not on every [StateSnapshotEvent], so a snapshot between multi-card
  /// penalty draws cannot replay [GameSound.cardDraw].
  bool _drawSoundPlayedThisBatch = false;

  /// Per player: suppress this many `card_drawn` sounds after
  /// [InvalidPlayPenaltyEvent] (mirrors [TableScreen._suppressDrawLogForPlayer]).
  final Map<String, int> _suppressCardDrawSoundByPlayerId = {};

  /// True after [invalid_play_penalty] plays cardDraw+penaltyDraw for the local
  /// player — [penalty_applied] must not duplicate those sounds.
  bool _invalidPenaltySoundPlayed = false;

  /// Opponent [card_played] animations run before applying the paired snapshot.
  int _opponentFlightsInFlight = 0;
  final Queue<GameState> _deferredSnapshots = Queue<GameState>();
  static const Duration _opponentFlightWatchdogDuration = Duration(seconds: 6);
  Timer? _opponentFlightWatchdog;

  // Convenience getter so callers that only need GameState? don't change.
  GameState? get gameState => state.gameState;

  void _applyStateSnapshot(StateSnapshotEvent e) {
    if (state.gameState?.phase == GamePhase.ended &&
        e.gameState.phase == GamePhase.playing) {
      return;
    }
    final suitChoiceResolved = state.pendingSuitChoice &&
        state.gameState != null &&
        e.gameState.currentPlayerId != state.gameState!.currentPlayerId;
    final inGame = e.gameState.players.map((p) => p.id).toSet();
    final prunedDisconnected = state.socketDisconnectedPlayerIds
        .where(inGame.contains)
        .toSet();
    state = state.copyWith(
      gameState: e.gameState,
      clearError: true,
      clearSuitChoice: !e.gameState.pendingJokerResolution &&
          (!state.pendingSuitChoice || suitChoiceResolved),
      socketDisconnectedPlayerIds: prunedDisconnected,
    );
    wouldConfirmWin(e.gameState);
  }

  /// Called after [TableScreen] finishes opponent card flight animations.
  void opponentPlayFlightsFinished() {
    _cancelOpponentFlightWatchdog();
    if (_opponentFlightsInFlight > 0) {
      _opponentFlightsInFlight--;
    }
    // Do not apply deferred snapshots until every opponent flight has finished,
    // or the UI would jump ahead while another animation is still running.
    if (_opponentFlightsInFlight > 0) return;
    if (_deferredSnapshots.isEmpty) return;
    if (state.gameState?.phase == GamePhase.ended) {
      _deferredSnapshots.clear();
      return;
    }
    // Coalesce to the latest authoritative state (FIFO would end on the same
    // final state but would repeat work).
    GameState? latest;
    while (_deferredSnapshots.isNotEmpty) {
      latest = _deferredSnapshots.removeFirst();
    }
    _applyStateSnapshot(StateSnapshotEvent(latest!));
  }

  void _cancelOpponentFlightWatchdog() {
    _opponentFlightWatchdog?.cancel();
    _opponentFlightWatchdog = null;
  }

  void _armOpponentFlightWatchdog() {
    _opponentFlightWatchdog?.cancel();
    _opponentFlightWatchdog = Timer(_opponentFlightWatchdogDuration, () {
      _opponentFlightWatchdog = null;
      if (_opponentFlightsInFlight <= 0) return;
      _opponentFlightsInFlight = 0;
      if (_deferredSnapshots.isEmpty) return;
      if (state.gameState?.phase == GamePhase.ended) {
        _deferredSnapshots.clear();
        return;
      }
      GameState? latest;
      while (_deferredSnapshots.isNotEmpty) {
        latest = _deferredSnapshots.removeFirst();
      }
      _applyStateSnapshot(StateSnapshotEvent(latest!));
    });
  }

  void _subscribe() {
    // ── state_snapshot ──────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.stateSnapshots.listen((e) {
        if (state.gameState?.phase == GamePhase.ended &&
            e.gameState.phase == GamePhase.playing) {
          return;
        }
        final localId = e.gameState.localPlayer?.id;
        if (localId != null) {
          _onlineRejoin.setPlayerId(localId);
        }
        if (_opponentFlightsInFlight > 0) {
          if (state.gameState?.phase == GamePhase.ended) {
            return;
          }
          _deferredSnapshots.addLast(e.gameState);
          _armOpponentFlightWatchdog();
          return;
        }
        _applyStateSnapshot(e);
      }),
    );

    // ── invalid_play_penalty ────────────────────────────────────────────────
    _subs.add(
      _eventHandler.invalidPlayPenalties.listen((e) {
        _suppressCardDrawSoundByPlayerId.update(
          e.playerId,
          (v) => v + e.drawCount,
          ifAbsent: () => e.drawCount,
        );
        final localId = state.gameState?.localPlayer?.id;
        if (localId != null && e.playerId == localId) {
          _invalidPenaltySoundPlayed = true;
          unawaited(AudioService.instance.playSound(GameSound.cardDraw));
          unawaited(AudioService.instance.playSound(GameSound.penaltyDraw));
        }
      }),
    );

    // ── card_played ─────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.cardPlays.listen((e) {
        if (state.gameState == null) return;
        final localId = state.gameState!.localPlayer?.id;
        if (localId != null && e.playerId != localId) {
          _opponentFlightsInFlight++;
          _armOpponentFlightWatchdog();
        }
        for (final card in e.cards) {
          unawaited(AudioService.instance.playSound(GameSound.cardPlace));
          final s = soundForCard(card);
          if (s != null) unawaited(AudioService.instance.playSound(s));
        }
        final before = e.activeSkipCountBefore;
        final after = e.activeSkipCountAfter;
        final skipIncreased =
            before != null && after != null && after > before;
        if (skipIncreased) {
          unawaited(AudioService.instance.playSound(GameSound.skipApplied));
        }
        if (e.directionReversed) {
          unawaited(
              AudioService.instance.playSound(GameSound.directionReversed));
        }
      }),
    );

    // ── card_drawn ──────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.cardDraws.listen((e) {
        if (state.gameState == null) return;
        final suppressed = _suppressCardDrawSoundByPlayerId[e.playerId] ?? 0;
        if (suppressed > 0) {
          if (suppressed <= 1) {
            _suppressCardDrawSoundByPlayerId.remove(e.playerId);
          } else {
            _suppressCardDrawSoundByPlayerId[e.playerId] = suppressed - 1;
          }
        } else {
          if (!_drawSoundPlayedThisBatch) {
            unawaited(AudioService.instance.playSound(GameSound.cardDraw));
            _drawSoundPlayedThisBatch = true;
          }
        }
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            drawPileCount: (state.gameState!.drawPileCount - 1)
                .clamp(0, double.infinity)
                .toInt(),
          ),
        );
      }),
    );

    // ── turn_changed ────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.turnChanges.listen((e) {
        if (state.gameState == null) return;
        _drawSoundPlayedThisBatch = false;
        // Partial patch arrives before state_snapshot; reset per-turn fields so
        // draw/play gating (actionsThisTurn) matches a fresh turn until the
        // snapshot lands (mirrors [advanceTurn]).
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            currentPlayerId: e.newCurrentPlayerId,
            direction: e.direction,
            actionsThisTurn: 0,
            cardsPlayedThisTurn: 0,
            lastPlayedThisTurn: null,
            activeSkipCount: 0,
            queenSuitLock: null,
          ),
        );
      }),
    );

    // ── penalty_applied ─────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.penalties.listen((e) {
        if (state.gameState == null) return;
        if (_invalidPenaltySoundPlayed) {
          _invalidPenaltySoundPlayed = false;
          state = state.copyWith(
            gameState: state.gameState!.copyWith(
              activePenaltyCount: e.newPenaltyStack,
            ),
          );
          return;
        }
        if (e.cardsDrawn > 1) {
          unawaited(AudioService.instance.playSound(GameSound.penaltyDraw));
        }
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            activePenaltyCount: e.newPenaltyStack,
          ),
        );
      }),
    );

    // ── game_ended ──────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.events
          .where((e) => e is GameEndedEvent)
          .cast<GameEndedEvent>()
          .listen((e) {
        if (state.gameState == null) return;
        _drawSoundPlayedThisBatch = false;
        _cancelOpponentFlightWatchdog();
        _deferredSnapshots.clear();
        _opponentFlightsInFlight = 0;
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            phase: GamePhase.ended,
            winnerId: e.winnerId,
          ),
          rankedRatingChanges: e.ratingChanges,
          clearSocketDisconnected: true,
        );
      }),
    );

    // ── player_socket_lost / restored (transient disconnect vs grace expiry)
    _subs.add(
      _eventHandler.events
          .where((e) => e is PlayerSocketLostEvent)
          .cast<PlayerSocketLostEvent>()
          .listen((e) {
        if (state.gameState == null) return;
        state = state.copyWith(
          socketDisconnectedPlayerIds: {
            ...state.socketDisconnectedPlayerIds,
            e.playerId,
          },
        );
      }),
    );
    _subs.add(
      _eventHandler.events
          .where((e) => e is PlayerSocketRestoredEvent)
          .cast<PlayerSocketRestoredEvent>()
          .listen((e) {
        // If we just reconnected ourselves, clear all stale disconnect flags
        // — we may have missed PlayerSocketRestoredEvent for other players
        // while offline.
        final localId = state.gameState?.localPlayer?.id;
        if (localId != null && e.playerId == localId) {
          state = state.copyWith(clearSocketDisconnected: true);
          return;
        }
        if (!state.socketDisconnectedPlayerIds.contains(e.playerId)) return;
        final next = Set<String>.from(state.socketDisconnectedPlayerIds)
          ..remove(e.playerId);
        state = state.copyWith(socketDisconnectedPlayerIds: next);
      }),
    );

    _subs.add(
      _eventHandler.events
          .where((e) => e is PlayerLeftEvent)
          .cast<PlayerLeftEvent>()
          .listen((e) {
        if (!state.socketDisconnectedPlayerIds.contains(e.playerId)) return;
        final next = Set<String>.from(state.socketDisconnectedPlayerIds)
          ..remove(e.playerId);
        state = state.copyWith(socketDisconnectedPlayerIds: next);
      }),
    );

    // ── suit_choice_required ────────────────────────────────────────────────
    _subs.add(
      _eventHandler.suitChoiceRequired.listen((e) {
        state = state.copyWith(
          pendingSuitChoice: true,
          pendingSuitChoiceCardId: e.cardId,
        );
      }),
    );

    // ── joker_choice_required ───────────────────────────────────────────────
    _subs.add(
      _eventHandler.jokerChoiceRequired.listen((e) {
        state = state.copyWith(
          pendingJokerResolution: true,
          pendingJokerCardId: e.jokerCardId,
        );
      }),
    );

    // ── turn_timeout ────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.turnTimeouts.listen((e) {
        if (state.gameState == null) return;
        // Adjust draw pile count optimistically; the next state_snapshot will
        // provide the authoritative count.
        final drawn = e.cardsDrawn;
        if (drawn > 0) {
          state = state.copyWith(
            gameState: state.gameState!.copyWith(
              drawPileCount: (state.gameState!.drawPileCount - drawn)
                  .clamp(0, double.infinity)
                  .toInt(),
            ),
          );
        }
      }),
    );

    // ── reshuffle ───────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.reshuffles.listen((e) {
        if (state.gameState == null) return;
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            drawPileCount: e.newDrawPileCount,
            discardPileHistory: [],
          ),
        );
      }),
    );

    // ── session_config ──────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.sessionConfigs.listen((e) {
        final rc = e.roomCode;
        if (rc != null) {
          _onlineRejoin.setRoomCode(rc);
        }
        state = state.copyWith(
          isRanked: e.isRanked,
          isHardcoreSession: e.isHardcore,
          isPrivateSession: e.isPrivate,
          isBustSession: e.isBustMode,
          isKnockoutTournamentSession: e.isKnockoutTournament,
        );
      }),
    );

    // ── error ───────────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.errors.listen((e) {
        // Ignore parse/unknown errors that are not actionable by the player.
        if (e.code == 'parse_error' || e.code == 'unknown_event') return;
        state = state.copyWith(lastError: e.message);
      }),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  static const _sendFailedMessage =
      'Connection lost. Reconnecting — try again in a moment.';

  void playCards(List<String> cardIds, {String? declaredSuit}) {
    if (!_eventHandler.sendPlayCards(PlayCardsAction(
      cardIds: cardIds,
      declaredSuit:
          declaredSuit != null ? Suit.values.byName(declaredSuit) : null,
    ))) {
      state = state.copyWith(lastError: _sendFailedMessage);
    }
  }

  void drawCard() {
    if (!_eventHandler.sendDrawCard()) {
      state = state.copyWith(lastError: _sendFailedMessage);
    }
  }

  void declareJoker({
    required String jokerCardId,
    required String suitName,
    required String rankName,
  }) {
    // Clear the pending joker flag optimistically; the server will confirm
    // via the next state_snapshot.
    state = state.copyWith(clearJokerResolution: true);
    if (!_eventHandler.sendDeclareJoker(DeclareJokerAction(
      jokerCardId: jokerCardId,
      declaredSuit: Suit.values.byName(suitName),
      declaredRank: Rank.values.byName(rankName),
    ))) {
      state = state.copyWith(
        lastError: _sendFailedMessage,
        pendingJokerResolution: true,
        pendingJokerCardId: jokerCardId,
      );
    }
  }

  void declareSuit(String suitName) {
    final aceCardId = state.pendingSuitChoiceCardId;
    // Clear the pending suit-choice flag optimistically.
    state = state.copyWith(clearSuitChoice: true);
    if (!_eventHandler.sendSuitChoice(
      SuitChoiceAction(suit: Suit.values.byName(suitName)),
    )) {
      state = state.copyWith(
        lastError: _sendFailedMessage,
        pendingSuitChoice: true,
        pendingSuitChoiceCardId: aceCardId,
      );
    }
  }

  void endTurn() {
    if (!_eventHandler.sendEndTurn()) {
      state = state.copyWith(lastError: _sendFailedMessage);
    }
  }

  void declareLastCards() {
    if (!_eventHandler.sendDeclareLastCards()) {
      state = state.copyWith(lastError: _sendFailedMessage);
    }
  }

  /// Clears the last error so the UI can dismiss an error banner.
  void clearError() => state = state.copyWith(clearError: true);

  /// When a non-game action (e.g. quick chat) could not be sent over the socket.
  void connectionSendFailed() {
    state = state.copyWith(lastError: _sendFailedMessage);
  }

  /// Clears all online game state. Call when the user leaves an online game
  /// so that the next TableScreen (e.g. single player) does not inherit stale
  /// ranked/online state.
  void clearOnlineState() {
    _drawSoundPlayedThisBatch = false;
    _suppressCardDrawSoundByPlayerId.clear();
    _invalidPenaltySoundPlayed = false;
    _opponentFlightsInFlight = 0;
    _deferredSnapshots.clear();
    _cancelOpponentFlightWatchdog();
    _onlineRejoin.clear();
    state = const GameNotifierState();
  }

  @override
  void dispose() {
    _cancelOpponentFlightWatchdog();
    _deferredSnapshots.clear();
    _suppressCardDrawSoundByPlayerId.clear();
    _opponentFlightsInFlight = 0;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final gameNotifierProvider =
    StateNotifierProvider<GameNotifier, GameNotifierState>((ref) {
  final handler = ref.watch(gameEventHandlerProvider);
  final rejoin = ref.read(onlineRejoinProvider.notifier);
  return GameNotifier(handler, rejoin);
});

/// Convenience selector — the current game state (may be null before connect).
final gameStateProvider = Provider<GameState?>((ref) {
  return ref.watch(gameNotifierProvider).gameState;
});

/// Whether it's the local player's turn.
final isLocalTurnProvider = Provider<bool>((ref) {
  return ref.watch(gameStateProvider)?.isLocalPlayerTurn ?? false;
});

/// Active penalty count for the HUD badge.
final penaltyCountProvider = Provider<int>((ref) {
  return ref.watch(gameStateProvider)?.activePenaltyCount ?? 0;
});

/// True while the server is waiting for the local player to pick a suit
/// (after an Ace play). The UI should show a suit picker when this is true.
final pendingSuitChoiceProvider = Provider<bool>((ref) {
  return ref.watch(gameNotifierProvider).pendingSuitChoice;
});

/// Card ID of the Ace that triggered the pending suit choice, or null.
final pendingSuitChoiceCardIdProvider = Provider<String?>((ref) {
  return ref.watch(gameNotifierProvider).pendingSuitChoiceCardId;
});

/// True while the server is waiting for the local player to declare a Joker.
/// The UI should show a joker picker when this is true.
final pendingJokerResolutionProvider = Provider<bool>((ref) {
  return ref.watch(gameNotifierProvider).pendingJokerResolution;
});

/// Card ID of the Joker awaiting declaration, or null.
final pendingJokerCardIdProvider = Provider<String?>((ref) {
  return ref.watch(gameNotifierProvider).pendingJokerCardId;
});

/// Most recent server error message for the local player, or null.
/// Call [GameNotifier.clearError] to dismiss.
final gameErrorProvider = Provider<String?>((ref) {
  return ref.watch(gameNotifierProvider).lastError;
});

/// Per-player rating deltas from the most recent ranked game, or null.
/// Key is server player ID; value is the rating delta (+25/-15).
final rankedRatingChangesProvider = Provider<Map<String, int>?>((ref) {
  return ref.watch(gameNotifierProvider).rankedRatingChanges;
});

/// True when the current online session is a ranked match (from session_config).
final isRankedGameProvider = Provider<bool>((ref) {
  return ref.watch(gameNotifierProvider).isRanked;
});
