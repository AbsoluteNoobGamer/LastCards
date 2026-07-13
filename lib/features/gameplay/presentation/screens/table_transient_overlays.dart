part of 'table_screen.dart';

// ── Portrait transient overlay layer ─────────────────────────────────────────
//
// Positioned above the fixed grid; reads slot [GlobalKey]s — never affects layout.
//
// The move log / stack-block banner / GlobalKeyFollower positioner
// themselves live in `../widgets/stack_block_banner_overlay.dart`, shared
// with Bust mode. What's local to this file is purely *this screen's grid
// geometry* — where its own opponent row / board region sit — used to feed
// those shared widgets their `top`/`boardTop`/`minTop` positioning inputs.

/// Where this screen's move-log band starts ([top]), and its board's top
/// edge ([boardTop]) — the cap past which the log must stop growing. Derived
/// from [TablePortraitGrid], this screen's own fixed grid constants.
({double top, double boardTop}) _moveLogGridAnchors({
  required BuildContext context,
  required double opponentRowHeight,
  required bool hasRankedBadge,
  required bool useRail,
  required bool landscape,
  double scale = 1.0,
}) {
  final safeTop = MediaQuery.paddingOf(context).top;
  final boardTop = landscape
      ? TablePortraitGrid.landscapeBoardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
          scale: scale,
        )
      : TablePortraitGrid.boardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
          scale: scale,
        );
  final railVisualHeight = (hasRankedBadge
          ? (landscape
              ? TablePortraitGrid.landscapeOpponentRailBaseHeightWithBadge
              : TablePortraitGrid.opponentRailBaseHeightWithBadge)
          : (landscape
              ? TablePortraitGrid.landscapeOpponentRailBaseHeight
              : TablePortraitGrid.opponentRailBaseHeight)) *
      scale;
  final opponentVisualHeight = useRail ? railVisualHeight : opponentRowHeight;
  final top = safeTop +
      (hasRankedBadge ? 28.0 * scale : 0.0) +
      opponentVisualHeight +
      (TablePortraitGrid.moveLogTopGap + TablePortraitGrid.moveLogTopNudge) * scale;
  return (top: top, boardTop: boardTop);
}

/// Horizontal distance from the discard pile's own centre to the true centre
/// of the draw+discard pile row (the row is centered as a whole, but the
/// discard pile — the wider of the two — sits right of that midpoint).
/// Negative: the row's true centre is left of the discard pile's centre.
double _pileRowCenterOffsetFromDiscardCenter({
  required bool landscape,
  double scale = 1.0,
}) {
  final drawWidth = (landscape
          ? TablePortraitGrid.landscapeDrawPileCardWidth
          : TablePortraitGrid.drawPileCardWidth) *
      scale;
  final discardWidth = (landscape
          ? TablePortraitGrid.landscapeDiscardPileCardWidth
          : TablePortraitGrid.discardPileCardWidth) *
      scale;
  final gap = (landscape ? TablePortraitGrid.landscapePileGap : TablePortraitGrid.pileGap) *
      scale;

  final drawFootprint = TablePortraitGrid.drawPileFootprintWidth(drawWidth);
  final discardFootprint =
      TablePortraitGrid.discardPileFootprintWidth(discardWidth);
  final rowCenter = (drawFootprint + gap + discardFootprint) / 2;
  final discardCenter = drawFootprint + gap + discardFootprint / 2;
  return rowCenter - discardCenter;
}

/// King direction-reversal banner — same slot as the suit-lock HUD row.
class _PortraitDirectionBannerOverlay extends StatelessWidget {
  const _PortraitDirectionBannerOverlay({
    required this.direction,
    required this.kingJustPlayed,
    required this.hudKey,
    this.minTop,
    this.scale = 1.0,
  });

  final PlayDirection direction;
  final bool kingJustPlayed;
  final GlobalKey hudKey;

  /// Floors the banner's top so it stays below the move log band — the
  /// stack-block banner and Last Cards strip already have this defense;
  /// this was the one overlay missing it.
  final double? minTop;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return GlobalKeyFollower(
      targetKey: hudKey,
      targetAnchor: Alignment.center,
      childAnchor: Alignment.center,
      offset: Offset(0, kDirectionReversalBannerYOffset * scale),
      minTop: minTop,
      scale: scale,
      child: TurnIndicatorOverlay(
        direction: direction,
        kingJustPlayed: kingJustPlayed,
        maxWidth: kDirectionReversalBannerMaxWidth,
        bannerAlignment: Alignment.center,
        scale: scale,
      ),
    );
  }
}

/// Wraps portrait-only transient overlays (move log, direction banner, Last
/// Cards strip). Quick-chat bubbles are no longer rendered here — they're
/// docked inline under each player's name/avatar instead (via
/// [PlayerZoneWidget.chatBubble] / [BustPlayerRail.quickChatBubblesByPlayer]),
/// matching Bust mode, so it's unambiguous who sent a reaction instead of a
/// loosely-positioned floating bubble.
class _PortraitTransientOverlayLayer extends StatelessWidget {
  const _PortraitTransientOverlayLayer({
    required this.gameState,
    required this.kingJustPlayed,
    required this.playerZoneKeys,
    required this.hudKey,
    required this.discardPileKey,
    required this.opponentRowHeight,
    required this.hasRankedBadge,
    required this.moveLogEntries,
    required this.appTheme,
    this.stackBlockBannerText,
    this.stackBlockBannerColor,
    this.scale = 1.0,
  });

