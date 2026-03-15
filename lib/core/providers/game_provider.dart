import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/services/audio_service.dart';
import 'package:last_cards/services/game_sound.dart' show GameSound, soundForCard;
import 'package:last_cards/shared/rules/win_condition_rules.dart';

import '../models/card_model.dart';
import '../models/game_event.dart';
import '../models/game_state.dart';
import '../network/game_event_handler.dart';
import 'connection_provider.dart';

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
  });

  /// The authoritative server game state. Null until the first snapshot arrives.
  final GameState? gameState;

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

  GameNotifierState copyWith({
    GameState? gameState,
    bool? pendingSuitChoice,
    String? pendingSuitChoiceCardId,
    bool? pendingJokerResolution,
    String? pendingJokerCardId,
    String? lastError,
    Map<String, int>? rankedRatingChanges,
    bool? isRanked,
    bool clearError = false,
    bool clearSuitChoice = false,
    bool clearJokerResolution = false,
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
    );
  }
}

// ── Game State Notifier ───────────────────────────────────────────────────────

class GameNotifier extends StateNotifier<GameNotifierState> {
  GameNotifier(this._eventHandler) : super(const GameNotifierState()) {
    _subscribe();
  }

  final GameEventHandler _eventHandler;
  final List<StreamSubscription<dynamic>> _subs = [];

  // Convenience getter so callers that only need GameState? don't change.
  GameState? get gameState => state.gameState;

  void _subscribe() {
    // ── state_snapshot ──────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.stateSnapshots.listen((e) {
        // A fresh snapshot from the server is authoritative — clear any
        // pending UI flags that the snapshot implicitly resolves, and clear
        // any stale error.
        //
        // Clear pendingSuitChoice when:
        //   • There is no pending joker resolution (unrelated flow), AND
        //   • Either the flag isn't set, OR the turn has moved on (the player
        //     who triggered the suit choice is no longer current — the server
        //     timed them out or they responded via declareSuit).
        final suitChoiceResolved = state.pendingSuitChoice &&
            state.gameState != null &&
            e.gameState.currentPlayerId != state.gameState!.currentPlayerId;
        state = state.copyWith(
          gameState: e.gameState,
          clearError: true,
          clearSuitChoice: !e.gameState.pendingJokerResolution &&
              (!state.pendingSuitChoice || suitChoiceResolved),
        );
        // Online mode consumes shared rules for structural dependency.
        wouldConfirmWin(e.gameState);
      }),
    );

    // ── card_played ─────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.cardPlays.listen((e) {
        if (state.gameState == null) return;
        // Every card uses card_place.wav; special cards also get their effect sound.
        for (final card in e.cards) {
          unawaited(AudioService.instance.playSound(GameSound.cardPlace));
          final s = soundForCard(card);
          if (s != null) unawaited(AudioService.instance.playSound(s));
        }
        // Eight played → skip effect incoming
        if (e.cards.any((c) => c.effectiveRank == Rank.eight)) {
          unawaited(AudioService.instance.playSound(GameSound.skipApplied));
        }
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            discardPileHistory: [
              if (state.gameState!.discardTopCard != null)
                state.gameState!.discardTopCard!,
              ...state.gameState!.discardPileHistory,
            ].take(5).toList(),
            discardTopCard: e.newDiscardTop,
          ),
        );
      }),
    );

    // ── card_drawn ──────────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.cardDraws.listen((e) {
        if (state.gameState == null) return;
        unawaited(AudioService.instance.playSound(GameSound.cardDraw));
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
        if (e.direction != state.gameState!.direction) {
          unawaited(
              AudioService.instance.playSound(GameSound.directionReversed));
        }
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            currentPlayerId: e.newCurrentPlayerId,
            direction: e.direction,
          ),
        );
      }),
    );

    // ── penalty_applied ─────────────────────────────────────────────────────
    _subs.add(
      _eventHandler.penalties.listen((e) {
        if (state.gameState == null) return;
        unawaited(AudioService.instance.playSound(GameSound.penaltyDraw));
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
        state = state.copyWith(
          gameState: state.gameState!.copyWith(
            phase: GamePhase.ended,
            winnerId: e.winnerId,
          ),
          rankedRatingChanges: e.ratingChanges,
        );
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
        state = state.copyWith(isRanked: e.isRanked);
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

  void playCards(List<String> cardIds, {String? declaredSuit}) {
    _eventHandler.sendPlayCards(PlayCardsAction(
      cardIds: cardIds,
      declaredSuit:
          declaredSuit != null ? Suit.values.byName(declaredSuit) : null,
    ));
  }

  void drawCard() => _eventHandler.sendDrawCard();

  void declareJoker({
    required String jokerCardId,
    required String suitName,
    required String rankName,
  }) {
    // Clear the pending joker flag optimistically; the server will confirm
    // via the next state_snapshot.
    state = state.copyWith(clearJokerResolution: true);
    _eventHandler.sendDeclareJoker(DeclareJokerAction(
      jokerCardId: jokerCardId,
      declaredSuit: Suit.values.byName(suitName),
      declaredRank: Rank.values.byName(rankName),
    ));
  }

  void declareSuit(String suitName) {
    // Clear the pending suit-choice flag optimistically.
    state = state.copyWith(clearSuitChoice: true);
    _eventHandler.sendSuitChoice(
      SuitChoiceAction(suit: Suit.values.byName(suitName)),
    );
  }

  void endTurn() => _eventHandler.sendEndTurn();

  /// Clears the last error so the UI can dismiss an error banner.
  void clearError() => state = state.copyWith(clearError: true);

  /// Clears all online game state. Call when the user leaves an online game
  /// so that the next TableScreen (e.g. single player) does not inherit stale
  /// ranked/online state.
  void clearOnlineState() => state = const GameNotifierState();

  @override
  void dispose() {
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
  return GameNotifier(handler);
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
