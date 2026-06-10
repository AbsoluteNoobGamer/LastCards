part of 'table_screen.dart';

// ── Portrait transient overlay layer ─────────────────────────────────────────
//
// Positioned above the fixed grid; reads slot [GlobalKey]s — never affects layout.

/// Bottom edge of the move-log band in overlay coordinates (null when empty).
double? _moveLogBottomPx({
  required BuildContext context,
  required List<MoveLogEntry> entries,
  required double opponentRowHeight,
  required bool hasRankedBadge,
  required bool useRail,
  required bool landscape,
}) {
  if (entries.isEmpty) return null;

  final safeTop = MediaQuery.paddingOf(context).top;
  final boardTop = landscape
      ? TablePortraitGrid.landscapeBoardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
        )
      : TablePortraitGrid.boardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
        );
  final railVisualHeight = hasRankedBadge
      ? (landscape
          ? TablePortraitGrid.landscapeOpponentRailBaseHeightWithBadge
          : TablePortraitGrid.opponentRailBaseHeightWithBadge)
      : (landscape
          ? TablePortraitGrid.landscapeOpponentRailBaseHeight
          : TablePortraitGrid.opponentRailBaseHeight);
  final opponentVisualHeight = useRail ? railVisualHeight : opponentRowHeight;
  final top = safeTop +
      (hasRankedBadge ? 28.0 : 0.0) +
      opponentVisualHeight +
      TablePortraitGrid.moveLogTopGap +
      TablePortraitGrid.moveLogTopNudge;
  final maxHeight = math.min(
    TablePortraitGrid.moveLogMaxHeight,
    math.max(
      0.0,
      boardTop +
          TablePortraitGrid.moveLogMaxHeight -
          top -
          TablePortraitGrid.moveLogBottomClearance,
    ),
  );
  if (maxHeight <= 0) return null;

  return top + maxHeight + AppDimensions.xs;
}

/// Positions [child] at [targetKey]'s [targetAnchor], aligned with [childAnchor].
class _GlobalKeyFollower extends StatefulWidget {
  const _GlobalKeyFollower({
    required this.targetKey,
    required this.child,
    this.targetAnchor = Alignment.center,
    this.childAnchor = Alignment.center,
    this.offset = Offset.zero,
    this.maxTop,
    this.minTop,
  });

  final GlobalKey targetKey;
  final Widget child;
  final Alignment targetAnchor;
  final Alignment childAnchor;
  final Offset offset;
  /// When set, caps [Positioned.top] so followers (e.g. chat bubbles) stay above
  /// the move log band.
  final double? maxTop;
  /// When set, floors [Positioned.top] so followers stay below the move log band.
  final double? minTop;

  @override
  State<_GlobalKeyFollower> createState() => _GlobalKeyFollowerState();
}

