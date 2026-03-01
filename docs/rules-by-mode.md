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

### Play Online
- Intended to use the same core gameplay rules.
- Uses lobby/room flow for multiplayer sessions.
- Note: online networking/game-sync implementation is currently in progress in this codebase.

