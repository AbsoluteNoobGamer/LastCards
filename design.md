# Stack & Flow — Design & Theme Specification

## Brand Identity

**Stack & Flow** is a premium competitive card game. Every design decision should reinforce three core feelings: **prestige**, **tension**, and **control**. The visual language draws from high-end casino culture — not the neon excess of Las Vegas, but the quiet, deliberate atmosphere of a private members' club where the stakes are real and every play matters.

The experience should feel mature, strategic, and polished. Never playful. Never cartoonish.

---

## Color Palette

### Primary Backgrounds

| Token | Hex | Usage |
|---|---|---|
| `felt-deep` | `#0D2B1A` | Primary table felt background |
| `felt-mid` | `#1A3D2B` | Secondary surface, card zones |
| `burgundy-deep` | `#2B0D17` | Alternate table variant |
| `burgundy-mid` | `#3D1A24` | Alternate secondary surface |

### Accent Colors

| Token | Hex | Usage |
|---|---|---|
| `gold-primary` | `#C9A84C` | Active player glow, UI highlights, borders |
| `gold-light` | `#E8CC7A` | Hover states, card selection shimmer |
| `gold-dark` | `#8A6D28` | Subtle accents, inactive dividers |
| `red-accent` | `#9B2335` | Red Jack effect, danger states, suit icons |
| `red-soft` | `#C0392B` | Warning indicators |

### UI Neutrals

| Token | Hex | Usage |
|---|---|---|
| `text-primary` | `#F5EFE0` | Primary readable text (warm white) |
| `text-secondary` | `#B0A080` | Labels, secondary information |
| `surface-dark` | `#0A0A0A` | Overlays, modals |
| `surface-panel` | `#1C1C1C` | UI panels, HUD backgrounds |

---

## Typography

| Role | Typeface | Weight | Notes |
|---|---|---|---|
| Game Title / Logo | Playfair Display or Cormorant Garamond | Bold | Serif — conveys prestige |
| Headings | Playfair Display | SemiBold | Consistent with brand voice |
| UI Labels | Inter or DM Sans | Medium | Clean, legible at small sizes |
| Card Ranks | Custom or Libre Baskerville | Bold | Large, high-contrast, unambiguous |
| Suit Symbols | SVG icon set | — | Crisp at all resolutions |

All typography should be set with generous letter-spacing at display sizes. Avoid tight, compressed type. The goal is legibility and elegance, not density.

---

## Table Layout

The play area is presented as a **top-down view of a casino table** with a consistent, clear spatial hierarchy.

### Layout Zones

```
┌─────────────────────────────────────────────────┐
│              Opponent 3 (top)                   │
│                                                 │
│  Opponent 2       [ DRAW ]  [ DISCARD ]  Opp 4 │
│  (left)                                 (right) │
│                                                 │
│              [ LOCAL PLAYER ]                   │
└─────────────────────────────────────────────────┘
```

- **Discard pile** — centered on the table, always visible and prominent
- **Draw pile** — positioned immediately beside the discard pile; shows a stacked card effect indicating remaining count
- **Player hand** — local player's cards fanned along the bottom edge
- **Opponent hands** — face-down card fans positioned at their table position (top, left, right for 2–4 players)
- **Turn indicator** — active player position is highlighted with a soft gold glow ring around their card zone

### Table Surface

The felt texture should have:

- Subtle micro-texture for depth (not a flat fill)
- Soft vignette darkening toward table edges
- A faint inner highlight ring suggesting an overhead light source

---

## Card Design

Cards follow the traditional 52-card deck format with the aesthetic refinement of a high-end playing card manufacturer.

### Standard Card Anatomy

- **Face:** Cream or warm white background (`#FAF6ED`)
- **Rank:** Bold, large numerals in the top-left and bottom-right corners
- **Suit icon:** Centered pip icon, scaled appropriately for each rank
- **Corner pips:** Small rank + suit repeated at corners
- **Shadow:** Soft drop shadow to create depth above the table surface

### Suits

| Suit | Color |
|---|---|
| Spades ♠ | Deep charcoal (`#1A1A2E`) |
| Clubs ♣ | Deep charcoal (`#1A1A2E`) |
| Hearts ♥ | Rich crimson (`#9B2335`) |
| Diamonds ♦ | Rich crimson (`#9B2335`) |

### Joker Design

The Jokers should read as premium and slightly dramatic — a step above the standard deck.

- Dark background card (inverts the standard white face)
- Gold foil-style typography for "JOKER"
- Stylized jester motif — geometric and angular, not cartoonish
- Subtle iridescent shimmer on the card face
- Distinct from all other cards at a glance

### Card Back

- Deep green or burgundy base matching table palette
- Gold geometric border pattern (diamond lattice or art deco motif)
- Centered emblem (crown, crest, or abstract mark)
- The back should look premium enough to be mistaken for real playing cards