  final GameState gameState;
  final bool kingJustPlayed;
  final Map<String, GlobalKey> playerZoneKeys;
  final GlobalKey hudKey;
  final GlobalKey discardPileKey;
  final double opponentRowHeight;
  final bool hasRankedBadge;
  final List<MoveLogEntry> moveLogEntries;
  final AppThemeData appTheme;
  final String? stackBlockBannerText;
  final Color? stackBlockBannerColor;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final useRail = gameState.players.length > 4;
    final moveLogAnchors = _moveLogGridAnchors(
      context: context,
      opponentRowHeight: opponentRowHeight,
      hasRankedBadge: hasRankedBadge,
      useRail: useRail,
      landscape: false,
      scale: scale,
    );
    final moveLogBottom = moveLogBottomPx(
      entries: moveLogEntries,
      top: moveLogAnchors.top,
      boardTop: moveLogAnchors.boardTop,
      scale: scale,
    );

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        MoveLogOverlay(
          entries: moveLogEntries,
          top: moveLogAnchors.top,
          boardTop: moveLogAnchors.boardTop,
          scale: scale,
        ),
        _PortraitDirectionBannerOverlay(
          direction: gameState.direction,
          kingJustPlayed: kingJustPlayed,
          hudKey: hudKey,
          minTop: moveLogBottom,
          scale: scale,
        ),
        _PortraitLastCardsStripOverlay(
          players: gameState.players,
          lastCardsDeclaredBy: gameState.lastCardsDeclaredBy,
          hudKey: hudKey,
          minTop: moveLogBottom,
          scale: scale,
        ),
        if (stackBlockBannerText != null)
          StackBlockBannerOverlay(
            text: stackBlockBannerText!,
            color: stackBlockBannerColor!,
            appTheme: appTheme,
            discardPileKey: discardPileKey,
            centerOffsetX:
                _pileRowCenterOffsetFromDiscardCenter(landscape: false, scale: scale),
            minTop: moveLogBottom,
            scale: scale,
          ),
      ],
    );
  }
}

/// Landscape transient overlays — same key-follower pattern as portrait.
/// Quick-chat bubbles are docked inline (see [_PortraitTransientOverlayLayer]
/// doc comment) rather than rendered here.
class _LandscapeTransientOverlayLayer extends StatelessWidget {
  const _LandscapeTransientOverlayLayer({
    required this.gameState,
    required this.kingJustPlayed,
    required this.playerZoneKeys,
    required this.hudKey,
    required this.discardPileKey,
    required this.opponentRowHeight,
    required this.hasRankedBadge,
    required this.moveLogEntries,
    required this.appTheme,
    this.stackBlockBannerText,
    this.stackBlockBannerColor,
    this.scale = 1.0,
  });

  final GameState gameState;
  final bool kingJustPlayed;
  final Map<String, GlobalKey> playerZoneKeys;
  final GlobalKey hudKey;
  final GlobalKey discardPileKey;
  final double opponentRowHeight;
  final bool hasRankedBadge;
  final List<MoveLogEntry> moveLogEntries;
  final AppThemeData appTheme;
  final String? stackBlockBannerText;
  final Color? stackBlockBannerColor;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final useRail = gameState.players.length > 4;
    final moveLogAnchors = _moveLogGridAnchors(
      context: context,
      opponentRowHeight: opponentRowHeight,
      hasRankedBadge: hasRankedBadge,
      useRail: useRail,
      landscape: true,
      scale: scale,
    );
    final moveLogBottom = moveLogBottomPx(
      entries: moveLogEntries,
      top: moveLogAnchors.top,
      boardTop: moveLogAnchors.boardTop,
      scale: scale,
    );

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        MoveLogOverlay(
          entries: moveLogEntries,
          top: moveLogAnchors.top,
          boardTop: moveLogAnchors.boardTop,
          scale: scale,
        ),
        _PortraitDirectionBannerOverlay(
          direction: gameState.direction,
          kingJustPlayed: kingJustPlayed,
          hudKey: hudKey,
          minTop: moveLogBottom,
          scale: scale,
        ),
        _PortraitLastCardsStripOverlay(
          players: gameState.players,
          lastCardsDeclaredBy: gameState.lastCardsDeclaredBy,
          hudKey: hudKey,
          minTop: moveLogBottom,
          scale: scale,
        ),
        if (stackBlockBannerText != null)
          StackBlockBannerOverlay(
            text: stackBlockBannerText!,
            color: stackBlockBannerColor!,
            appTheme: appTheme,
            discardPileKey: discardPileKey,
            centerOffsetX:
                _pileRowCenterOffsetFromDiscardCenter(landscape: true, scale: scale),
            minTop: moveLogBottom,
            scale: scale,
          ),
      ],
    );
  }
}

/// Last Cards strip — below the suit-lock HUD row.
class _PortraitLastCardsStripOverlay extends StatelessWidget {
  const _PortraitLastCardsStripOverlay({
    required this.players,
    required this.lastCardsDeclaredBy,
    required this.hudKey,
    this.minTop,
    this.scale = 1.0,
  });

  final List<PlayerModel> players;
  final Set<String> lastCardsDeclaredBy;
  final GlobalKey hudKey;
  final double? minTop;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (lastCardsDeclaredBy.isEmpty) return const SizedBox.shrink();

    return GlobalKeyFollower(
      targetKey: hudKey,
      targetAnchor: Alignment.bottomCenter,
      childAnchor: Alignment.topCenter,
      offset: Offset(0, AppDimensions.xs * scale),
      minTop: minTop,
      scale: scale,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340 * scale),
        child: LastCardsTableStrip(
          players: players,
          lastCardsDeclaredBy: lastCardsDeclaredBy,
          inline: true,
          scale: scale,
        ),
      ),
    );
  }
}
