import 'package:last_cards/shared/engine/game_engine.dart';

import 'ai_player_config.dart';

export 'package:last_cards/shared/engine/game_engine.dart';
export 'ai_player_config.dart';

part 'offline_game_engine_ai.dart';

/// Offline / local session helper: holds one [GameState] and a [cardFactory]
/// for draws, and forwards to [aiTakeTurn]. Table flows may keep state on the
/// widget instead; this class is optional when you want a single place to run
/// AI moves against a mutable [state].
class OfflineGameEngine {
  OfflineGameEngine({
    required this.state,
    required List<CardModel> Function(int n) cardFactory,
  }) : _cardFactory = cardFactory;

  GameState state;
  final List<CardModel> Function(int n) _cardFactory;

  bool aiCanPlay(String aiPlayerId) =>
      aiHasPlayableTurn(state: state, aiPlayerId: aiPlayerId);

  ({
    GameState state,
    List<CardModel> playedCards,
    GameState preTurnAdvanceState,
    int queenCoverDrawCount,
    Suit? aceDeclaredSuit,
  }) runAiTurn({
    required String aiPlayerId,
    AiPersonality? personality,
  }) {
    final result = aiTakeTurn(
      state: state,
      aiPlayerId: aiPlayerId,
      cardFactory: _cardFactory,
      personality: personality,
    );
    state = result.state;
    return result;
  }

  /// Drops offline AI suit-inference data for [state.sessionId]. Call when the
  /// session ends (e.g. after the round/game finishes or the engine is discarded).
  void dispose() {
    clearSuitInference(state.sessionId);
  }
}