---

## Animation System

All animations target **60fps** and are tuned to feel weighted and satisfying — not instant, not sluggish.

### Card Play Animations

| Interaction | Animation | Duration |
|---|---|---|
| Card selected from hand | Subtle lift (translate Y –8px) + gold shimmer outline | 150ms ease-out |
| Card played to discard | Smooth slide arc from hand position to center pile | 300ms ease-in-out |
| Card drawn from pile | Slide from draw pile into hand, fan reflows | 250ms ease-out |
| Card flip (reveal) | 3D Y-axis flip, back to face | 400ms ease-in-out |
| Hand reflow | Cards slide to new positions when one is played | 200ms ease-out |

### Special Card Effects

| Card | Effect |
|---|---|
| **2 / Black Jack** | Card slams into pile with sharp deceleration. Table surface pulses once with a subtle vibration ripple. |
| **Red Jack** | Warm red radial pulse emanates from card on landing. Active penalty counter fades out. |
| **King** | Turn direction arrow rotates 180° smoothly around the table perimeter. |
| **Ace** | Elegant suit-selection overlay fades in. Four suit icons are presented in a radial layout. Selected suit pulses gold before overlay dismisses. |
| **Queen** | Active suit icon appears on the table surface with a glowing gold ring. Persists until the lock breaks. |
| **8** | Skipped player's card zone dims to ~40% opacity. A subtle "pause" icon appears briefly. |
| **Joker** | Card performs a dramatic slow flip. Brief spotlight cone narrows on the card. Player declaration UI fades in. |

Effects are purposefully restrained — impactful but never distracting. The effect should serve the gameplay information, not overshadow it.

---

## UI Components

### HUD (Heads-Up Display)

- Minimal chrome — no unnecessary borders or decoration
- Card counts displayed as a small number badge on each player's hand zone
- Turn timer shown as a thin arc progress ring around the active player indicator (gold)
- Active effects (penalty stack count, suit lock icon) displayed in the center table area near the discard pile

### Modals & Overlays

- Background dims to `rgba(0, 0, 0, 0.75)` with a blur effect
- Modal surface uses `surface-panel` with a gold border at 1px
- All overlays animate in with a subtle scale-up (0.95 → 1.0) and fade

### Buttons

- Primary action: Gold fill (`gold-primary`), dark text, rounded corners (4px radius)
- Secondary: Transparent with gold border, gold text
- Destructive: `red-accent` fill
- Hover states: Lighten 10%, cursor changes to pointer
- Disabled states: 40% opacity, no hover effect

### Notifications & Turn Alerts

- "Your Turn" alert: Gentle pulse glow on hand zone + soft chime sound
- Penalty incoming: Red border flash on affected player zone
- Win state: Full-table gold shimmer cascade, elegant victory modal

---

## Sound Design

All sound should reinforce the **luxury lounge** atmosphere. Volume levels default to moderate; all categories independently adjustable in settings.

| Event | Sound Description |
|---|---|
| Ambient background | Soft jazz or low lounge ambience, instrumental only |
| Card slide (play) | Crisp cloth-on-felt card slide |
| Card draw | Softer card lift sound |
| Penalty trigger | Weighted chip or token drop sound |
| Your turn | Gentle single chime or soft bell |
| Special card effect | Unique tonal accent per card type (subtle, not jarring) |
| Win | Short elegant fanfare — restrained, not celebratory excess |

All sounds should use a reverb/room profile consistent with a felt-lined enclosed space.

---

## Responsive Layout

| Breakpoint | Layout Adjustments |
|---|---|
| Mobile (< 600px) | Table fills screen. Player hand scrollable. HUD condensed. Opponent hands collapsed to card-count badges. |
| Tablet (600px–1024px) | Full table layout. Comfortable card sizing. HUD expanded. |
| Desktop / Web (> 1024px) | Full layout. Wider card spacing. Optional sidebar for game log. |

Card sizes scale proportionally. Touch targets are never smaller than 44×44px on mobile.

---

## Accessibility

- All UI text meets WCAG AA contrast ratios against their backgrounds
- Card suit colors are not the only differentiator — suit icons are distinct in shape
- Animation intensity can be reduced via a "Reduce Motion" setting
- Font sizes respect system accessibility settings on mobile

---

## Design Anti-Patterns (Do Not)

- Do not use bright, saturated backgrounds
- Do not use rounded, bubbly typography
- Do not use comic or illustrative card art styles
- Do not use confetti, star bursts, or exaggerated celebratory animations
- Do not overcrowd the table with UI chrome
- Do not use sound effects that are jarring, cartoonish, or dissonant with the lounge atmosphere

---

*Stack & Flow — Design & Theme Specification v1.0*
