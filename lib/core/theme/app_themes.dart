import 'package:flutter/material.dart';
import 'app_theme_data.dart';

/// All 10 built-in Stack & Flow themes.
///
/// Index 0 is the default (Classic Felt). Order here determines the display
/// order in [ThemeSelectorModal] and maps to the persisted index integer.
const List<AppThemeData> kAppThemes = [
  _classicFelt,
  _carbon,
  _gold,
  _midnightNavy,
  _crimsonVelvet,
  _obsidian,
  _emeraldRoyale,
  _sapphire,
  _copperNoir,
  _arctic,
];

// ── 1. Classic Felt (default) ────────────────────────────────────────────────

const _classicFelt = AppThemeData(
  id: 'classic_felt',
  name: 'Classic Felt',
  backgroundDeep: Color(0xFF0D2B1A),
  backgroundMid: Color(0xFF1A3D2B),
  accentPrimary: Color(0xFFC9A84C),
  accentLight: Color(0xFFE8CC7A),
  accentDark: Color(0xFF8A6D28),
  secondaryAccent: Color(0xFF9B2335),
  surfaceDark: Color(0xFF0A0A0A),
  surfacePanel: Color(0xFF1C2E20),
  textPrimary: Color(0xFFF5EFE0),
  textSecondary: Color(0xFFB0A080),
  cardFace: Color(0xFFFAF6ED),
  suitRed: Color(0xFF9B2335),
  suitBlack: Color(0xFF1A1A2E),
  overlayTop: Color(0x99000000),
  overlayBottom: Color(0xCC000000),
  swatchPreview: [Color(0xFF0D2B1A), Color(0xFF1A3D2B), Color(0xFFC9A84C)],
);

// ── 2. Carbon ────────────────────────────────────────────────────────────────
// Carbon-fibre aesthetic: graphite/charcoal weave, chrome silver accent.

const _carbon = AppThemeData(
  id: 'carbon',
  name: 'Carbon',
  backgroundDeep:  Color(0xFF0C0C0C),   // near-black graphite base
  backgroundMid:   Color(0xFF1C1C1F),   // charcoal panel (slight warm)
  accentPrimary:   Color(0xFFB0B8C1),   // chrome silver
  accentLight:     Color(0xFFDDE2E8),   // bright chrome highlight
  accentDark:      Color(0xFF6E7880),   // dark gunmetal
  secondaryAccent: Color(0xFF4FC3F7),   // subtle electric-blue spark
  surfaceDark:     Color(0xFF080808),   // deepest black
  surfacePanel:    Color(0xFF242428),   // woven graphite panel
  textPrimary:     Color(0xFFE8EAED),   // near-white
  textSecondary:   Color(0xFF8A8F94),   // medium grey
  cardFace:        Color(0xFFF5F5F5),   // clean white card
  suitRed:         Color(0xFFE53935),   // pure red, no tint
  suitBlack:       Color(0xFF1A1A1E),   // off-black
  overlayTop:      Color(0xCC0C0C0C),   // heavy dark overlay
  overlayBottom:   Color(0xEE080808),   // near-opaque black
  swatchPreview: [Color(0xFF0C0C0C), Color(0xFF1C1C1F), Color(0xFFB0B8C1)],
  jokerBackgroundColors: [Color(0xFF0C0C0C), Color(0xFF080808)],
  jokerBorderColor: Color(0xFF6E7880),
  jokerAccentColor: Color(0xFFB0B8C1),
);

// ── 3. Gold ──────────────────────────────────────────────────────────────────

const _gold = AppThemeData(
  id: 'gold',
  name: 'Gold',
  backgroundDeep: Color(0xFF0C0900),
  backgroundMid: Color(0xFF1A1300),
  accentPrimary: Color(0xFFFFD700),
  accentLight: Color(0xFFFFEA80),
  accentDark: Color(0xFFB8960C),
  secondaryAccent: Color(0xFFFF8C00),
  surfaceDark: Color(0xFF080600),
  surfacePanel: Color(0xFF1F1800),
  textPrimary: Color(0xFFFFF8E1),
  textSecondary: Color(0xFFBFA040),
  cardFace: Color(0xFFFFFBF0),
  suitRed: Color(0xFFFF4444),
  suitBlack: Color(0xFF0C0900),
  overlayTop: Color(0xA6000000),
  overlayBottom: Color(0xD9000000),
  swatchPreview: [Color(0xFF0C0900), Color(0xFF1A1300), Color(0xFFFFD700)],
  headingFontFamily: 'cinzel',
  jokerBackgroundColors: [Color(0xFF1A1300), Color(0xFF0C0900)],
  jokerBorderColor: Color(0xFFB8960C),
  jokerAccentColor: Color(0xFFFFD700),
);

