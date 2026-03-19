# Stack & Flow - Rules by Mode

## Core Gameplay Rules (applies to all gameplay modes)

### Objective
- Be the first player to play all cards in your hand.

### Setup
- Standard 52-card deck plus 2 Jokers (54 cards total).
- Cards are shuffled before each game.
- Each player receives 7 random cards.
- One card is placed face-up to start the discard pile.
- Remaining cards form the draw pile.
- If the starting face-up card is a special card, its effect triggers immediately.

### Turn Structure
- On your turn, you may play a card if it matches:
  - the suit of the top discard card, or
  - the rank/value of the top discard card, or
  - a valid special override (Ace, Joker, etc.).
- If you cannot play:
  - draw 1 card, and
  - your turn ends immediately.
- The drawn card cannot be played on that same turn.
- The table action bar shows **Next: …** (offline / local table only) — who would act after the current player ends the turn, using Eights (skip), King (reverse), and 2-player King. Online table omits it because player list order is per-client. Bust still shows **Next:** on its own state order.

### Multi-Card and Sequence Play
- You may play multiple cards of the same value in one turn.
- You may build a numerical sequence ascending or descending, but only in the same suit.
- After a same-suit sequence ends, you may continue with a cross-suit card of the same value as the final sequence card.

### Special Cards
- `2` (all suits): Next player draws 2 cards. Stackable with other 2s (penalty accumulates).
- `Black Jack` (`spades`/`clubs`): Next player draws 5 cards. Stackable, and can stack onto an active 2-chain.
- `Red Jack` (`hearts`/`diamonds`): Cancels any active draw penalty (resets draw stack to 0).
- `King`: Reverses direction of play.
- `Ace`: Player changes the active suit.
- `Queen`: Suit lock; next player must follow that suit (no number-match bypass).
- `8`: Next player is skipped.
- `Joker`: Wild; player declares both suit and rank.

### Effect Resolution Order
When multiple effects are active together, resolve in this order:
1. Draw penalties (`2` / Black Jack)
2. Skip (`8`)
3. Reverse (`King`)
4. Suit lock (`Queen`)

### Edge Cases
- If draw pile is empty, reshuffle discard pile (except top card) into a new draw pile.
- A player cannot win on a forced penalty draw unless a rule explicitly allows it.

---

## Mode-Specific Rules

### Play with AI
- Uses all core gameplay rules above.
- Played offline against AI opponents.

### Practice Mode
- Uses all core gameplay rules above.
- Played offline against AI opponents.
- Marked as **No leaderboard impact**.

### Tournament Mode
- Uses all core gameplay rules above within each round.
- Tournament progression:
  - Multiple players enter a round.
  - Players finish in order by emptying their hand.
  - The last finisher in the round is eliminated.
  - Remaining players advance to the next round.
  - Repeat until only one player remains (tournament winner).
- **Offline tournament:** After you qualify (empty hand), **Skip to result** fast-forwards the rest of the round with no AI think-time, card flights, or draw animations until the round ends (any player count).
- **Implementation note:** AI seats use IDs `tournament-ai-*` with `Ai.playerId` aligned to the same id so configs and bracket updates stay consistent.

### Play Online
- Intended to use the same core gameplay rules.
- Uses lobby/room flow for multiplayer sessions.
- Note: online networking/game-sync implementation is currently in progress in this codebase.
- **Leaderboards:** Firestore collections `leaderboard_online` and `leaderboard_bust_online` are **server-written only** (Admin SDK); the client may cache increments locally for instant UI. Casual quickplay standard wins update `leaderboard_online` when the session is trophy-eligible (`!isPrivate`); online Bust finals update `leaderboard_bust_online` the same way.

### Bust Mode
- **Deck:** 52-card standard deck only (no Jokers); 2–10 players.
- **Deal:** Hand size depends on player count (e.g. 10 cards each for 2–5 players, down to 5 each for 9–10 players) — see adaptive deal table in code (`handSizeForBust`).
- **Round structure:** Each active player takes exactly **2** turns per round; the round ends when everyone has played twice.
- **Scoring / elimination:** Cards left in hand at round end add to that player’s **cumulative** penalty score; the **bottom two** players by cumulative penalty are eliminated each round (only **one** elimination when two players remain, producing a winner).
- **Placement pile:** When the visible discard pile reaches **5** cards, the bottom **four** are shuffled back into the draw pile, leaving only the top card showing.
- **Reconnect / disconnect (online):** With **more than two** survivors, a disconnect removes that player and play continues; if **two or fewer** survivors would remain, the session ends like a normal disconnect.
- **Win:** Last player standing after eliminations wins.
- **Implementation notes:** Offline Bust tracks the same cumulative penalties across rounds via `BustRoundManager` and reuses seat IDs (`player-1` … `player-N`) each round. Jokers are not present; online play must use `declare_joker` (not `play_cards`) for Jokers in standard 54-card modes.