class _GlobalKeyFollowerState extends State<_GlobalKeyFollower> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_scheduleUpdate);
  }

  @override
  void didUpdateWidget(covariant _GlobalKeyFollower oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_scheduleUpdate);
  }

  void _scheduleUpdate(_) {
    if (!mounted) return;
    _updateTargetRect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTargetRect();
    });
  }

  void _updateTargetRect() {
    final targetBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return;

    final overlayBox =
        context.findAncestorRenderObjectOfType<RenderStack>();
    if (overlayBox == null || !overlayBox.hasSize) return;

    final globalTopLeft = targetBox.localToGlobal(Offset.zero);
    final topLeft = overlayBox.globalToLocal(globalTopLeft);
    final size = targetBox.size;
    final rect = topLeft & size;
    if (_targetRect != rect) {
      setState(() => _targetRect = rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _targetRect;
    if (rect == null) return const SizedBox.shrink();

    final targetPoint = Offset(
          rect.left + rect.width * (widget.targetAnchor.x + 1) / 2,
          rect.top + rect.height * (widget.targetAnchor.y + 1) / 2,
        ) +
        widget.offset;

    var top = targetPoint.dy;
    if (widget.maxTop != null) {
      top = math.min(top, widget.maxTop!);
    }
    if (widget.minTop != null) {
      top = math.max(top, widget.minTop!);
    }

    return Positioned(
      left: targetPoint.dx,
      top: top,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 360,
          maxHeight: 220,
        ),
        child: _ChildAnchorWrapper(
          anchor: widget.childAnchor,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Offsets [child] so [anchor] sits at the parent's origin (0,0).
class _ChildAnchorWrapper extends StatelessWidget {
  const _ChildAnchorWrapper({
    required this.anchor,
    required this.child,
  });

  final Alignment anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _ChildAnchorDelegate(anchor),
      child: child,
    );
  }
}

class _ChildAnchorDelegate extends SingleChildLayoutDelegate {
  _ChildAnchorDelegate(this.anchor);

  final Alignment anchor;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(
      -childSize.width * (anchor.x + 1) / 2,
      -childSize.height * (anchor.y + 1) / 2,
    );
  }

  @override
  bool shouldRelayout(covariant _ChildAnchorDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// Move log — fixed overlay below the opponent row, above board piles.
class _PortraitMoveLogOverlay extends StatelessWidget {
  const _PortraitMoveLogOverlay({
    required this.entries,
    required this.opponentRowHeight,
    required this.hasRankedBadge,
    required this.useRail,
    this.landscape = false,
  });

  final List<MoveLogEntry> entries;
  final double opponentRowHeight;
  final bool hasRankedBadge;
  final bool useRail;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final safeTop = MediaQuery.paddingOf(context).top;
    final boardTop = landscape
        ? TablePortraitGrid.landscapeBoardRegionTopPx(
            safeTop: safeTop,
            hasRankedBadge: hasRankedBadge,
            opponentRowHeight: opponentRowHeight,
          )
        : TablePortraitGrid.boardRegionTopPx(
            safeTop: safeTop,
            hasRankedBadge: hasRankedBadge,
            opponentRowHeight: opponentRowHeight,
          );
    final railVisualHeight = hasRankedBadge
        ? (landscape
            ? TablePortraitGrid.landscapeOpponentRailBaseHeightWithBadge
            : TablePortraitGrid.opponentRailBaseHeightWithBadge)
        : (landscape
            ? TablePortraitGrid.landscapeOpponentRailBaseHeight
            : TablePortraitGrid.opponentRailBaseHeight);
    final opponentVisualHeight = useRail ? railVisualHeight : opponentRowHeight;
    final top = safeTop +
        (hasRankedBadge ? 28.0 : 0.0) +
        opponentVisualHeight +
        TablePortraitGrid.moveLogTopGap +
        TablePortraitGrid.moveLogTopNudge;
    final maxHeight = math.min(
      TablePortraitGrid.moveLogMaxHeight,
      math.max(
        0.0,
        boardTop +
            TablePortraitGrid.moveLogMaxHeight -
            top -
            TablePortraitGrid.moveLogBottomClearance,
      ),
    );

    if (maxHeight <= 0) return const SizedBox.shrink();

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TablePortraitGrid.moveLogHorizontalInset,
          ),
          child: ClipRect(
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: TablePortraitGrid.moveLogMaxWidth,
                  maxHeight: maxHeight,
                ),
                child: GameMoveLogPanel(
                  entries: entries,
                  maxHeight: maxHeight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// King direction-reversal banner — same slot as the suit-lock HUD row.
class _PortraitDirectionBannerOverlay extends StatelessWidget {
  const _PortraitDirectionBannerOverlay({
    required this.direction,
    required this.kingJustPlayed,
    required this.hudKey,
  });

  final PlayDirection direction;
  final bool kingJustPlayed;
  final GlobalKey hudKey;

  @override
  Widget build(BuildContext context) {
    return _GlobalKeyFollower(
      targetKey: hudKey,
      targetAnchor: Alignment.center,
      childAnchor: Alignment.center,
      offset: const Offset(0, kDirectionReversalBannerYOffset),
      child: TurnIndicatorOverlay(
        direction: direction,
        kingJustPlayed: kingJustPlayed,
        maxWidth: kDirectionReversalBannerMaxWidth,
        bannerAlignment: Alignment.center,
      ),
    );
  }
}

/// Wraps portrait-only transient overlays (chat, direction banner).
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
    required this.quickChatBubblesByPlayer,
    required this.onRemoveQuickChatBubble,
  });

  final GameState gameState;
  final bool kingJustPlayed;
  final Map<String, GlobalKey> playerZoneKeys;
  final GlobalKey hudKey;
  final GlobalKey discardPileKey;
  final double opponentRowHeight;
  final bool hasRankedBadge;
  final List<MoveLogEntry> moveLogEntries;
  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;
  final void Function(String id)? onRemoveQuickChatBubble;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final chatBubbleMaxTop = TablePortraitGrid.boardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
        ) -
        8;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        _PortraitMoveLogOverlay(
          entries: moveLogEntries,
          opponentRowHeight: opponentRowHeight,
          hasRankedBadge: hasRankedBadge,
          useRail: gameState.players.length > 4,
        ),
        if (onRemoveQuickChatBubble != null)
          for (final entry in quickChatBubblesByPlayer.entries)
            if (playerZoneKeys[entry.key] != null)
              _GlobalKeyFollower(
                targetKey: playerZoneKeys[entry.key]!,
                targetAnchor: Alignment.bottomCenter,
                childAnchor: Alignment.topCenter,
                offset: const Offset(0, 4),
                maxTop: chatBubbleMaxTop,
                child: QuickChatBubble(
                  key: ValueKey(entry.value.id),
                  playerName: entry.value.playerName,
                  reactionWireIndex: entry.value.reactionWireIndex,
                  isLocal: entry.value.isLocal,
                  tailPointsUp: true,
                  onDismiss: () => onRemoveQuickChatBubble!(entry.value.id),
                ),
              ),
        _PortraitDirectionBannerOverlay(
          direction: gameState.direction,
          kingJustPlayed: kingJustPlayed,
          hudKey: hudKey,
        ),
        _PortraitLastCardsStripOverlay(
          players: gameState.players,
          lastCardsDeclaredBy: gameState.lastCardsDeclaredBy,
          discardPileKey: discardPileKey,
          minTop: _moveLogBottomPx(
            context: context,
            entries: moveLogEntries,
            opponentRowHeight: opponentRowHeight,
            hasRankedBadge: hasRankedBadge,
            useRail: gameState.players.length > 4,
            landscape: false,
          ),
        ),
      ],
    );
  }
}