// ── 4. Midnight Navy ─────────────────────────────────────────────────────────

const _midnightNavy = AppThemeData(
  id: 'midnight_navy',
  name: 'Midnight Navy',
  backgroundDeep: Color(0xFF050D20),
  backgroundMid: Color(0xFF0D1A38),
  accentPrimary: Color(0xFF4A90E2),
  accentLight: Color(0xFF82B4F0),
  accentDark: Color(0xFF2E5B9A),
  secondaryAccent: Color(0xFF00E5FF),
  surfaceDark: Color(0xFF020810),
  surfacePanel: Color(0xFF0F1E3A),
  textPrimary: Color(0xFFE8F0FF),
  textSecondary: Color(0xFF8099CC),
  cardFace: Color(0xFFF0F4FF),
  suitRed: Color(0xFFE84060),
  suitBlack: Color(0xFF050D20),
  overlayTop: Color(0x99000014),
  overlayBottom: Color(0xCC00000E),
  swatchPreview: [Color(0xFF050D20), Color(0xFF0D1A38), Color(0xFF4A90E2)],
  jokerBackgroundColors: [Color(0xFF050D20), Color(0xFF020810)],
  jokerBorderColor: Color(0xFF2E5B9A),
  jokerAccentColor: Color(0xFF4A90E2),
);

// ── 5. Crimson Velvet ────────────────────────────────────────────────────────

const _crimsonVelvet = AppThemeData(
  id: 'crimson_velvet',
  name: 'Crimson Velvet',
  backgroundDeep: Color(0xFF1A0408),
  backgroundMid: Color(0xFF2E0912),
  accentPrimary: Color(0xFFE8A0A0),   // rose gold-ish blush
  accentLight: Color(0xFFF5C8C8),
  accentDark: Color(0xFFA05050),
  secondaryAccent: Color(0xFFFFB347),
  surfaceDark: Color(0xFF0E0205),
  surfacePanel: Color(0xFF280810),
  textPrimary: Color(0xFFF8EAE8),
  textSecondary: Color(0xFFB08080),
  cardFace: Color(0xFFFDF5F5),
  suitRed: Color(0xFFCC2244),
  suitBlack: Color(0xFF1A0408),
  overlayTop: Color(0x991A0000),
  overlayBottom: Color(0xCC0E0000),
  swatchPreview: [Color(0xFF1A0408), Color(0xFF2E0912), Color(0xFFE8A0A0)],
  jokerBackgroundColors: [Color(0xFF1A0408), Color(0xFF0E0205)],
  jokerBorderColor: Color(0xFFA05050),
  jokerAccentColor: Color(0xFFE8A0A0),
);

// ── 6. Obsidian ──────────────────────────────────────────────────────────────

const _obsidian = AppThemeData(
  id: 'obsidian',
  name: 'Obsidian',
  backgroundDeep: Color(0xFF0D0D0F),
  backgroundMid: Color(0xFF18181C),
  accentPrimary: Color(0xFFC0C0C0),   // platinum silver
  accentLight: Color(0xFFE8E8E8),
  accentDark: Color(0xFF808080),
  secondaryAccent: Color(0xFF9B59B6),
  surfaceDark: Color(0xFF080808),
  surfacePanel: Color(0xFF1C1C22),
  textPrimary: Color(0xFFEEEEF2),
  textSecondary: Color(0xFF888896),
  cardFace: Color(0xFFF8F8FA),
  suitRed: Color(0xFFD84040),
  suitBlack: Color(0xFF0D0D0F),
  overlayTop: Color(0xA6000000),
  overlayBottom: Color(0xD9000000),
  swatchPreview: [Color(0xFF0D0D0F), Color(0xFF18181C), Color(0xFFC0C0C0)],
  jokerBackgroundColors: [Color(0xFF0D0D0F), Color(0xFF080808)],
  jokerBorderColor: Color(0xFF808080),
  jokerAccentColor: Color(0xFFC0C0C0),
);

// ── 7. Emerald Royale ────────────────────────────────────────────────────────

