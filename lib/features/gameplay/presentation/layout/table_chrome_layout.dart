import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:last_cards/core/theme/app_dimensions.dart';

/// Shared table chrome geometry for [TableScreen], offline Bust, and any future
/// full-table layouts — keeps HUD, floating move log, corner stacks, and pile
/// nudges visually aligned across modes.
abstract final class TableChromeLayout {
  static bool isLandscapeMobile(Size size) =>
      math.min(size.width, size.height) < AppDimensions.breakpointMobile &&
      size.width > size.height;

  /// Shortest side below mobile breakpoint (typical phones, any orientation).
  static bool isCompactPhone(Size size) =>
      math.min(size.width, size.height) < AppDimensions.breakpointMobile;

  static const double hudTopFractionOfScreenHeight = 0.63;
  static const double hudTopPixelAdjust = -1.0;

  /// Matches main table HUD [Positioned.top] (full-screen height, not layout inset).
  static double hudOverlayTopPx(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return h * hudTopFractionOfScreenHeight + hudTopPixelAdjust;
  }

  static const double cornerActionsBottomPortrait = 210;
  static const double cornerActionsBottomLandscape = 130;

  static double cornerActionsBottom(Size layoutSize) =>
      isLandscapeMobile(layoutSize)
          ? cornerActionsBottomLandscape
          : cornerActionsBottomPortrait;

  static const double tournamentSkipChipBottomPortrait = 208;
  static const double tournamentSkipChipBottomLandscape = 128;

  static double tournamentSkipChipBottom(Size layoutSize) =>
      isLandscapeMobile(layoutSize)
          ? tournamentSkipChipBottomLandscape
          : tournamentSkipChipBottomPortrait;

  static const Alignment directionBannerAlignment = Alignment(0, 0.22);

  /// Portrait column layout: slight downward nudge for draw/discard cluster.
  static const Offset drawDiscardClusterNudgeCompact = Offset(0, 0.5);

  // ── Move log (floating overlay) ─────────────────────────────────────────
  static const double moveLogHorizontalInsetFraction = 0.08;

  static double moveLogTopInsetBelowSafeAreaPx(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (isLandscapeMobile(size)) return 96;
    return 200;
  }
}
