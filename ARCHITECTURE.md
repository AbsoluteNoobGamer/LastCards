# Last Cards — Architecture

## Overview

Last Cards is a Flutter card game. **Authoritative game rules and engine behavior** live under `lib/shared/` (engine + rules) and **`lib/core/models/`** (serializable state and models). The `lib/shared/models/*.dart` files are **barrel re-exports** of the core models for convenient imports from shared code and the server; implement types in `lib/core/models/`, not duplicate definitions.

Game flows (offline, online, tournament, Bust) live under **`lib/features/`** and **`lib/tournament/`** as thin coordinators; they must not fork rule logic.

---

## Folder structure (high level)

```
lib/
  core/models/          ← canonical CardModel, GameState, PlayerModel, layout helpers, offline glue
  shared/
    engine/             ← game_engine.dart, timers, shuffle_utils
    rules/              ← card_rules, pickup_chain_rules, win_condition_rules, move_log_support
    models/             ← barrel exports → package:last_cards/core/models/...
  features/             ← gameplay UI, bust, profile, settings, etc.
  tournament/             ← tournament orchestration (uses shared engine)
server/                   ← Dart server; imports package:last_cards (shared engine + core)

test/                     ← engine_test, shared_rules_test, feature tests (e.g. test/bust/, test/tournament/)
```

---

## Core rules (`lib/shared/`)

### Pick-up cards

- **2♠, 2♥, 2♦, 2♣** — add +2 to the active pick-up chain
- **J♠, J♣ (Black Jacks)** — add +5 to the chain
- **J♥, J♦ (Red Jacks)** — cancel the chain (+0)

### Joker (54-card modes)

- **Wild play** — the Joker is played as a chosen rank/suit (including specials) for matching and sequences; it is not a separate fixed “pick-up value” on its own.
- **Penalty chains** — a Joker can **participate in the pick-up chain** when declared as a penalty-generating card (e.g. as a **2** or **Black Jack**), using the usual penalty rules for that declared rank.

### Pick-up chain

- Penalty cards can counter each other per shared rules; values stack until resolved by draw or Red Jack.
- **Penalty-on-penalty free matching** (any 2 or Jack on any other 2 or Jack without matching suit or rank) applies **only while** the pick-up chain is active (`activePenaltyCount > 0`). After the penalty is resolved, the top discard may still be a 2 or Jack, but it is matched like any other card (suit or rank).

### Win condition

- Last card is NOT a pick-up card → win immediately
- Last card IS a pick-up card → win deferred until chain fully resolves
- If a player is forced to draw from the chain, they no longer have zero cards and do not win

See [`docs/rules-by-mode.md`](docs/rules-by-mode.md) for mode-specific notes.

---

## Architecture rules

1. **Shared rules** live in `lib/shared/rules/`; **engine** in `lib/shared/engine/`.
2. **Canonical models** live in `lib/core/models/`; `lib/shared/models/` re-exports only.
3. **Game modes and screens** must not duplicate engine rules; they configure flows and call `validatePlay` / `applyPlay` / `applyDraw` from the shared engine.
4. **Tournament / Bust–specific orchestration** lives under `lib/features/` and `lib/tournament/` (not a parallel `lib/modes/` tree).
5. **UI** must not own core rule logic; keep validation in the shared engine.

---

## Decision rule

Before placing a change, ask:

> Does this rule apply when playing a casual online game?

- **Yes** → `lib/shared/` (engine + rules) and, if needed, `lib/core/models/` for state shape
- **No** → `lib/features/{feature}/` or `lib/tournament/` for orchestration only

---

## Testing

- **Engine and shared rules:** `test/engine_test.dart`, `test/shared_rules_test.dart`, and focused files (e.g. `test/joker_popup_options_test.dart`).
- **Feature / mode:** e.g. `test/bust/`, `test/tournament/`, `test/widgets/`.
- **Server:** `server/test/` (game session, protocol).
- New rules should include regression tests that would fail if the shared engine changes.

---
