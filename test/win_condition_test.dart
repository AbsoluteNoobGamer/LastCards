import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/core/models/card_model.dart';
import 'package:stack_and_flow/core/models/offline_game_engine.dart';
import 'package:stack_and_flow/core/models/game_state.dart';
import 'package:stack_and_flow/core/models/player_model.dart';
import 'package:stack_and_flow/shared/rules/win_condition_rules.dart';

// ---------------------------------------------------------------------------
// Helpers — mirrors the style in engine_test.dart
// ---------------------------------------------------------------------------

CardModel c(Rank r, Suit s, {String? id}) =>
    CardModel(id: id ?? '${r.name}_${s.name}', rank: r, suit: s);

CardModel joker(Suit s, {String? id}) =>
    CardModel(id: id ?? 'joker_${s.name}', rank: Rank.joker, suit: s);

/// Builds a two-player GameState with p1 as current player.
GameState buildState({
  required CardModel discardTop,
  List<CardModel> p1Hand = const [],
  List<CardModel> p2Hand = const [],
  int activePenalty = 0,
  Suit? queenSuitLock,
}) {
  final p1 = PlayerModel(
    id: 'p1',
    displayName: 'P1',
    tablePosition: TablePosition.bottom,
    hand: p1Hand,
    cardCount: p1Hand.length,
    isConnected: true,
    isActiveTurn: true,
    isSkipped: false,
  );
  final p2 = PlayerModel(
    id: 'p2',
    displayName: 'P2',
    tablePosition: TablePosition.top,
    hand: p2Hand,
    cardCount: p2Hand.length,
    isConnected: true,
    isActiveTurn: false,
    isSkipped: false,
  );

  return GameState(
    sessionId: 'test',
    phase: GamePhase.playing,
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 20,
    activePenaltyCount: activePenalty,
    queenSuitLock: queenSuitLock,
    lastUpdatedAt: 0,
    players: [p1, p2],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Win Condition Deferral', () {
    // ── Test 1 ───────────────────────────────────────────────────────────────
    test(
        'lastPickupCard_two_doesNotImmediatelyTriggerWin',
        () {
      // Scenario: P1 plays their last card — a 2 — as the discard top.
      // activePenaltyCount is 2 (just added by the 2).
      // P1's hand is now empty. The chain is still live.
      // _checkWin must NOT confirm the win.

      var state = buildState(
        discardTop: c(Rank.three, Suit.spades),
        p1Hand: [c(Rank.two, Suit.spades)], // only card
        p2Hand: [c(Rank.king, Suit.hearts)],
      );

      // P1 plays their only card (a 2 → penalty +2)
      state = applyPlay(state: state, playerId: 'p1', cards: [c(Rank.two, Suit.spades)]);

      // Hand should now be empty but penalty chain is live
      final p1 = state.players.firstWhere((p) => p.id == 'p1');
      expect(p1.hand, isEmpty, reason: 'P1 hand must be empty after playing their last card');
      expect(state.activePenaltyCount, 2, reason: 'Playing a 2 adds 2 to the penalty count');

      // Win must be deferred — chain not yet resolved
      expect(
        wouldConfirmWin(state),
        isFalse,
        reason: 'A player cannot win immediately by playing a 2 as their last card; '
            'the pick-up chain must resolve first',
      );
    });

    // ── Test 2 ───────────────────────────────────────────────────────────────
    test(
        'lastPickupCard_blackJack_doesNotImmediatelyTriggerWin',
        () {
      // Scenario: P1 plays their last card — a Black Jack — as the discard top.
      // activePenaltyCount is 5 (just added by the Black Jack).
      // _checkWin must NOT confirm the win.

      var state = buildState(
        discardTop: c(Rank.three, Suit.spades),
        p1Hand: [c(Rank.jack, Suit.spades)], // Black Jack — only card
        p2Hand: [c(Rank.king, Suit.hearts)],
      );

      expect(
        c(Rank.jack, Suit.spades).isBlackJack,
        isTrue,
        reason: 'J♠ must be identified as a Black Jack',
      );

      state = applyPlay(state: state, playerId: 'p1', cards: [c(Rank.jack, Suit.spades)]);

      final p1 = state.players.firstWhere((p) => p.id == 'p1');
      expect(p1.hand, isEmpty, reason: 'P1 hand must be empty after playing their last card');
      expect(state.activePenaltyCount, 5, reason: 'Black Jack adds 5 to the penalty count');

      expect(
        wouldConfirmWin(state),
        isFalse,
        reason: 'A player cannot win immediately by playing a Black Jack as their last card',
      );
    });

    // ── Test 3 ───────────────────────────────────────────────────────────────
    test(
        'winConfirmedAfterChainResolvesPlayerStillOnZero',
        () {
      // Scenario: P1 played a 2 as their last card (chain active, win deferred).
      // P2 cannot counter and draws — chain is cleared (activePenaltyCount = 0).
      // P1 still has zero cards. Win must now be confirmed.

      // Simulate the state AFTER the chain has fully resolved:
      //   • P1: no cards
      //   • activePenaltyCount: 0 (chain exhausted — P2 drew and cleared it)
      //   • currentPlayerId is P1 again (or checking from P2's turn doesn't matter;
      //     the guard only blocks if winner.id == currentPlayerId AND penalty > 0)
      //
      // Use P2 as currentPlayer to represent that the draw happened on P2's turn
      // and the turn advanced back — but it is now P1's turn again (or can be checked
      // from the perspective of P1 having won after P2's resolution).
      //
      // The simplest model: after the chain resolves, we check again.
      // activePenaltyCount == 0, P1 hand empty → win confirmed immediately.

      final state = buildState(
        discardTop: c(Rank.two, Suit.spades),
        p1Hand: [], // P1 already empty
        p2Hand: [c(Rank.king, Suit.hearts), c(Rank.five, Suit.clubs)], // P2 drew cards
        activePenalty: 0, // Chain fully resolved — P2 drew the penalty cards
      );

      // Confirm P1 is still on zero cards
      final p1 = state.players.firstWhere((p) => p.id == 'p1');
      expect(p1.hand, isEmpty);
      expect(state.activePenaltyCount, 0, reason: 'Chain is resolved (count = 0)');

      // Win must NOW be confirmed
      expect(
        wouldConfirmWin(state),
        isTrue,
        reason: 'After the chain resolves with P1 still on zero cards, the win must be confirmed',
      );
    });

    // ── Test 4 ───────────────────────────────────────────────────────────────
    test(
        'playerForcedToDrawFromChainLosesWin',
        () {
      // Scenario: P1 played their last card (a 2), penalty count = 2.
      // P2 counters with another 2 → count = 4.
      // Chain comes back to P1; P1 has no counter → must draw 4 cards.
      // After drawing, P1 is no longer on zero cards → win does not happen.

      // Start: P1 has played their last card (a 2). State right after applyPlay:

      var state = buildState(
        discardTop: c(Rank.three, Suit.clubs),
        p1Hand: [c(Rank.two, Suit.clubs)], // P1's only remaining card
        // Give P2 extra cards so P2 does not accidentally win when its counter is played
        p2Hand: [c(Rank.two, Suit.hearts), c(Rank.king, Suit.clubs), c(Rank.five, Suit.diamonds)],
      );

      // P1 plays their last card (2♣)
      state = applyPlay(state: state, playerId: 'p1', cards: [c(Rank.two, Suit.clubs)]);
      expect(state.activePenaltyCount, 2);
      expect(state.players.firstWhere((p) => p.id == 'p1').hand, isEmpty);

      // Win is deferred (chain live)
      expect(wouldConfirmWin(state), isFalse,
          reason: 'Win must be deferred while chain is active');

      // P2 counters with 2♥ → chain grows to 4, turn advances
      final stateAfterP2Counter = state.copyWith(
        currentPlayerId: 'p2',
        activePenaltyCount: 2, // already at 2 from P1's 2
      );
      final stateP2Played = applyPlay(
        state: stateAfterP2Counter,
        playerId: 'p2',
        cards: [c(Rank.two, Suit.hearts)],
      );
      expect(stateP2Played.activePenaltyCount, 4,
          reason: 'P2 counters: chain grows to 4');

      // Chain comes back to P1 — P1 must now draw the accumulated 4 cards
      // and has no counter (hand was empty). Use applyDraw to simulate the draw.
      final drawnCards = [
        c(Rank.nine, Suit.hearts, id: 'drawn1'),
        c(Rank.ten, Suit.spades, id: 'drawn2'),
        c(Rank.six, Suit.clubs, id: 'drawn3'),
        c(Rank.seven, Suit.diamonds, id: 'drawn4'),
      ];

      final stateAfterDraw = applyDraw(
        state: stateP2Played.copyWith(currentPlayerId: 'p1'),
        playerId: 'p1',
        count: 4,
        cardFactory: (_) => drawnCards,
      );

      // P1 now has cards again — win must NOT happen
      final p1AfterDraw =
          stateAfterDraw.players.firstWhere((p) => p.id == 'p1');
      expect(p1AfterDraw.hand, isNotEmpty,
          reason: 'P1 has drawn cards — hand is no longer empty');
      expect(stateAfterDraw.activePenaltyCount, 0,
          reason: 'applyDraw clears activePenaltyCount');

      expect(
        wouldConfirmWin(stateAfterDraw.copyWith(currentPlayerId: 'p1')),
        isFalse,
        reason: 'P1 is no longer on zero cards — win did not happen',
      );
    });
  });
}
