# Stack & Flow — Application Guidelines

## Overview

**Stack & Flow** is a competitive, turn-based card game for 2–4 players built around stacking mechanics, numerical flow, and tactical disruption. The application delivers a premium casino-grade experience with real-time multiplayer, smooth animations, and an authoritative server-side game engine.

---

## Game Rules

### Objective

Be the first player to play all cards in your hand.

---

### Setup

- Standard 52-card deck plus 2 Jokers (54 cards total)
- Cards are shuffled before each game
- Each player receives 7 random cards
- One card is placed face-up to start the discard pile
- Remaining cards form the draw pile
- **Note:** The starting face-up card triggers its special ability immediately if applicable

---

### Turn Structure

On a player's turn, they may play a card if it matches:

- The **suit** of the top discard card, OR
- The **rank/value** of the top discard card, OR
- A valid **special override** (Ace, Joker, etc.)

If a player cannot play:

- They must draw 1 card
- Their turn ends immediately
- The drawn card **cannot** be played on that same turn, even if it would be a valid play

---

### Multi-Card Play — Same-Value Stacking

A player may play multiple cards of the same value in a single turn.

**Example:** If `4♣` is on top, the player may play `4♦ + 4♠ + 4♥` all at once.

---

### Numerical Flow Rule (Core Mechanic)

Players may build a numerical sequence ascending or descending, but only within the **same suit**.

**Example:** If `A♥` is on top, the player may play `2♥ → 3♥ → 4♥`.

Once the sequence ends, if the final card matches another card in **value** (regardless of suit), it may be played to continue the turn.

**Example:** Sequence ends at `4♥` → player may then play `4♣`.

After that cross-suit value match, normal matching rules apply.

---

### Special Cards

| Card | Effect |
|---|---|
| **2 (All Suits)** | Next player draws 2 cards. May be stacked with another 2 to pass the penalty. Penalty accumulates (2 → 4 → 6…). |
| **Black Jack (♠ / ♣)** | Next player draws 5 cards. May be stacked with another Black Jack. Can also stack onto an active 2-chain. |
| **Red Jack (♥ / ♦)** | Cancels any active draw penalty. Resets the draw stack to 0. |
| **King** | Reverses the direction of play. |
| **Ace** | Player changes the active suit. Player declares the new suit upon playing. |
| **Queen** | Next player must follow the same suit. Cannot change suit or match by number. Must be covered with the same suit. |
| **8** | Next player misses their turn (skip). |
| **Joker** | Wild card. Player declares both the suit and rank. Treated as that card until replaced. |

---

### Penalty Resolution Order

When multiple effects are active simultaneously, they resolve in this order:

1. Draw penalties (2s / Black Jacks)
2. Skip (8)
3. Reverse (King)
4. Suit lock (Queen)

---

### Edge Cases

- If the starting card is a special card, its effect triggers immediately
- If the draw pile is empty, reshuffle the discard pile (excluding the top card) to form a new draw pile
- A player cannot win on a forced penalty draw unless a rule explicitly permits it

---

## Tech Stack

### Frontend

| Technology | Purpose |
|---|---|
| **Flutter** | Cross-platform UI framework |
| **Dart** | Primary programming language |

Target platforms: iOS, Android, Web, Tablet

### Backend

| Technology | Purpose |
|---|---|
| **Dart** | Authoritative server-side game engine |
| **Dart Frog** or **Shelf** | HTTP and WebSocket server |
| **Firebase** | Real-time multiplayer state sync (recommended) |
| **WebSockets** | Live game event streaming |

### Architecture Principles

- **Authoritative server-side engine** — all game logic validated server-side; clients are display-only
- **Clean separation of UI and game logic** — game state is managed independently of rendering
- **Real-time multiplayer** — game state synced across all connected clients with minimal latency
- **60fps animations** — UI targets smooth 60fps on all supported devices
- **Responsive design** — adaptive layouts for mobile, tablet, and web viewports

---

## Development Guidelines

### Game State Management

- Game state (hands, discard pile, draw pile, turn order, active effects) lives exclusively on the server
- Clients receive state updates via WebSocket events
- All player actions are sent as events to the server, validated, and then broadcast to all players

### Multiplayer

- Sessions support 2–4 concurrent players
- Reconnection handling required — players should be able to rejoin an active game
- Turn timeout should be configurable per session

### Security

- Server must validate every card play against current game state
- Clients should never be trusted to self-report valid moves
- Joker declarations must be validated against legal plays before acceptance

---

*Stack & Flow — Guidelines v1.0*
