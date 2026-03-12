# Regression Testing for 7-Player Support

When implementing the 7-player support changes (removing 4-player limit, fixed 7 cards per hand), run a full regression suite to ensure game logic and rules are not broken.

## Test Commands

```bash
# 1. Flutter/Dart client tests (from project root)
flutter test

# 2. Server tests (from project root)
dart run test server/test/
```

## Critical Test Suites (Game Logic & Rules)

| Suite | Path | Covers |
|-------|------|--------|
| Engine rules | `test/engine_test.dart` | validatePlay, applyPlay, numerical sequences, Queen self-covering, special cards (2, Jack, King, 8, Ace, Joker), penalty stacking, end-turn validation |
| Shared rules | `test/shared_rules_test.dart` | Win condition, suit lock, queen lock |
| Win condition | `test/win_condition_test.dart` | Win deferral, last-card special handling |
| Server session | `server/test/game_session_test.dart` | 7 cards per hand deal, room capacity, play/draw/end_turn flow, invalid play penalty |
| Tournament | `test/tournament/tournament_engine_test.dart` | Round flow, player advancement, qualification |
| AI player | `test/ai/ai_player_test.dart` | AI decision-making, valid plays |
| Bust logic | `test/bust/bust_logic_test.dart` | Bust-specific rules (unchanged; ensure no cross-contamination) |
| E2E gameplay | `test/e2e_gameplay_test.dart` | Full game flow |
| Joker pipeline | `test/joker_play_pipeline_connection_test.dart` | Joker popup, suit/rank declaration |

## New/Updated Tests to Add

- **OfflineGameState**: Verify `buildWithDeck(totalPlayers: 5)` and `buildWithDeck(totalPlayers: 7)` yield exactly 7 cards per player
- **GameSession (server)**: Verify 5-, 6-, 7-player games deal 7 cards each; room rejects 8th player (run from server package: `cd server && dart pub add dev:test && dart test`)
- **Engine**: Add a test with 5+ players to ensure turn advancement, nextPlayerId, and rule validation work correctly

## Manual Sanity Checks

After implementation:

1. **Offline single-player**: Start a 5- and 7-player game; confirm each hand has 7 cards and gameplay proceeds correctly
2. **Online**: Create/find a room with 5–7 players; confirm deal and play
3. **Tournament**: Run a 5-player tournament round; confirm flow and elimination
4. **Rules**: Play through scenarios (2-card penalty, Queen suit lock, 8 skip, King reverse, Ace wild, Joker declare) to confirm no regressions

## Success Criteria

- All existing tests pass
- New player-count tests (5, 6, 7) pass
- No failures in engine_test, shared_rules_test, win_condition_test, game_session_test
