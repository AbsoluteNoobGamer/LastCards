# DeckDrop — Architecture

## Overview
DeckDrop is a 4-player card game built in Flutter. All core game rules and engine
logic live in a centralised shared module. Game modes consume shared logic and must not
implement their own rule logic.

---

## Folder Structure



```
lib/
  shared/
    rules/
      card_rules.dart
...
```
 ← definitions of all special cards (2s, Black Jacks, Joker modes)
pickup_chain_rules.dart ← chain stacking, counter validation, chain resolution
win_condition_rules.dart ← immediate vs deferred win logic
engine/
game_engine.dart ← turn management, hand management, card play validation
models/
card_model.dart ← shared card model
game_state_model.dart ← shared game state model

modes/
online/
online_game_mode.dart ← online multiplayer mode (imports from shared only)
offline/
offline_game_mode.dart ← offline/AI mode (imports from shared only)
practice/
practice_mode.dart ← practice mode (imports from shared only)
tournament/
tournament_mode.dart ← tournament entry point
tournament_rules.dart ← tournament-only rules (brackets, elimination)
tournament_engine.dart ← tournament-only logic
tournament_bracket.dart ← bracket and elimination logic
tournament_scoring.dart ← points, rankings, tiebreakers

screens/ ← UI screens only, no game logic
widgets/ ← reusable UI components only, no game logic


---

## Core Rules (lib/shared/)

### Pick-Up Cards
- **2♠, 2♥, 2♦, 2♣** — force next player to pick up 2 cards
- **J♠, J♣ (Black Jacks)** — force next player to pick up 5 cards
- **Joker (pick-up mode)** — force next player to pick up Joker's defined value

### Joker Dual Mode
- **Pick-up mode** — Joker joins the pick-up chain, valid as a counter against any pick-up card
- **Transform/wild mode** — Joker transforms into any card; cannot be used as a counter in a chain

### Pick-Up Chain
- Any pick-up card can counter any other pick-up card
- Pick-up values stack cumulatively across the full chain
- Chain resolves when a player cannot counter and must draw

### Win Condition
- Last card is NOT a pick-up card → win immediately
- Last card IS a pick-up card → win deferred until chain fully resolves
- If player is forced to draw from the chain, they no longer have zero cards and do not win

---

## Architecture Rules

1. **All core game rules live in `lib/shared/rules/` only**
2. **All engine logic lives in `lib/shared/engine/` only**
3. **Game modes import from `lib/shared/` — they must not contain their own rule logic**
4. **Tournament-only logic lives in `lib/modes/tournament/` only**
5. **UI screens and widgets must not contain any game rule or engine logic**
6. **No circular dependencies between shared and mode-specific modules**
7. **Any new rule that applies to all modes goes in `lib/shared/rules/`**
8. **Any rule that applies only to one mode goes in `lib/modes/{mode}/`**

---

## Decision Rule
Before placing any logic, ask:
> "Does this rule apply when playing a casual online game?"
- **Yes** → `lib/shared/`
- **No** → `lib/modes/{specific_mode}/`

---

## Testing
- All shared rule tests live in `test/shared/`
- All mode-specific tests live in `test/modes/{mode}/`
- All pre-existing tests must pass after any refactor
- New rules must include regression tests before merging

---
