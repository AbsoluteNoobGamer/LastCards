import 'dart:math' as math;

import 'package:last_cards/shared/engine/game_engine.dart';

/// Picks the next action for a server-controlled bot. Uses only shared engine
/// rules (no Flutter imports).
class ServerAiTurnPlan {
  ServerAiTurnPlan.playCards(this.payload)
      : kind = ServerAiTurnKind.playCards;

  ServerAiTurnPlan.declareJoker(this.payload)
      : kind = ServerAiTurnKind.declareJoker;

  ServerAiTurnPlan.draw()
      : kind = ServerAiTurnKind.draw,
        payload = null;

  ServerAiTurnPlan.endTurn()
      : kind = ServerAiTurnKind.endTurn,
        payload = null;

  final ServerAiTurnKind kind;

  /// JSON body expected by [GameSession.handleAction] (includes `type`).
  final Map<String, dynamic>? payload;
}

enum ServerAiTurnKind { playCards, declareJoker, draw, endTurn }

/// Difficulty string from the client (`easy` / `medium` / `hard`).
ServerAiTurnPlan planServerAiTurn({
  required GameState state,
  required String playerId,
  required String difficulty,
  required math.Random rng,
  required bool isHardcore,
}) {
  final player = state.playerById(playerId);
  if (player == null) {
    return ServerAiTurnPlan.draw();
  }

  final top = state.discardTopCard;
  if (top == null) {
    return ServerAiTurnPlan.draw();
  }

  final easy = difficulty == 'easy';

  // Joker in hand — try a legal declaration before normal plays.
  final jokerInHand = player.hand.where((c) => c.isJoker).toList();
  if (jokerInHand.isNotEmpty &&
      !(isHardcore && player.hand.length == 1)) {
    final jokerCard = jokerInHand.first;
    final jokerIn = resolveJokerPlayInputs(state: state, discardTop: top);
    final options = getValidJokerOptions(
      state: state,
      discardTop: top,
      context: jokerIn.resolvedContext,
      contextTopCard: jokerIn.anchor,
    );
    if (options.isNotEmpty) {
      final pick = easy
          ? options[rng.nextInt(options.length)]
          : _pickBestJokerOption(options, rng);
      return ServerAiTurnPlan.declareJoker({
        'type': 'declare_joker',
        'jokerCardId': jokerCard.id,
        'declaredSuit': pick.suit.name,
        'declaredRank': pick.rank.name,
      });
    }
  }

  // Enumerate same-rank stacks (offline-style multi plays).
  final playCandidates = _enumeratePlayCandidates(
    hand: player.hand,
    isHardcore: isHardcore,
  );

  final scored = <({List<CardModel> cards, Suit? declaredSuit, int score})>[];
  for (final cards in playCandidates) {
    if (cards.any((c) => c.isJoker)) continue;

    Suit? declaredSuit;
    if (cards.length == 1 &&
        cards.first.effectiveRank == Rank.ace &&
        state.actionsThisTurn == 0) {
      declaredSuit = Suit.values[rng.nextInt(Suit.values.length)];
    }

    final err = validatePlay(
      cards: cards,
      discardTop: top,
      state: state,
    );
    if (err != null) continue;

    var score = cards.length * 10;
    final afterCount = player.hand.length - cards.length;
    if (afterCount == 0) score += 100000;
    if (!easy) {
      score += rng.nextInt(6);
    }

    scored.add((cards: cards, declaredSuit: declaredSuit, score: score));
  }

  if (scored.isEmpty) {
    if (state.actionsThisTurn > 0 && validateEndTurn(state) == null) {
      return ServerAiTurnPlan.endTurn();
    }
    return ServerAiTurnPlan.draw();
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  final best =
      easy ? scored[rng.nextInt(scored.length)] : scored.first;

  final payload = <String, dynamic>{
    'type': 'play_cards',
    'cardIds': best.cards.map((c) => c.id).toList(),
  };
  if (best.declaredSuit != null) {
    payload['declaredSuit'] = best.declaredSuit!.name;
  }

  return ServerAiTurnPlan.playCards(payload);
}

CardModel _pickBestJokerOption(List<CardModel> options, math.Random rng) {
  // Prefer non-penalty declarations when possible.
  final nonPenalty = options
      .where(
        (c) =>
            c.rank != Rank.two &&
            c.rank != Rank.jack,
      )
      .toList();
  final pool = nonPenalty.isNotEmpty ? nonPenalty : options;
  return pool[rng.nextInt(pool.length)];
}

/// Builds candidate stacks: singles and same-rank multiples (non-joker).
List<List<CardModel>> _enumeratePlayCandidates({
  required List<CardModel> hand,
  required bool isHardcore,
}) {
  final result = <List<CardModel>>[];
  final nonJokers = hand.where((c) => !c.isJoker).toList();

  final byRank = <Rank, List<CardModel>>{};
  for (final c in nonJokers) {
    byRank.putIfAbsent(c.effectiveRank, () => []).add(c);
  }

  for (final group in byRank.values) {
    final n = group.length;
    for (var k = 1; k <= n; k++) {
      for (final combo in _combinations(group, k)) {

        }
        result.add(combo);
      }
    }
  }

  return result;
}

List<List<CardModel>> _combinations(List<CardModel> items, int k) {
  if (k == 0) return [[]];
  if (k > items.length) return [];
  if (k == items.length) return [List<CardModel>.from(items)];

  final out = <List<CardModel>>[];
  void pick(int start, List<CardModel> acc) {
    if (acc.length == k) {
      out.add(List<CardModel>.from(acc));
      return;
    }
    for (var i = start; i <= items.length - (k - acc.length); i++) {
      acc.add(items[i]);
      pick(i + 1, acc);
      acc.removeLast();
    }
  }

  pick(0, []);
  return out;
}
