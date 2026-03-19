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

  /// Bust uses a standard 52-card deck only — there are no Jokers — so Bust UI
  /// does not need Joker declaration paths or `isJoker` guards.

  /// Returns a freshly shuffled 52-card deck (no Jokers).
  /// Delegates to [buildBustDeck] in the shared engine.
  static List<CardModel> buildShuffledDeck({int? seed, math.Random? random}) =>
      buildBustDeck(seed: seed, random: random);

  // ── Game builder ───────────────────────────────────────────────────────────

  /// Builds the initial [GameState] and draw pile for a Bust round.
  ///
  /// [playerCount] must be between 2 and 10.
  ///
  /// [seatPlayerIds] optional full seat order: length [playerCount], index `0`
  /// must be [OfflineGameState.localId], remaining entries are opponent IDs
  /// (use the same strings as prior rounds so penalties / [aiNames] stay aligned).
  /// If omitted, opponents are `'player-2'` … `'player-{playerCount}'`.
  ///
  /// [aiNames] maps each non-local seat id to a display name.
  /// [startingPlayerId] optionally overrides who goes first (random by default).
  static ({GameState gameState, List<CardModel> drawPile}) buildRound({
    required int playerCount,
    List<String>? seatPlayerIds,
    Map<String, String> aiNames = const {},
    String? startingPlayerId,
    int? seed,
  }) {
    assert(playerCount >= 2 && playerCount <= 10,
        'Bust playerCount must be between 2 and 10');

    final seatIds = seatPlayerIds ??
        [
          OfflineGameState.localId,
          for (var k = 2; k <= playerCount; k++) 'player-$k',
        ];
    assert(seatIds.length == playerCount,
        'seatPlayerIds length must equal playerCount');
    assert(seatIds.toSet().length == seatIds.length,
        'seatPlayerIds must not contain duplicates');
    assert(seatIds[0] == OfflineGameState.localId,
        'seatPlayerIds[0] must be OfflineGameState.localId');

    final rng = seed != null ? math.Random(seed) : math.Random();
    final deck = buildShuffledDeck(random: rng);
    int idx = 0;
    final handSize = handSizeFor(playerCount);

    List<CardModel> draw(int count) {
      final drawn = deck.sublist(idx, idx + count);
      idx += count;
      return drawn;
    }

    // Positions cycle through all 9 opponent slots so up to 10-player Bust
    // matches the server's _positionFor logic in game_session.dart.
    const aiPositionCycle = [
      TablePosition.top,
      TablePosition.left,
      TablePosition.right,
      TablePosition.bottomLeft,
      TablePosition.topLeft,
      TablePosition.topRight,
      TablePosition.bottomRight,
      TablePosition.farLeft,
      TablePosition.farRight,
    ];

    final players = <PlayerModel>[];
    for (var i = 0; i < playerCount; i++) {
      final id = seatIds[i];
      final hand = draw(handSize);
      if (i == 0) {
        players.add(PlayerModel(
          id: id,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: hand,
          cardCount: hand.length,
        ));
      } else {
        final aiSlot = i - 1;
        players.add(PlayerModel(
          id: id,
          displayName:
              aiNames[id] ?? id.replaceFirst(RegExp(r'^player-'), 'Player '),
          tablePosition: aiPositionCycle[aiSlot % aiPositionCycle.length],
          hand: hand,
          cardCount: hand.length,
        ));
      }
    }

    // 3. Face-up discard + remaining draw pile
    final discardTop = draw(1).first;
    final drawPile = List<CardModel>.from(deck.sublist(idx));

    // 4. Pick starting player (same RNG stream as deck shuffle for reproducibility)
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

    fisherYatesShuffle(toShuffle, seed: seed);

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
