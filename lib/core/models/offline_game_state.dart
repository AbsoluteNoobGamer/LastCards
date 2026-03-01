import 'dart:math' as math;

import '../models/card_model.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';

/// Pre-built GameState + shuffled draw pile for offline mode.
///
/// Players:
///   • You        (bottom, human)  — 7 randomly dealt cards
///   • Player 2   (top,    AI)     — 7 randomly dealt cards
///
/// The Dealer is NOT a player. It is the banking entity whose only
/// responsibility is managing the draw pile. No card count, no hand,
/// no turns.
abstract final class OfflineGameState {
  static const localId = 'player-local';
  static const aiId = 'player-2';

  // ── Full 54-card deck builder ────────────────────────────────────────────────

  static const _ranks = [
    Rank.two,
    Rank.three,
    Rank.four,
    Rank.five,
    Rank.six,
    Rank.seven,
    Rank.eight,
    Rank.nine,
    Rank.ten,
    Rank.jack,
    Rank.queen,
    Rank.king,
    Rank.ace,
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
    deck.add(
        const CardModel(id: 'joker_r', rank: Rank.joker, suit: Suit.hearts));
    deck.add(
        const CardModel(id: 'joker_b', rank: Rank.joker, suit: Suit.spades));

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
  /// fresh shuffled deck, dealing 7 cards to each of [totalPlayers] (2 to 4).
  static (GameState gameState, List<CardModel> drawPile) buildWithDeck(
      {int totalPlayers = 2}) {
    assert(totalPlayers >= 2 && totalPlayers <= 4,
        'totalPlayers must be between 2 and 4');
    final deck = buildShuffledDeck();

    int deckIndex = 0;

    // Helper to draw exactly count cards safely
    List<CardModel> draw(int count) {
      final drawn = deck.sublist(deckIndex, deckIndex + count);
      deckIndex += count;
      return drawn;
    }

    // 1. Deal local human
    final localHand = draw(7);
    final players = <PlayerModel>[
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
    ];

    // 2. Deal AIs
    final aiPositions = switch (totalPlayers) {
      2 => [TablePosition.top],
      3 => [TablePosition.left, TablePosition.right],
      4 => [TablePosition.left, TablePosition.top, TablePosition.right],
      _ => [TablePosition.top],
    };

    for (int i = 0; i < totalPlayers - 1; i++) {
      final aiHand = draw(7);
      players.add(PlayerModel(
        // Dynamic zero-indexed based suffix for IDs, e.g. player-2, player-3, player-4
        id: 'player-${i + 2}',
        displayName: 'Player ${i + 2}',
        tablePosition: aiPositions[i],
        hand: aiHand,
        cardCount: aiHand.length,
        isConnected: true,
        isActiveTurn: false,
        isSkipped: false,
      ));
    }

    final discardTop = draw(1).first;
    final drawPile = deck.sublist(deckIndex);

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
