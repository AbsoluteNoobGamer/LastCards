part of 'table_screen.dart';

// Transient floating overlays (move log, King direction banner, Last Cards
// strip, stack-block banner) were removed in the Neon Arena table redesign.
// That feedback now lives in reserved layout slots:
//   • [MatchBroadcastHeader] — mode / LIVE / hardcore
//   • [TableEventTicker] — event announcements
//   • [DirectionSweepOverlay] — King reverse FX
//
// This part file is kept so existing `part` directives stay valid.
