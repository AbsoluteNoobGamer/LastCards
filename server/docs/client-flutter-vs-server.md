# Flutter UI vs `last_cards_server`

The game **server does not render UI**. It has no Flutter engine, widgets, or animations. These areas exist only in the **Flutter app**:

- **Ace suit sheet** — presentation (modal, suit buttons, layout).
- **Animations** — card flight, pile pulses, move log motion, etc.
- **Draw pile polish** — drawable ring, “DRAW” affordance, opacity.
- **Floating action bar layout** — direction icon, End Turn, Last Cards placement.

## What the server provides instead (authoritative)

The server validates **actions** and broadcasts **state** so the client can render the above honestly:

| Client concern | Server responsibility |
|----------------|----------------------|
| Ace suit choice after a wild Ace | `play_cards` accepts the Ace without `declaredSuit` when required; client then sends `suit_choice` with the chosen suit. `GameSession._handleSuitChoice` applies `suitLock` and snapshots. |
| Motion / timing | Outgoing messages such as `card_played`, `card_drawn`, `turn_changed`, `state_snapshot` — clients animate from these; the server does not describe frames or curves. |
| Draw pile | `draw_card` handler; `drawPileCount` (and draw events) in snapshots so the client can show pile size and reactions. |
| Floating bar (direction, Last Cards) | `end_turn`, `declare_last_cards`; turn order and `PlayDirection` appear in game state / snapshots. Last Cards timing uses shared `mayDeclareLastCards` in `lib/shared/rules/last_cards_rules.dart` (also enforced in `GameSession._handleDeclareLastCards`). |

If a future feature needs the server to **hint** animation (e.g. a named `effect` field), that would be a deliberate protocol change — not a copy of Flutter code on the server.
