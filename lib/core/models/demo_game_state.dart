import 'dart:math' as math;

import '../models/card_model.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';

/// Pre-built GameState + shuffled draw pile for demo / development mode.
///
/// Players:
///   • You        (bottom, human)  — 7 randomly dealt cards
///   • Player 2   (top,    AI)     — 7 randomly dealt cards
///
/// The Dealer is NOT a player. It is the banking entity whose only
/// responsibility is managing the draw pile. No card count, no hand,
/// no turns.
abstract final class DemoGameState {
  static const localId = 'player-local';
  static const aiId    = 'player-2';

  // ── Full 54-card deck builder ────────────────────────────────────────────────

  static const _ranks = [
    Rank.two, Rank.three, Rank.four, Rank.five, Rank.six, Rank.seven,
    Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen, Rank.king, Rank.ace,
  ];
  static const _suits = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

  /// Returns a freshly shuffled 54-card deck.
  static List<CardModel> buildShuffledDeck() {
    final rng = math.Random();
    final deck = <CardModel>[];

    for (final suit in _suits) {
      for (final rank in _ranks) {
        deck.add(CardModel(
          id: '${rank.name}_${suit.name}',
          rank: rank,
          suit: suit,
        ));
      }
    }
    // Two Jokers
    deck.add(const CardModel(id: 'joker_r', rank: Rank.joker, suit: Suit.hearts));
    deck.add(const CardModel(id: 'joker_b', rank: Rank.joker, suit: Suit.spades));

    // Fisher-Yates shuffle
    for (int i = deck.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = deck[i];
      deck[i] = deck[j];
      deck[j] = tmp;
    }

    return deck;
  }

  /// Builds the initial [GameState] and the remaining [drawPile] from a single
  /// fresh shuffled deck.
  ///
  /// Cards 0-6  → local player hand
  /// Cards 7-13 → AI hand
  /// Card  14   → starting discard
  /// Cards 15+  → draw pile (39 cards)
  static (GameState gameState, List<CardModel> drawPile) buildWithDeck() {
    final deck = buildShuffledDeck();

    final localHand  = deck.sublist(0, 7);
    final aiHand     = deck.sublist(7, 14);
    final discardTop = deck[14];
    final drawPile   = deck.sublist(15); // 39 cards

    final players = [
      PlayerModel(
        id: localId,
        displayName: 'You',
        tablePosition: TablePosition.bottom,
        hand: localHand,
        cardCount: localHand.length,
        isConnected: true,
        isActiveTurn: true,
        isSkipped: false,
      ),
      PlayerModel(
        id: aiId,
        displayName: 'Player 2',
        tablePosition: TablePosition.top,
        hand: aiHand,
        cardCount: aiHand.length,
        isConnected: true,
        isActiveTurn: false,
        isSkipped: false,
      ),
    ];

    final state = GameState(
      sessionId: 'demo-session',
      phase: GamePhase.playing,
      players: players,
      currentPlayerId: localId,
      direction: PlayDirection.clockwise,
      discardTopCard: discardTop,
      discardSecondCard: null,
      drawPileCount: drawPile.length,
      activePenaltyCount: 0,
      suitLock: null,
      queenSuitLock: null,
      winnerId: null,
      lastUpdatedAt: 0,
    );

    return (state, drawPile);
  }
}
