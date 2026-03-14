import 'dart:math' as math;

import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/engine/shuffle_utils.dart';

export 'package:last_cards/shared/models/card_model.dart';
export 'package:last_cards/shared/models/game_state_model.dart';
export 'package:last_cards/shared/models/player_model.dart';

/// Bust-mode specific game engine.
///
/// Differences from the standard offline engine:
/// - 52-card deck (no Jokers)
/// - Adaptive deal based on player count (5–10)
/// - Placement pile rule: discard hits 5 → bottom 4 shuffle back into draw pile
abstract final class BustEngine {
  // ── Adaptive deal table ─────────────────────────────────────────────────────

  /// Returns the hand size for the given player count per the Bust deal table.
  ///
  /// | Players | Cards each |
  /// |---------|------------|
  /// | 2–4     | 10         |
  /// | 5       | 10         |
  /// | 6       | 8          |
  /// | 7       | 7          |
  /// | 8       | 6          |
  /// | 9–10    | 5          |
  ///
  /// Counts below 5 arise in later rounds as players are eliminated.
  /// Delegates to [handSizeForBust] in the shared engine.
  static int handSizeFor(int playerCount) => handSizeForBust(playerCount);

  // ── 52-card deck builder (no Jokers) ───────────────────────────────────────

  /// Returns a freshly shuffled 52-card deck (no Jokers).
  /// Delegates to [buildBustDeck] in the shared engine.
  static List<CardModel> buildShuffledDeck({int? seed}) =>
      buildBustDeck(seed: seed);

  // ── Game builder ───────────────────────────────────────────────────────────

  /// Builds the initial [GameState] and draw pile for a Bust round.
  ///
  /// [playerCount] must be between 5 and 10.
  /// [aiNames] maps player IDs (`'player-2'` … `'player-N'`) to display names.
  /// [startingPlayerId] optionally overrides who goes first (random by default).
  static ({GameState gameState, List<CardModel> drawPile}) buildRound({
    required int playerCount,
    Map<String, String> aiNames = const {},
    String? startingPlayerId,
    int? seed,
  }) {
    assert(playerCount >= 2 && playerCount <= 10,
        'Bust playerCount must be between 2 and 10');

    final deck = buildShuffledDeck(seed: seed);
    int idx = 0;
    final handSize = handSizeFor(playerCount);

    List<CardModel> draw(int count) {
      final drawn = deck.sublist(idx, idx + count);
      idx += count;
      return drawn;
    }

    // 1. Local player (bottom)
    final localHand = draw(handSize);
    final players = <PlayerModel>[
      PlayerModel(
        id: OfflineGameState.localId,
        displayName: 'You',
        tablePosition: TablePosition.bottom,
        hand: localHand,
        cardCount: localHand.length,
      ),
    ];

    // 2. AI players — positions cycle so all counts work
    const aiPositionCycle = [
      TablePosition.top,
      TablePosition.left,
      TablePosition.right,
    ];
    for (int i = 0; i < playerCount - 1; i++) {
      final aiId = 'player-${i + 2}';
      final aiHand = draw(handSize);
      players.add(PlayerModel(
        id: aiId,
        displayName: aiNames[aiId] ?? 'Player ${i + 2}',
        tablePosition: aiPositionCycle[i % aiPositionCycle.length],
        hand: aiHand,
        cardCount: aiHand.length,
      ));
    }

    // 3. Face-up discard + remaining draw pile
    final discardTop = draw(1).first;
    final drawPile = List<CardModel>.from(deck.sublist(idx));

    // 4. Pick starting player (random unless overridden)
    final rng = math.Random(seed);
    final firstId = startingPlayerId ??
        players[rng.nextInt(players.length)].id;

    final state = GameState(
      sessionId: 'bust-session',
      phase: GamePhase.playing,
      players: players,
      currentPlayerId: firstId,
      direction: PlayDirection.clockwise,
      discardTopCard: discardTop,
      drawPileCount: drawPile.length,
      activePenaltyCount: 0,
      suitLock: null,
      queenSuitLock: null,
      winnerId: null,
    );

    return (gameState: state, drawPile: drawPile);
  }

  // ── Placement pile rule ────────────────────────────────────────────────────

  /// When the discard pile reaches [threshold] cards (default 5), the bottom
  /// [threshold - 1] cards are shuffled back into the draw pile, leaving only
  /// the top card as the active face-up card.
  ///
  /// Returns `null` if no reshuffle is needed.
  static ({List<CardModel> newDrawPile, bool didReshuffle}) applyPlacementPileRule({
    required List<CardModel> discardPile,
    required List<CardModel> drawPile,
    int threshold = 5,
    int? seed,
  }) {
    if (discardPile.length < threshold) {
      return (newDrawPile: drawPile, didReshuffle: false);
    }

    final toShuffle =
        List<CardModel>.from(discardPile.sublist(0, discardPile.length - 1));

    fisherYatesShuffle(toShuffle, seed);

    // Discard pile is managed by caller — they should clear it and add topCard back
    final newDrawPile = [...drawPile, ...toShuffle];
    return (newDrawPile: newDrawPile, didReshuffle: true);
  }

  /// Returns `true` if the discard pile has reached the placement threshold.
  static bool needsPlacementPileReshuffle(
      List<CardModel> discardPile, {
      int threshold = 5,
    }) =>
      discardPile.length >= threshold;
}
