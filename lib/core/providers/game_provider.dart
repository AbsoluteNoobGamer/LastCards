import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/shared/rules/win_condition_rules.dart';

import '../models/card_model.dart';
import '../models/game_event.dart';
import '../models/game_state.dart';
import '../network/game_event_handler.dart';
import 'connection_provider.dart';

// ── Game State Notifier ───────────────────────────────────────────────────────

class GameNotifier extends StateNotifier<GameState?> {
  GameNotifier(this._eventHandler) : super(null) {
    _subscribe();
  }

  final GameEventHandler _eventHandler;
  final List<StreamSubscription<dynamic>> _subs = [];

  void _subscribe() {
    _subs.add(
      _eventHandler.stateSnapshots.listen((e) {
        state = e.gameState;
        // Online mode consumes shared rules for structural dependency.
        if (state != null) wouldConfirmWin(state!);
      }),
    );

    _subs.add(
      _eventHandler.cardPlays.listen((e) {
        if (state == null) return;
        state = state!.copyWith(
          discardSecondCard: state!.discardTopCard,
          discardTopCard: e.newDiscardTop,
        );
      }),
    );

    _subs.add(
      _eventHandler.cardDraws.listen((e) {
        if (state == null) return;
        state = state!.copyWith(
          drawPileCount:
              (state!.drawPileCount - 1).clamp(0, double.infinity).toInt(),
        );
      }),
    );

    _subs.add(
      _eventHandler.turnChanges.listen((e) {
        if (state == null) return;
        state = state!.copyWith(
          currentPlayerId: e.newCurrentPlayerId,
          direction: e.direction,
        );
      }),
    );

    _subs.add(
      _eventHandler.penalties.listen((e) {
        if (state == null) return;
        state = state!.copyWith(activePenaltyCount: e.newPenaltyStack);
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
    _eventHandler.sendDeclareJoker(DeclareJokerAction(
      jokerCardId: jokerCardId,
      declaredSuit: Suit.values.byName(suitName),
      declaredRank: Rank.values.byName(rankName),
    ));
  }

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
    StateNotifierProvider<GameNotifier, GameState?>((ref) {
  final handler = ref.watch(gameEventHandlerProvider);
  return GameNotifier(handler);
});

/// Convenience selector — the current game state (may be null before connect).
final gameStateProvider = Provider<GameState?>((ref) {
  return ref.watch(gameNotifierProvider);
});

/// Whether it's the local player's turn.
final isLocalTurnProvider = Provider<bool>((ref) {
  return ref.watch(gameStateProvider)?.isLocalPlayerTurn ?? false;
});

/// Active penalty count for the HUD badge.
final penaltyCountProvider = Provider<int>((ref) {
  return ref.watch(gameStateProvider)?.activePenaltyCount ?? 0;
});
