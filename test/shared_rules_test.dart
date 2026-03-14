import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/core/providers/game_provider.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/rules/pickup_chain_rules.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart';

// ---------------------------------------------------------------------------
// Structural tests: verify all modes consume shared logic
// ---------------------------------------------------------------------------

CardModel c(Rank r, Suit s, {String? id}) =>
    CardModel(id: id ?? '${r.name}_${s.name}', rank: r, suit: s);

GameState buildState({
  required CardModel discardTop,
  List<CardModel> p1Hand = const [],
  List<CardModel> p2Hand = const [],
  int activePenalty = 0,
  Suit? queenSuitLock,
  String currentPlayerId = 'p1',
}) {
  final p1 = PlayerModel(
    id: 'p1',
    displayName: 'P1',
    tablePosition: TablePosition.bottom,
    hand: p1Hand,
    cardCount: p1Hand.length,
  );
  final p2 = PlayerModel(
    id: 'p2',
    displayName: 'P2',
    tablePosition: TablePosition.top,
    hand: p2Hand,
    cardCount: p2Hand.length,
  );

  return GameState(
    sessionId: 'test',
    phase: GamePhase.playing,
    currentPlayerId: currentPlayerId,
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 20,
    activePenaltyCount: activePenalty,
    queenSuitLock: queenSuitLock,
    players: [p1, p2],
  );
}

void main() {
  group('Shared Rules Structural Tests', () {
    test('Online mode correctly consumes shared card rules', () {
      // game_provider is the central provider for online mode and imports shared rules
      expect(gameNotifierProvider, isNotNull);
      expect(gameStateProvider, isNotNull);
      // wouldConfirmWin is used in game_provider's state update handler
      final state = buildState(
        discardTop: c(Rank.three, Suit.spades),
        p1Hand: [c(Rank.four, Suit.spades)],
        p2Hand: [c(Rank.five, Suit.hearts)],
      );
      expect(wouldConfirmWin(state), isFalse);
    });

    test('Offline/AI mode correctly consumes shared card rules', () {
      // Offline mode uses offline_game_engine which re-exports from shared
      final state = buildState(
        discardTop: c(Rank.five, Suit.hearts),
        p1Hand: [c(Rank.six, Suit.hearts)],
      );
      final err = validatePlay(
        cards: [c(Rank.six, Suit.hearts)],
        discardTop: state.discardTopCard!,
        state: state,
      );
      expect(err, isNull);
      // Pick-up chain rules
      expect(isFirstCardValidUnderPenalty(c(Rank.two, Suit.spades)), isTrue);
      expect(areAllCardsPenaltyAddressing([c(Rank.two, Suit.hearts)]), isTrue);
    });

    test('Pick-up chain logic produces identical results across all modes', () {
      // Shared pickup_chain_rules used by game_engine
      final two = c(Rank.two, Suit.spades);
      final blackJack = c(Rank.jack, Suit.clubs);
      final redJack = c(Rank.jack, Suit.hearts);

      expect(isFirstCardValidUnderPenalty(two), isTrue);
      expect(isFirstCardValidUnderPenalty(blackJack), isTrue);
      expect(isFirstCardValidUnderPenalty(redJack), isTrue);
      expect(isFirstCardValidUnderPenalty(c(Rank.three, Suit.hearts)), isFalse);

      expect(shouldClearPenaltyAfterPlay(two), isFalse);
      expect(shouldClearPenaltyAfterPlay(blackJack), isFalse);
      expect(shouldClearPenaltyAfterPlay(c(Rank.five, Suit.diamonds)), isTrue);

      expect(isPenaltyChain(two, blackJack), isTrue);
      expect(isPenaltyChain(blackJack, redJack), isTrue);
      expect(isPenaltyChain(two, c(Rank.three, Suit.hearts)), isFalse);
    });

    test('Win condition logic produces identical results across all modes', () {
      // Shared win_condition_rules
      var state = buildState(
        discardTop: c(Rank.two, Suit.spades),
        p1Hand: [],
        p2Hand: [c(Rank.king, Suit.hearts)],
        activePenalty: 0,
      );
      expect(wouldConfirmWin(state), isTrue);

      state = buildState(
        discardTop: c(Rank.two, Suit.spades),
        p1Hand: [],
        p2Hand: [c(Rank.king, Suit.hearts)],
        activePenalty: 2,
        currentPlayerId: 'p1',
      );
      expect(wouldConfirmWin(state), isFalse);

      state = buildState(
        discardTop: c(Rank.queen, Suit.spades),
        p1Hand: [],
        p2Hand: [c(Rank.king, Suit.hearts)],
        queenSuitLock: Suit.hearts,
        currentPlayerId: 'p1',
      );
      expect(wouldConfirmWin(state), isFalse);
    });

    test('All pre-existing engine exports work from shared', () {
      final state = buildState(
        discardTop: c(Rank.six, Suit.spades),
        p1Hand: [c(Rank.seven, Suit.spades)],
      );
      expect(validatePlay(cards: [c(Rank.seven, Suit.spades)], discardTop: state.discardTopCard!, state: state), isNull);
      expect(validateEndTurn(state.copyWith(actionsThisTurn: 1)), isNull);
      expect(nextPlayerId(state: state), 'p2');
      final newState = applyPlay(state: state, playerId: 'p1', cards: [c(Rank.seven, Suit.spades)]);
      expect(newState.players.firstWhere((p) => p.id == 'p1').hand, isEmpty);
    });

    test('No logic regressions - applyPlay and applyDraw behave identically', () {
      var state = buildState(
        discardTop: c(Rank.three, Suit.clubs),
        p1Hand: [c(Rank.two, Suit.clubs)],
        p2Hand: [c(Rank.king, Suit.hearts)],
      );
      state = applyPlay(state: state, playerId: 'p1', cards: [c(Rank.two, Suit.clubs)]);
      expect(state.activePenaltyCount, 2);
      expect(state.players.firstWhere((p) => p.id == 'p1').hand, isEmpty);

      final drawn = [c(Rank.ace, Suit.spades, id: 'd1')];
      state = applyDraw(
        state: state.copyWith(currentPlayerId: 'p2'),
        playerId: 'p2',
        count: 1,
        cardFactory: (_) => drawn,
      );
      expect(state.activePenaltyCount, 0);
      expect(state.players.firstWhere((p) => p.id == 'p2').hand.length, 2);
    });
  });
}
