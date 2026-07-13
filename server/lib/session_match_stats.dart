import 'package:last_cards/core/models/card_model.dart';

/// Per-player counters accumulated during an online [GameSession].
class PlayerSessionMatchStats {
  int cardsPlayed = 0;
  int drawsTaken = 0;
  int penaltyCardsDrawn = 0;
  int specialsPlayed = 0;
  int stackBlocks = 0;
  int turns = 0;
  bool lastCardsDeclared = false;
  bool lastCardsBluffed = false;
}

/// Tracks match stats for all seats in a room.
class SessionMatchStats {
  final Map<String, PlayerSessionMatchStats> _byPlayer = {};

  PlayerSessionMatchStats forPlayer(String playerId) =>
      _byPlayer.putIfAbsent(playerId, () => PlayerSessionMatchStats());

  void reset() => _byPlayer.clear();

  void recordCardsPlayed(String playerId, List<CardModel> cards) {
    final s = forPlayer(playerId);
    s.cardsPlayed += cards.length;
    s.specialsPlayed += cards.where(_isSpecialForStats).length;
  }

  void recordDraw(String playerId, int count, {required bool isPenalty}) {
    final s = forPlayer(playerId);
    s.drawsTaken += count;
    if (isPenalty) {
      s.penaltyCardsDrawn += count;
    }
  }

  void recordStackBlock(String playerId) {
    forPlayer(playerId).stackBlocks++;
  }

  void recordTurnCompleted(String playerId) {
    forPlayer(playerId).turns++;
  }

  void recordLastCardsDeclared(String playerId) {
    forPlayer(playerId).lastCardsDeclared = true;
  }

  void recordLastCardsBluff(String playerId) {
    final s = forPlayer(playerId);
    s.lastCardsBluffed = true;
  }

  /// JSON map keyed by server player id for [game_ended.matchStats].
  Map<String, Map<String, dynamic>> toJsonByPlayerId({
    required Map<String, String> displayNames,
  }) {
    final out = <String, Map<String, dynamic>>{};
    for (final entry in _byPlayer.entries) {
      final s = entry.value;
      out[entry.key] = {
        'displayName': displayNames[entry.key] ?? entry.key,
        'cardsPlayed': s.cardsPlayed,
        'drawsTaken': s.drawsTaken,
        'penaltyCardsDrawn': s.penaltyCardsDrawn,
        'specialsPlayed': s.specialsPlayed,
        'stackBlocks': s.stackBlocks,
        'turns': s.turns,
        'lastCardsDeclared': s.lastCardsDeclared,
        'lastCardsBluffed': s.lastCardsBluffed,
      };
    }
    return out;
  }
}

bool _isSpecialForStats(CardModel c) {
  const specialRanks = {
    Rank.two,
    Rank.jack,
    Rank.queen,
    Rank.king,
    Rank.ace,
    Rank.eight,
  };
  return specialRanks.contains(c.effectiveRank) || c.isJoker;
}