const _emeraldRoyale = AppThemeData(
  id: 'emerald_royale',
  name: 'Emerald Royale',
  backgroundDeep: Color(0xFF062010),
  backgroundMid: Color(0xFF0E3620),
  accentPrimary: Color(0xFFD4AF37),   // champagne gold
  accentLight: Color(0xFFEDD68A),
  accentDark: Color(0xFF997C1D),
  secondaryAccent: Color(0xFF50C878),
  surfaceDark: Color(0xFF031208),
  surfacePanel: Color(0xFF102E1C),
  textPrimary: Color(0xFFF0F8EE),
  textSecondary: Color(0xFF90B890),
  cardFace: Color(0xFFF4FBF3),
  suitRed: Color(0xFFBF1C3C),
  suitBlack: Color(0xFF062010),
  overlayTop: Color(0x99001A0A),
  overlayBottom: Color(0xCC000E05),
  swatchPreview: [Color(0xFF062010), Color(0xFF0E3620), Color(0xFFD4AF37)],
  jokerBackgroundColors: [Color(0xFF062010), Color(0xFF031208)],
  jokerBorderColor: Color(0xFF997C1D),
  jokerAccentColor: Color(0xFFD4AF37),
);

// ── 8. Sapphire ──────────────────────────────────────────────────────────────

const _sapphire = AppThemeData(
  id: 'sapphire',
  name: 'Sapphire',
  backgroundDeep: Color(0xFF050820),
  backgroundMid: Color(0xFF0A1040),
  accentPrimary: Color(0xFFE8F4FD),   // ice white / pale blue
  accentLight: Color(0xFFFFFFFF),
  accentDark: Color(0xFF9BB8D4),
  secondaryAccent: Color(0xFF2979FF),
  surfaceDark: Color(0xFF020412),
  surfacePanel: Color(0xFF0C1440),
  textPrimary: Color(0xFFEFF5FF),
  textSecondary: Color(0xFF7A99CC),
  cardFace: Color(0xFFF5F9FF),
  suitRed: Color(0xFFFF3060),
  suitBlack: Color(0xFF050820),
  overlayTop: Color(0xA6000010),
  overlayBottom: Color(0xD9000020),
  swatchPreview: [Color(0xFF050820), Color(0xFF0A1040), Color(0xFFE8F4FD)],
  headingFontFamily: 'cinzel',
  jokerBackgroundColors: [Color(0xFF050820), Color(0xFF020412)],
  jokerBorderColor: Color(0xFF9BB8D4),
  jokerAccentColor: Color(0xFFE8F4FD),
);

// ── 9. Copper Noir ───────────────────────────────────────────────────────────

const _copperNoir = AppThemeData(
  id: 'copper_noir',
  name: 'Copper Noir',
  backgroundDeep: Color(0xFF100804),
  backgroundMid: Color(0xFF1E1008),
  accentPrimary: Color(0xFFB87333),   // copper
  accentLight: Color(0xFFD4956A),
  accentDark: Color(0xFF7A4B1F),
  secondaryAccent: Color(0xFF8B4513),
  surfaceDark: Color(0xFF0A0502),
  surfacePanel: Color(0xFF1C120A),
  textPrimary: Color(0xFFF2E6D8),
  textSecondary: Color(0xFF906040),
  cardFace: Color(0xFFFAF0E6),
  suitRed: Color(0xFFAA2222),
  suitBlack: Color(0xFF100804),
  overlayTop: Color(0x99100400),
  overlayBottom: Color(0xCC080200),
  swatchPreview: [Color(0xFF100804), Color(0xFF1E1008), Color(0xFFB87333)],
  jokerBackgroundColors: [Color(0xFF100804), Color(0xFF0A0502)],
  jokerBorderColor: Color(0xFF7A4B1F),
  jokerAccentColor: Color(0xFFB87333),
);

// ── 10. Arctic ───────────────────────────────────────────────────────────────

const _arctic = AppThemeData(
  id: 'arctic',
  name: 'Arctic',
  backgroundDeep: Color(0xFF0A0E14),
  backgroundMid: Color(0xFF141C24),
  accentPrimary: Color(0xFFE8CC7A),   // pale warm gold
  accentLight: Color(0xFFF5E4A8),
  accentDark: Color(0xFFA08840),
  secondaryAccent: Color(0xFF78C8E0),
  surfaceDark: Color(0xFF060A10),
  surfacePanel: Color(0xFF161E28),
  textPrimary: Color(0xFFF0F4FA),
  textSecondary: Color(0xFF8898AA),
  cardFace: Color(0xFFF8FAFF),
  suitRed: Color(0xFFCC3344),
  suitBlack: Color(0xFF0A0E14),
  overlayTop: Color(0xA6000000),
  overlayBottom: Color(0xCC000000),
  swatchPreview: [Color(0xFF0A0E14), Color(0xFF141C24), Color(0xFFE8CC7A)],
  jokerBackgroundColors: [Color(0xFF0A0E14), Color(0xFF060A10)],
  jokerBorderColor: Color(0xFFA08840),
  jokerAccentColor: Color(0xFFE8CC7A),
);