/// Landscape transient overlays — same key-follower pattern as portrait.
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
    required this.quickChatBubblesByPlayer,
    required this.onRemoveQuickChatBubble,
  });

  final GameState gameState;
  final bool kingJustPlayed;
  final Map<String, GlobalKey> playerZoneKeys;
  final GlobalKey hudKey;
  final GlobalKey discardPileKey;
  final double opponentRowHeight;
  final bool hasRankedBadge;
  final List<MoveLogEntry> moveLogEntries;
  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;
  final void Function(String id)? onRemoveQuickChatBubble;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final chatBubbleMaxTop = TablePortraitGrid.landscapeBoardRegionTopPx(
          safeTop: safeTop,
          hasRankedBadge: hasRankedBadge,
          opponentRowHeight: opponentRowHeight,
        ) -
        8;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        _PortraitMoveLogOverlay(
          entries: moveLogEntries,
          opponentRowHeight: opponentRowHeight,
          hasRankedBadge: hasRankedBadge,
          useRail: gameState.players.length > 4,
          landscape: true,
        ),
        if (onRemoveQuickChatBubble != null)
          for (final entry in quickChatBubblesByPlayer.entries)
            if (playerZoneKeys[entry.key] != null)
              _GlobalKeyFollower(
                targetKey: playerZoneKeys[entry.key]!,
                targetAnchor: Alignment.bottomCenter,
                childAnchor: Alignment.topCenter,
                offset: const Offset(0, 4),
                maxTop: chatBubbleMaxTop,
                child: QuickChatBubble(
                  key: ValueKey(entry.value.id),
                  playerName: entry.value.playerName,
                  reactionWireIndex: entry.value.reactionWireIndex,
                  isLocal: entry.value.isLocal,
                  tailPointsUp: true,
                  onDismiss: () => onRemoveQuickChatBubble!(entry.value.id),
                ),
              ),
        _PortraitDirectionBannerOverlay(
          direction: gameState.direction,
          kingJustPlayed: kingJustPlayed,
          hudKey: hudKey,
        ),
        _PortraitLastCardsStripOverlay(
          players: gameState.players,
          lastCardsDeclaredBy: gameState.lastCardsDeclaredBy,
          discardPileKey: discardPileKey,
          minTop: _moveLogBottomPx(
            context: context,
            entries: moveLogEntries,
            opponentRowHeight: opponentRowHeight,
            hasRankedBadge: hasRankedBadge,
            useRail: gameState.players.length > 4,
            landscape: true,
          ),
        ),
      ],
    );
  }
}

/// Last Cards strip — above centre piles, below the move log when present.
class _PortraitLastCardsStripOverlay extends StatelessWidget {
  const _PortraitLastCardsStripOverlay({
    required this.players,
    required this.lastCardsDeclaredBy,
    required this.discardPileKey,
    this.minTop,
  });

  final List<PlayerModel> players;
  final Set<String> lastCardsDeclaredBy;
  final GlobalKey discardPileKey;
  final double? minTop;

  @override
  Widget build(BuildContext context) {
    if (lastCardsDeclaredBy.isEmpty) return const SizedBox.shrink();

    return _GlobalKeyFollower(
      targetKey: discardPileKey,
      targetAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      offset: const Offset(0, -AppDimensions.xs),
      minTop: minTop,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: LastCardsTableStrip(
          players: players,
          lastCardsDeclaredBy: lastCardsDeclaredBy,
          inline: true,
        ),
      ),
    );
  }
}
