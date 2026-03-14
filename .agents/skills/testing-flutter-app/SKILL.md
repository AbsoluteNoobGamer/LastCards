# Testing stackAndFlow Flutter App

## Environment Setup

- Flutter SDK must be available (check with `flutter --version`)
- Use `flutter run -d web-server --web-port 8080` to serve the app (NOT `-d chrome` which may fail in headless environments)
- Open `http://localhost:8080` in Chrome manually after the server starts
- Wait ~30s for the web build to compile before opening the browser
- The production server URL is `stackandflow-production.up.railway.app`

## Running Tests

```bash
cd ~/repos/stackAndFlow && flutter test
```

## Offline Single-Player Game Flow

This is the primary testing path that exercises most game logic without needing a server:

1. **Start screen** loads at `/` — shows "Single Player", "Online", "Tournament" buttons
2. Click **"Single Player"** → opens difficulty selection bottom sheet (Easy/Medium/Hard)
3. Select a **difficulty** → opens player count sheet (2-7 players)
4. Select **player count** and click **"Play"** → navigates to loading screen, then game table
5. **Deal animation** plays — cards animate being dealt to all players
6. **Game table** renders with:
   - Local player's hand at bottom
   - AI opponents at top/left/right positions
   - Discard pile and draw pile in center
   - Turn indicator and direction indicator

## Key Game Mechanics to Validate

- **Card play**: Click a card in hand to play it (must match suit or rank of discard top)
- **Draw**: Click draw pile when no valid play available
- **End Turn**: Click "End Turn" button after playing/drawing
- **Special effects**:
  - **2s**: Add +2 pickup penalty (stacks with other 2s)
  - **Kings**: Reverse play direction (Clockwise ↔ Counter-Clockwise)
  - **8s**: Skip next player
  - **Jokers**: Wild card — shows resolution popup to declare suit/rank. The declared card's special effect should apply.
- **Penalty chains**: 2s stack penalties (+2, +4, +6...). Jokers declared as 2s also stack.
- **Win condition**: First player to empty their hand wins
- **Play Again**: After game ends, "PLAY AGAIN" button starts a new game with fresh opponents

## Navigation Code References

- Start screen: `lib/features/start/presentation/screens/start_screen.dart`
- Start buttons: `lib/features/start/presentation/screens/start_screen_buttons.dart`
- Difficulty sheet: `lib/features/single_player/widgets/difficulty_selection_sheet.dart`
- Player count sheet: `lib/features/single_player/widgets/player_count_sheet.dart`
- Game table: `lib/features/gameplay/presentation/screens/table_screen.dart`
- Game engine: `lib/shared/engine/game_engine.dart`
- Routes: `lib/app/router/app_routes.dart` (/ = start, /game = table)

## Tips

- The app uses Riverpod for state management — game state flows through providers
- Offline mode runs the shared game engine locally (no server needed)
- AI turns happen automatically with delays — wait 10-15 seconds between turns
- The deal animation count is derived from actual hand size (not hardcoded)
- Fisher-Yates shuffle is in `lib/shared/engine/shuffle_utils.dart`

## Devin Secrets Needed

No secrets are needed for offline testing. For online play testing, the server URL is public.
