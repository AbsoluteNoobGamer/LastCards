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
- **Pick-up matching:** While the penalty chain is **live** (a penalty card was most recently played and no player has drawn or played a non-penalty card to break it), penalty cards (`2` / Black Jack / Red Jack) may be played on other penalty cards without matching suit or rank. The chain stays **live** after a Red Jack resets the draw count to zero; it ends when someone draws, a non-penalty card clears the chain (e.g. sequence continuation), or the turn advances after a non-penalty card.
- `King`: Reverses direction of play. **2 players:** that sends the turn back to you; your **next** card on that same turn is matched to the discard top (the King) with normal suit/rank rules — it does **not** have to be the next/previous rank in a numerical run from the King. **Ace on that follow-up** is not “change the suit” wild; it must match the King by suit or by rank like other cards. **3+ players:** mid-turn numerical-flow rules still apply after a King like any other non-special card.
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

### Last Cards (not in Bust mode)
- Press **Last Cards** before your turn when you believe you can shed your whole hand in one turn.
- The server (and offline engine) record whether your hand **was** clearable in one turn when your turn **starts**. You must have declared only if that snapshot is true; otherwise you can still win without declaring (e.g. you drew into a winning hand).
- If you must declare and play out without having declared, you draw 1 card instead of winning and your turn ends.
- The button is available when it is not your turn and you have not already declared (no fixed hand-size gate in the UI).
- Declaring is public: everyone sees who declared.
- A false declaration (hand not clearable in one turn) is caught when your turn starts: you draw 2 penalty cards and your declaration is cleared.
- Clearability is evaluated from **your hand only** (valid multi-card chains, penalty-card chains, etc.), **independent of the current discard top** — so it does not change if an opponent plays before your turn.
- **Must-declare / turn-start snapshots** and **AI** use that same hand-only clearability with no special case for Jokers.
- When **you** press Last Cards (offline or online), if you hold **any Joker**, you are never flagged as bluffing from the clearability check alone; AI does not get that pass.
- **Bust mode** does not use this rule.

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
- **Disconnect (standard 54-card):** A disconnect removes that player immediately (no rejoin to the same seat). If **at least two** players remain, the leaver’s hand is shuffled into the draw pile and play continues; with only one player left, the session ends.
- Note: online networking/game-sync implementation is currently in progress in this codebase.
- **Leaderboards:** Firestore collections `leaderboard_online` and `leaderboard_bust_online` are **server-written only** (Admin SDK); the client may cache increments locally for instant UI. Casual quickplay standard wins update `leaderboard_online` when the session is trophy-eligible (`!isPrivate`); online Bust finals update `leaderboard_bust_online` the same way.

### Bust Mode
- **Deck:** 52-card standard deck only (no Jokers); 2–10 players.
- **Deal:** Hand size depends on player count (e.g. 10 cards each for 2–5 players, down to 5 each for 9–10 players) — see adaptive deal table in code (`handSizeForBust`).
- **Round structure:** With **3+** active players, each takes exactly **2** turns per round and the round ends when everyone has played twice. The **final** round (exactly **2** players left) is a **race to empty hand**: play continues until someone legally sheds their last card; turn count does not end that round.
- **Scoring / elimination:** Cards left in hand at round end add to that player’s **cumulative** penalty score; the **bottom two** players by cumulative penalty are eliminated each round. In the **2-player finale**, the **empty-hand** player wins and the other is eliminated (penalty comparison is not used to pick the winner).
- **Placement pile:** When the visible discard pile reaches **5** cards, the bottom **four** are shuffled back into the draw pile, leaving only the top card showing.
- **Reconnect / disconnect (online):** With **more than two** survivors, a disconnect removes that player and play continues; if **two or fewer** survivors would remain, the session ends like a normal disconnect.
- **Win:** Last player standing after eliminations wins.
- **Implementation notes:** Offline Bust tracks the same cumulative penalties across rounds via `BustRoundManager` and reuses the same seat IDs each round (`player-local` for the human, unchanged `player-*` labels for surviving AIs via `BustEngine.buildRound(seatPlayerIds: …)`). Jokers are not present; online play must use `declare_joker` (not `play_cards`) for Jokers in standard 54-card modes.
