/// Spacing, sizing, border radii and responsive breakpoints for Stack & Flow.
abstract final class AppDimensions {
  // ── Spacing scale ────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // ── Border radii ─────────────────────────────────────────────────
  static const double radiusCard = 8;
  static const double radiusButton = 4;
  static const double radiusModal = 12;

  // ── Card dimensions ──────────────────────────────────────────────
  /// Aspect ratio width:height = 5:7 (standard playing card)
  static const double cardAspectRatio = 5 / 7;

  static const double cardWidthSmall = 50; // mobile condensed
  static const double cardWidthMedium = 72; // tablet / hand fan
  static const double cardWidthLarge = 90; // desktop

  // Specific table pile overrides
  static const double cardWidthDrawPile = 160;
  static const double cardWidthDiscardTop = 200;

  static double cardHeight(double width) => width / cardAspectRatio;

  // ── Hand fan overlap ─────────────────────────────────────────────
  static const double handCardOverlap = 28; // px overlap between fanned cards

  // ── Turn indicator ───────────────────────────────────────────────
  static const double turnGlowRadius = 12;
  static const double turnRingWidth = 3;

  // ── Minimum touch target ─────────────────────────────────────────
  static const double minTouchTarget = 44;

  // ── Responsive breakpoints ───────────────────────────────────────
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 1024;

  // ── Pile offsets (stacked card effect) ───────────────────────────
  static const double pileStackOffset = 2.0; // px per card layer
  static const int pileStackLayers = 3;

  // ── HUD ──────────────────────────────────────────────────────────
  static const double penaltyBadgeSize = 24;
}
