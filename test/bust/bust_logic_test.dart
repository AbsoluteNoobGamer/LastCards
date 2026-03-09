// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/features/bust/bust_engine.dart';
import 'package:last_cards/features/bust/bust_round_manager.dart';
import 'package:last_cards/features/bust/models/bust_round_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

CardModel card(Rank r, Suit s) =>
    CardModel(id: '${r.name}_${s.name}', rank: r, suit: s);

/// Builds a minimal [BustRoundManager] for [playerIds] with [firstId] going first.
BustRoundManager makeManager(List<String> playerIds, String firstId) =>
    BustRoundManager(
      initialActivePlayerIds: playerIds,
      firstPlayerId: firstId,
    );

// ─────────────────────────────────────────────────────────────────────────────
// 1. BustEngine — deck & deal
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('BustEngine.buildShuffledDeck', () {
    test('produces exactly 52 cards', () {
      final deck = BustEngine.buildShuffledDeck(seed: 1);
      expect(deck.length, 52);
    });

    test('contains no Jokers', () {
      final deck = BustEngine.buildShuffledDeck(seed: 2);
      expect(deck.any((c) => c.isJoker), isFalse);
    });

    test('contains all 4 suits × 13 ranks', () {
      final deck = BustEngine.buildShuffledDeck(seed: 3);
      for (final suit in Suit.values) {
        for (final rank in Rank.values.where((r) => r != Rank.joker)) {
          expect(
            deck.any((c) => c.suit == suit && c.rank == rank),
            isTrue,
            reason: 'Missing $rank of $suit',
          );
        }
      }
    });

    test('same seed produces same deck order', () {
      final a = BustEngine.buildShuffledDeck(seed: 42);
      final b = BustEngine.buildShuffledDeck(seed: 42);
      expect(a.map((c) => c.id).toList(), b.map((c) => c.id).toList());
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. BustEngine.handSizeFor
  // ─────────────────────────────────────────────────────────────────────────

  group('BustEngine.handSizeFor', () {
    test('2–5 players → 10 cards each', () {
      for (final n in [2, 3, 4, 5]) {
        expect(BustEngine.handSizeFor(n), 10, reason: '$n players');
      }
    });

    test('6 players → 8 cards', () => expect(BustEngine.handSizeFor(6), 8));
    test('7 players → 7 cards', () => expect(BustEngine.handSizeFor(7), 7));
    test('8 players → 6 cards', () => expect(BustEngine.handSizeFor(8), 6));
    test('9 players → 5 cards', () => expect(BustEngine.handSizeFor(9), 5));
    test('10 players → 5 cards', () => expect(BustEngine.handSizeFor(10), 5));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. BustEngine.buildRound
  // ─────────────────────────────────────────────────────────────────────────

  group('BustEngine.buildRound', () {
    for (final n in [2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      test('$n players: correct player count and hand sizes', () {
        final (:gameState, :drawPile) =
            BustEngine.buildRound(playerCount: n, seed: n);
        expect(gameState.players.length, n);
        final handSize = BustEngine.handSizeFor(n);
        for (final p in gameState.players) {
          expect(p.hand.length, handSize,
              reason: '${p.id} should have $handSize cards');
        }
      });
    }

    test('local player is always present', () {
      final (:gameState, :drawPile) =
          BustEngine.buildRound(playerCount: 5, seed: 7);
      expect(
        gameState.players.any((p) => p.id == OfflineGameState.localId),
        isTrue,
      );
    });

    test('draw pile + hands + discard = 52 cards', () {
      for (final n in [5, 7, 10]) {
        final (:gameState, :drawPile) =
            BustEngine.buildRound(playerCount: n, seed: n * 3);
        final handCards =
            gameState.players.fold<int>(0, (s, p) => s + p.hand.length);
        expect(handCards + drawPile.length + 1, 52,
            reason: '$n players: card count mismatch');
      }
    });

    test('exactly one player has isActiveTurn = true', () {
      final (:gameState, :drawPile) =
          BustEngine.buildRound(playerCount: 6, seed: 99);
      final active = gameState.players.where((p) => p.isActiveTurn).toList();
      expect(active.length, 1);
      expect(active.first.id, gameState.currentPlayerId);
    });

    test('assert fires for playerCount < 2', () {
      expect(
        () => BustEngine.buildRound(playerCount: 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert fires for playerCount > 10', () {
      expect(
        () => BustEngine.buildRound(playerCount: 11),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. BustEngine.applyPlacementPileRule
  // ─────────────────────────────────────────────────────────────────────────

  group('BustEngine.applyPlacementPileRule', () {
    test('no reshuffle when discard < threshold', () {
      final discard = [card(Rank.two, Suit.hearts), card(Rank.three, Suit.clubs)];
      final draw = [card(Rank.four, Suit.spades)];
      final result = BustEngine.applyPlacementPileRule(
        discardPile: discard,
        drawPile: draw,
        threshold: 5,
      );
      expect(result.didReshuffle, isFalse);
      expect(result.newDrawPile.length, draw.length);
    });

    test('reshuffles when discard == threshold', () {
      final discard = List.generate(
          5, (i) => card(Rank.values[i + 2], Suit.hearts));
      final draw = <CardModel>[];
      final result = BustEngine.applyPlacementPileRule(
        discardPile: discard,
        drawPile: draw,
        threshold: 5,
        seed: 1,
      );
      expect(result.didReshuffle, isTrue);
      // 4 cards shuffled back (top card stays on discard, managed by caller)
      expect(result.newDrawPile.length, 4);
    });

    test('needsPlacementPileReshuffle returns correct boolean', () {
      final four = List.generate(4, (i) => card(Rank.values[i + 2], Suit.clubs));
      final five = List.generate(5, (i) => card(Rank.values[i + 2], Suit.clubs));
      expect(BustEngine.needsPlacementPileReshuffle(four), isFalse);
      expect(BustEngine.needsPlacementPileReshuffle(five), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. BustRoundState derived helpers
  // ─────────────────────────────────────────────────────────────────────────

  group('BustRoundState derived helpers', () {
    test('turnsPerRound = playerCount × 2', () {
      final state = BustRoundState(
        roundNumber: 1,
        activePlayerIds: const ['a', 'b', 'c'],
        eliminatedIds: const [],
        turnsThisRound: const {'a': 0, 'b': 0, 'c': 0},
        penaltyPoints: const {'a': 0, 'b': 0, 'c': 0},
        playerOrder: const ['a', 'b', 'c'],
      );
      expect(state.turnsPerRound, 6);
    });

    test('isRoundComplete is false when not all players have 2 turns', () {
      final state = BustRoundState(
        roundNumber: 1,
        activePlayerIds: const ['a', 'b'],
        eliminatedIds: const [],
        turnsThisRound: const {'a': 2, 'b': 1},
        penaltyPoints: const {},
        playerOrder: const ['a', 'b'],
      );
      expect(state.isRoundComplete, isFalse);
    });

    test('isRoundComplete is true when all players have >= 2 turns', () {
      final state = BustRoundState(
        roundNumber: 1,
        activePlayerIds: const ['a', 'b'],
        eliminatedIds: const [],
        turnsThisRound: const {'a': 2, 'b': 2},
        penaltyPoints: const {},
        playerOrder: const ['a', 'b'],
      );
      expect(state.isRoundComplete, isTrue);
    });

    test('currentRotation reflects turns taken', () {
      final twoPlayers = ['a', 'b'];
      var state = BustRoundState(
        roundNumber: 1,
        activePlayerIds: twoPlayers,
        eliminatedIds: const [],
        turnsThisRound: const {'a': 0, 'b': 0},
        penaltyPoints: const {},
        playerOrder: twoPlayers,
      );
      expect(state.currentRotation, 1);

      state = state.copyWith(turnsThisRound: {'a': 1, 'b': 1});
      expect(state.currentRotation, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. BustRoundManager.recordTurn
  // ─────────────────────────────────────────────────────────────────────────

  group('BustRoundManager.recordTurn', () {
    test('increments turn count for valid player', () {
      final mgr = makeManager(['a', 'b', 'c'], 'a');
      mgr.recordTurn('a');
      expect(mgr.state.turnsThisRound['a'], 1);
      expect(mgr.state.turnsThisRound['b'], 0);
    });

    test('does nothing for unknown player', () {
      final mgr = makeManager(['a', 'b'], 'a');
      mgr.recordTurn('z');
      expect(mgr.state.turnsThisRound['a'], 0);
      expect(mgr.state.turnsThisRound['b'], 0);
    });

    test('does nothing once round is complete', () {
      final mgr = makeManager(['a', 'b'], 'a');
      // Give everyone 2 turns
      mgr.recordTurn('a'); mgr.recordTurn('a');
      mgr.recordTurn('b'); mgr.recordTurn('b');
      expect(mgr.state.isRoundComplete, isTrue);

      // Extra call should be ignored
      mgr.recordTurn('a');
      expect(mgr.state.turnsThisRound['a'], 2);
    });

    test('round completes after every player has 2 turns', () {
      final ids = ['p1', 'p2', 'p3'];
      final mgr = makeManager(ids, 'p1');
      for (final id in ids) {
        mgr.recordTurn(id);
        mgr.recordTurn(id);
      }
      expect(mgr.state.isRoundComplete, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. BustRoundManager.finalizeRound — elimination logic
  // ─────────────────────────────────────────────────────────────────────────

  group('BustRoundManager.finalizeRound', () {
    /// Builds a GameState for finalizeRound using real BustEngine.buildRound
    /// then replaces player hands with custom card counts.
    GameState stateWithCardCounts(Map<String, int> cardCounts) {
      final playerIds = cardCounts.keys.toList();
      final n = playerIds.length;
      final (:gameState, :drawPile) =
          BustEngine.buildRound(playerCount: n, seed: 0);

      // Replace each player's hand with the desired count of dummy cards
      final updatedPlayers = gameState.players.map((p) {
        final count = cardCounts[p.id] ?? 0;
        final hand = List.generate(
          count,
          (i) => card(Rank.values[(i % 13) + 1], Suit.hearts),
        );
        return p.copyWith(hand: hand, cardCount: count);
      }).toList();

      return gameState.copyWith(players: updatedPlayers);
    }

    test('eliminates bottom 2 players with 5 active players', () {
      // 5 players, local has fewest cards → should survive
      final ids = [
        OfflineGameState.localId,
        'player-2',
        'player-3',
        'player-4',
        'player-5',
      ];
      final cardCounts = {
        OfflineGameState.localId: 1,
        'player-2': 2,
        'player-3': 8,
        'player-4': 9,
        'player-5': 10,
      };
      final gs = stateWithCardCounts(cardCounts);
      final mgr = makeManager(ids, ids.first);
      // Give everyone 2 turns so round is complete
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(gs, {for (final id in ids) id: id});

      expect(result.eliminatedThisRound.length, 2);
      // Worst 2 (most cards) should be eliminated
      expect(result.eliminatedThisRound, containsAll(['player-4', 'player-5']));
      expect(result.survivorIds.length, 3);
      expect(result.isGameOver, isFalse);
    });

    test('eliminates 1 player when only 2 remain, declares winner', () {
      final ids = [OfflineGameState.localId, 'player-2'];
      final cardCounts = {
        OfflineGameState.localId: 1,
        'player-2': 5,
      };
      final gs = stateWithCardCounts(cardCounts);
      final mgr = makeManager(ids, ids.first);
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(gs, {for (final id in ids) id: id});

      expect(result.eliminatedThisRound.length, 1);
      expect(result.eliminatedThisRound.first, 'player-2');
      expect(result.isGameOver, isTrue);
      expect(result.winnerId, OfflineGameState.localId);
    });

    test('game is over when only 1 survivor remains', () {
      final ids = [OfflineGameState.localId, 'player-2', 'player-3'];
      final cardCounts = {
        OfflineGameState.localId: 0,
        'player-2': 5,
        'player-3': 6,
      };
      final gs = stateWithCardCounts(cardCounts);
      final mgr = makeManager(ids, ids.first);
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(gs, {for (final id in ids) id: id});

      // 3 players → eliminate 2 → 1 survivor → game over
      expect(result.isGameOver, isTrue);
      expect(result.survivorIds.length, 1);
      expect(result.winnerId, isNotNull);
    });

    test('cumulative penalties accumulate across rounds', () {
      final ids = [OfflineGameState.localId, 'player-2', 'player-3'];
      final cardCounts = {
        OfflineGameState.localId: 2,
        'player-2': 3,
        'player-3': 5,
      };
      final gs = stateWithCardCounts(cardCounts);
      final mgr = makeManager(ids, ids.first);
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(gs, {for (final id in ids) id: id});

      expect(result.cumulativePenalties[OfflineGameState.localId], 2);
      expect(result.cumulativePenalties['player-2'], 3);
      expect(result.cumulativePenalties['player-3'], 5);
    });

    test('standings are ordered best-first (fewest cumulative cards)', () {
      final ids = [OfflineGameState.localId, 'player-2', 'player-3', 'player-4', 'player-5'];
      final cardCounts = {
        OfflineGameState.localId: 1,
        'player-2': 3,
        'player-3': 5,
        'player-4': 7,
        'player-5': 9,
      };
      final gs = stateWithCardCounts(cardCounts);
      final mgr = makeManager(ids, ids.first);
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(gs, {for (final id in ids) id: id});

      // Best first = fewest cards
      expect(result.standingsThisRound.first.playerId, OfflineGameState.localId);
      expect(result.standingsThisRound.last.playerId, 'player-5');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 8. BustRoundManager.resumed — clean slate per round
  // ─────────────────────────────────────────────────────────────────────────

  group('BustRoundManager.resumed', () {
    test('starts with zero turns for all survivors', () {
      final survivors = ['player-2', 'player-3'];
      final mgr = BustRoundManager.resumed(
        survivorIds: survivors,
        firstPlayerId: 'player-2',
        penaltyPoints: const {},
        eliminatedIds: const [],
        roundNumber: 2,
      );
      for (final id in survivors) {
        expect(mgr.state.turnsThisRound[id], 0);
      }
    });

    test('round number is set correctly', () {
      final mgr = BustRoundManager.resumed(
        survivorIds: ['a', 'b'],
        firstPlayerId: 'a',
        penaltyPoints: const {},
        eliminatedIds: const [],
        roundNumber: 3,
      );
      expect(mgr.state.roundNumber, 3);
    });

    test('empty penaltyPoints means no inherited penalties', () {
      final mgr = BustRoundManager.resumed(
        survivorIds: ['a', 'b'],
        firstPlayerId: 'a',
        penaltyPoints: const {},
        eliminatedIds: const [],
        roundNumber: 2,
      );
      expect(mgr.state.penaltyPoints['a'], isNull);
      expect(mgr.state.penaltyPoints['b'], isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 9. BustLocalRoundStat.cardsShed
  // ─────────────────────────────────────────────────────────────────────────

  group('BustLocalRoundStat.cardsShed', () {
    test('shed = dealt - remaining', () {
      const stat = BustLocalRoundStat(
        roundNumber: 1,
        survived: true,
        cardsRemaining: 3,
        cardsDealt: 10,
      );
      expect(stat.cardsShed, 7);
    });

    test('shed is clamped to 0 when remaining > dealt (edge case)', () {
      const stat = BustLocalRoundStat(
        roundNumber: 1,
        survived: false,
        cardsRemaining: 12,
        cardsDealt: 10,
      );
      expect(stat.cardsShed, 0);
    });

    test('shed = 0 when no cards were played', () {
      const stat = BustLocalRoundStat(
        roundNumber: 1,
        survived: false,
        cardsRemaining: 10,
        cardsDealt: 10,
      );
      expect(stat.cardsShed, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 10. Full game-flow simulation (no UI)
  // ─────────────────────────────────────────────────────────────────────────

  group('Full game-flow simulation', () {
    /// Simulates a complete Bust tournament purely in logic:
    /// - Builds each round with BustEngine
    /// - Gives every player exactly 2 turns via recordTurn
    /// - Finalizes the round, collects elimination records
    /// - Repeats until game over
    test('10-player tournament concludes with exactly 1 winner', () {
      const startCount = 10;
      var playerCount = startCount;
      var roundNumber = 1;
      final eliminationHistory = <BustEliminationRecord>[];
      final localStats = <BustLocalRoundStat>[];

      // Track which survivor IDs carry forward (simulated)
      List<String> survivorIds = [];

      while (playerCount >= 2) {
        final (:gameState, :drawPile) =
            BustEngine.buildRound(playerCount: playerCount, seed: roundNumber);

        final ids = gameState.players.map((p) => p.id).toList();
        final mgr = roundNumber == 1
            ? BustRoundManager(
                initialActivePlayerIds: ids,
                firstPlayerId: ids.first,
              )
            : BustRoundManager.resumed(
                survivorIds: ids,
                firstPlayerId: ids.first,
                penaltyPoints: const {},
                eliminatedIds: const [],
                roundNumber: roundNumber,
              );

        // Every player takes 2 turns
        for (final id in ids) {
          mgr.recordTurn(id);
          mgr.recordTurn(id);
        }

        expect(mgr.state.isRoundComplete, isTrue,
            reason: 'Round $roundNumber should be complete');

        final playerNames = {for (final p in gameState.players) p.id: p.displayName};
        final result = mgr.finalizeRound(gameState, playerNames);

        expect(result.roundNumber, roundNumber);

        // Build elimination records for this round
        final cardsByPlayer = {
          for (final s in result.standingsThisRound) s.playerId: s.cardsThisRound,
        };
        for (final id in result.eliminatedThisRound) {
          eliminationHistory.add(BustEliminationRecord(
            playerName: playerNames[id] ?? id,
            roundEliminated: roundNumber,
            cardsAtElimination: cardsByPlayer[id] ?? 0,
            isLocal: id == OfflineGameState.localId,
          ));
        }

        // Track local player stat
        final localCards = cardsByPlayer[OfflineGameState.localId] ?? 0;
        final localSurvived =
            !result.eliminatedThisRound.contains(OfflineGameState.localId);
        localStats.add(BustLocalRoundStat(
          roundNumber: roundNumber,
          survived: localSurvived,
          cardsRemaining: localCards,
          cardsDealt: BustEngine.handSizeFor(playerCount),
        ));

        if (result.isGameOver) {
          expect(result.survivorIds.length, 1);
          expect(result.winnerId, isNotNull);
          // The winner's ID must be in the survivor list
          expect(result.survivorIds.contains(result.winnerId), isTrue);
          // The winner must NOT be in this round's eliminated list
          expect(result.eliminatedThisRound.contains(result.winnerId), isFalse);
          break;
        }

        survivorIds = result.survivorIds;
        playerCount = survivorIds.length;
        roundNumber++;
      }

      // Sanity: all non-winners have an elimination record
      expect(eliminationHistory.length, startCount - 1);

      // Sanity: every elimination record has a valid round number (>= 1)
      for (final rec in eliminationHistory) {
        expect(rec.roundEliminated, greaterThanOrEqualTo(1),
            reason: 'roundEliminated must be >= 1');
      }

      // Sanity: no two records share the same (playerName, round) pair
      final keys = eliminationHistory
          .map((r) => '${r.playerName}:${r.roundEliminated}')
          .toSet();
      expect(keys.length, eliminationHistory.length,
          reason: 'Duplicate elimination records found');
    });

    test('2-player game ends in exactly 1 round', () {
      final (:gameState, :drawPile) =
          BustEngine.buildRound(playerCount: 2, seed: 77);
      final ids = gameState.players.map((p) => p.id).toList();
      final mgr = BustRoundManager(
        initialActivePlayerIds: ids,
        firstPlayerId: ids.first,
      );
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(
        gameState,
        {for (final p in gameState.players) p.id: p.displayName},
      );

      expect(result.isGameOver, isTrue);
      expect(result.eliminatedThisRound.length, 1);
      expect(result.survivorIds.length, 1);
    });

    test('local player elimination is correctly flagged', () {
      // Force local player to have the most cards (worst score)
      final (:gameState, :drawPile) =
          BustEngine.buildRound(playerCount: 5, seed: 5);

      // Artificially give local player many cards
      final updatedPlayers = gameState.players.map((p) {
        if (p.id == OfflineGameState.localId) {
          final bigHand = List.generate(
              10, (i) => card(Rank.values[(i % 13) + 1], Suit.spades));
          return p.copyWith(hand: bigHand, cardCount: 10);
        }
        // AI players get 1 card each
        return p.copyWith(
          hand: [card(Rank.two, Suit.hearts)],
          cardCount: 1,
        );
      }).toList();
      final gs = gameState.copyWith(players: updatedPlayers);

      final ids = gs.players.map((p) => p.id).toList();
      final mgr = BustRoundManager(
        initialActivePlayerIds: ids,
        firstPlayerId: ids.first,
      );
      for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

      final result = mgr.finalizeRound(
        gs,
        {for (final p in gs.players) p.id: p.displayName},
      );

      expect(
        result.eliminatedThisRound.contains(OfflineGameState.localId),
        isTrue,
        reason: 'Local player with most cards should be eliminated',
      );
    });

    test('round does not complete until all players have 2 turns', () {
      final ids = ['a', 'b', 'c', 'd'];
      final mgr = makeManager(ids, 'a');

      // Only 1 turn each
      for (final id in ids) { mgr.recordTurn(id); }
      expect(mgr.state.isRoundComplete, isFalse);

      // Second turn for all
      for (final id in ids) { mgr.recordTurn(id); }
      expect(mgr.state.isRoundComplete, isTrue);
    });

    test('elimination count scales with player count', () {
      for (final n in [3, 4, 5, 6, 8, 10]) {
        final (:gameState, :drawPile) =
            BustEngine.buildRound(playerCount: n, seed: n);
        final ids = gameState.players.map((p) => p.id).toList();
        final mgr = BustRoundManager(
          initialActivePlayerIds: ids,
          firstPlayerId: ids.first,
        );
        for (final id in ids) { mgr.recordTurn(id); mgr.recordTurn(id); }

        final result = mgr.finalizeRound(
          gameState,
          {for (final p in gameState.players) p.id: p.displayName},
        );

        final expectedElim = n <= 2 ? 1 : 2;
        expect(result.eliminatedThisRound.length, expectedElim,
            reason: '$n players should eliminate $expectedElim');
        expect(result.survivorIds.length, n - expectedElim);
      }
    });
  });
}
