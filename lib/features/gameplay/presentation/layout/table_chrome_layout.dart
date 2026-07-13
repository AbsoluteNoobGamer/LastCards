import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:last_cards/core/theme/app_dimensions.dart';

/// Breakpoint helpers shared by all table layouts.
abstract final class TableChromeLayout {
  static bool isLandscapeMobile(Size size) =>
      math.min(size.width, size.height) < AppDimensions.breakpointMobile &&
      size.width > size.height;

  /// Shortest side below mobile breakpoint (typical phones, any orientation).
  static bool isCompactPhone(Size size) =>
      math.min(size.width, size.height) < AppDimensions.breakpointMobile;

  /// Single source of truth for the tablet/desktop chrome-scale multiplier
  /// — 1.0 on phones, growing toward 2.2 on large tablets. Every screen
  /// that lays out [TablePortraitGrid]-based chrome (the main table, Bust)
  /// calls this instead of each computing its own copy of the formula.
  static double scaleFor(Size size) {
    if (isCompactPhone(size)) return 1.0;
    return (math.min(size.width, size.height) / 400.0).clamp(1.0, 2.2);
  }
}

/// Fixed portrait grid slot sizes — interactive content lives here; transient
/// chrome is positioned in the overlay layer relative to these regions.
abstract final class TablePortraitGrid {
  /// Opponent row (3-slot layout): avatar + name only; chat is overlay-only.
  static const double opponentSlotHeight = 108;
  static const double opponentSlotHeightWithBadge = 124;

  /// [BustPlayerRail] base height (chat strip is reserved inside the rail).
  static const double opponentRailBaseHeight = 96;
  static const double opponentRailBaseHeightWithBadge = 112;

  /// Turn timer + floating action bar band.
  static const double actionBarHeight = 108;

  /// Gap between the board region and the action bar — clears room for the
  /// "Last cards: (names)" strip, which floats just below the HUD and would
  /// otherwise overlap the turn timer bar now that the board sits close to
  /// the action bar (see the bottom-anchored board FittedBox alignment).
  static const double boardToActionBarGap = 24;

  /// Local [PlayerZoneWidget] + hand fan.
  static const double handRegionHeight = 156;

  /// Overlay move log geometry.
  static const double moveLogHorizontalInset = 20;
  static const double moveLogMaxWidth = 300;
  static const double moveLogMaxHeight = 112;
  static const double moveLogBottomClearance = 5;
  /// Fixed gap below the opponent row / above the board region.
  static const double moveLogTopGap = 4;
  static const double moveLogTopNudge = 0;

  /// Centre-board card width (passed to pile widgets).
  static const double pileSlotWidth = 100;
  static const double pileGap = AppDimensions.md;

  /// Draw pile stays a smaller, tidy utility stack; discard is the larger
  /// "stage" where the played card lands — the two piles are deliberately
  /// asymmetric rather than mirrored twins.
  static const double drawPileCardWidth = 82;
  static const double discardPileCardWidth = 112;

  /// Draw pile [SizedBox] — fits max stack depth (5 layers × [pileStackOffset]).
  static double drawPileFootprintWidth([double cardWidth = pileSlotWidth]) {
    const maxLayers = 5;
    return cardWidth + maxLayers * AppDimensions.pileStackOffset * 2;
  }

  static double drawPileFootprintHeight([double cardWidth = pileSlotWidth]) {
    const maxLayers = 5;
    return AppDimensions.cardHeight(cardWidth) +
        maxLayers * AppDimensions.pileStackOffset * 2;
  }

  /// Discard pile [SizedBox] — same stack-depth padding as draw pile.
  static double discardPileFootprintWidth([double cardWidth = pileSlotWidth]) {
    const maxLayers = 5;
    return cardWidth + maxLayers * AppDimensions.pileStackOffset * 2;
  }

  static double discardPileFootprintHeight([double cardWidth = pileSlotWidth]) {
    const maxLayers = 5;
    return AppDimensions.cardHeight(cardWidth) +
        maxLayers * AppDimensions.pileStackOffset * 2;
  }

  /// Legacy alias used by overlay geometry (tallest pile footprint).
  static const double pileSlotHeight = 156;

  /// Overlay: corner settings / reactions — true screen edge via [SafeArea].
  static const double cornerActionsInset = AppDimensions.sm;

  /// Overlay: tournament skip chip sits above the hand region with clear gap.
  static const double skipChipGapAboveHand = AppDimensions.md;

  static double opponentRowHeight({
    required bool useRail,
    required bool hasBadges,
    double scale = 1.0,
  }) {
    if (useRail) {
      const chatReserve = 96.0;
      return ((hasBadges ? opponentRailBaseHeightWithBadge : opponentRailBaseHeight) +
              chatReserve) *
          scale;
    }
    return (hasBadges ? opponentSlotHeightWithBadge : opponentSlotHeight) * scale;
  }

  /// Y offset from safe-area top to the top of the board [Expanded] region.
  ///
  /// [opponentRowHeight] is expected to already be pre-scaled by the caller
  /// (see [TablePortraitGrid.opponentRowHeight]'s own `scale` parameter).
  static double boardRegionTopPx({
    required double safeTop,
    required bool hasRankedBadge,
    required double opponentRowHeight,
    double scale = 1.0,
  }) {
    final rankedBand = hasRankedBadge ? 28.0 * scale : 0.0;
    return safeTop + rankedBand + opponentRowHeight;
  }

  // ── Landscape mobile grid slots ───────────────────────────────────────────

  static const double landscapeOpponentSlotHeight = 94;
  static const double landscapeOpponentSlotHeightWithBadge = 106;
  static const double landscapeOpponentRailBaseHeight = 94;
  static const double landscapeOpponentRailBaseHeightWithBadge = 106;
  static const double landscapeRankedBandHeight = 26;

  /// Compact turn timer + [FloatingActionBarWidget] band.
  static const double landscapeActionBarHeight = 72;

  /// Landscape counterpart of [boardToActionBarGap].
  static const double landscapeBoardToActionBarGap = 16;

  /// Local hand fan + avatar in landscape.
  static const double landscapeHandRegionHeight = 106;

  static const double landscapePileSlotWidth = 56;
  static const double landscapePileGap = AppDimensions.sm;

  /// Landscape counterparts of [drawPileCardWidth] / [discardPileCardWidth].
  static const double landscapeDrawPileCardWidth = 46;
  static const double landscapeDiscardPileCardWidth = 64;

  static double landscapeOpponentRowHeight({
    required bool useRail,
    required bool hasBadges,
    double scale = 1.0,
  }) {
    if (useRail) {
      return (hasBadges
              ? landscapeOpponentRailBaseHeightWithBadge
              : landscapeOpponentRailBaseHeight) *
          scale;
    }
    return (hasBadges
            ? landscapeOpponentSlotHeightWithBadge
            : landscapeOpponentSlotHeight) *
        scale;
  }

  static double landscapeBoardRegionTopPx({
    required double safeTop,
    required bool hasRankedBadge,
    required double opponentRowHeight,
    double scale = 1.0,
  }) {
    final rankedBand = hasRankedBadge ? landscapeRankedBandHeight * scale : 0.0;
    return safeTop + rankedBand + opponentRowHeight;
  }

  /// Tournament skip chip — above hand region (landscape branch).
  static double landscapeSkipChipBottom(double safeBottom, {double scale = 1.0}) =>
      safeBottom +
      (landscapeHandRegionHeight + landscapeActionBarHeight + skipChipGapAboveHand) *
          scale;
}
