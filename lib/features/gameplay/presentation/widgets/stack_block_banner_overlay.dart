import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/core/theme/app_theme_data.dart';
import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';

import 'game_move_log_overlay.dart';

/// Shared transient-overlay widgets for the move log and stack-block banner
/// ("+2 added to the stack!" etc.) — used by every game mode (TableScreen's
/// offline/online/tournament play and Bust) so all of them show the exact
/// same widgets, not per-mode reimplementations. Each mode supplies its own
/// positioning inputs (its opponent-rail/HUD area differs), but the actual
/// rendering, clipping, and follow-the-pile behavior is one implementation.

// ── Move log ─────────────────────────────────────────────────────────────────

/// Move-log band geometry: where it starts ([top]) and how tall it may grow
/// ([maxHeight]) before it would start overlapping the board below.
({double top, double maxHeight})? moveLogGeometry({
  required List<MoveLogEntry> entries,
  required double top,
  required double boardTop,
}) {
  if (entries.isEmpty) return null;
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
  return (top: top, maxHeight: maxHeight);
}

/// Bottom edge of the move-log band (null when [entries] is empty or the
/// band has no room to show) — used as a `minTop` floor for other overlays
/// (Last Cards strip, stack-block banner) so they never sit above the log.
double? moveLogBottomPx({
  required List<MoveLogEntry> entries,
  required double top,
  required double boardTop,
}) {
  final geometry = moveLogGeometry(entries: entries, top: top, boardTop: boardTop);
  if (geometry == null) return null;
  return geometry.top + geometry.maxHeight + AppDimensions.xs;
}

/// Move log — fixed overlay, positioned by the caller via [top]/[boardTop]
/// (each mode computes these from its own layout).
class MoveLogOverlay extends StatelessWidget {
  const MoveLogOverlay({
    super.key,
    required this.entries,
    required this.top,
    required this.boardTop,
  });

  final List<MoveLogEntry> entries;
  final double top;
  final double boardTop;

  @override
  Widget build(BuildContext context) {
    final geometry = moveLogGeometry(entries: entries, top: top, boardTop: boardTop);
    if (geometry == null) return const SizedBox.shrink();

    return Positioned(
      top: geometry.top,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TablePortraitGrid.moveLogHorizontalInset,
          ),
          child: ClipRect(
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: TablePortraitGrid.moveLogMaxWidth,
                  maxHeight: geometry.maxHeight,
                ),
                child: GameMoveLogPanel(
                  entries: entries,
                  maxHeight: geometry.maxHeight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── GlobalKey-following positioner ────────────────────────────────────────────

/// Positions [child] at [targetKey]'s [targetAnchor], aligned with [childAnchor].
class GlobalKeyFollower extends StatefulWidget {
  const GlobalKeyFollower({
    super.key,
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
  State<GlobalKeyFollower> createState() => _GlobalKeyFollowerState();
}

class _GlobalKeyFollowerState extends State<GlobalKeyFollower> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_scheduleUpdate);
  }

  @override
  void didUpdateWidget(covariant GlobalKeyFollower oldWidget) {
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

    final overlayBox = context.findAncestorRenderObjectOfType<RenderStack>();
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

// ── Stack-block banner ────────────────────────────────────────────────────────

/// Picks the stack-block banner text/color for [playedCard], or null if this
/// play doesn't warrant a banner. Shared across every mode so the wording
/// and triggers stay identical everywhere.
({String text, Color color})? stackBlockBannerMessageFor({
  required GameState beforeState,
  required GameState afterState,
  required CardModel playedCard,
  required bool isLocal,
  String? playerName,
}) {
  final chainWasActive =
      beforeState.activePenaltyCount > 0 || beforeState.penaltyChainLive;
  final name = playerName?.split(' ').first ?? 'Player';

  if (playedCard.effectiveRank == Rank.two) {
    return (
      text: isLocal ? '+2 added to the stack!' : '$name added +2 to the stack!',
      color: const Color(0xFFE53935),
    );
  }
  if (playedCard.effectiveRank == Rank.jack && !playedCard.suit.isRed) {
    return (
      text: isLocal ? '+5 added to the stack!' : '$name added +5 to the stack!',
      color: const Color(0xFFE53935),
    );
  }
  if (playedCard.effectiveRank == Rank.jack && playedCard.suit.isRed) {
    return (
      text: isLocal ? 'Pick up cancelled!' : '$name cancelled the pick up!',
      color: AppColors.goldPrimary,
    );
  }
  if (chainWasActive &&
      afterState.activePenaltyCount == 0 &&
      !afterState.penaltyChainLive) {
    return (
      text: isLocal ? 'Stack cancelled!' : '$name cancelled the stack!',
      color: AppColors.goldPrimary,
    );
  }
  return null;
}

/// Stack-block banner ("+2 added to the stack!" etc.) — floats just above the
/// pile row, floored by [minTop] so it never climbs above the move log.
///
/// Anchored to [discardPileKey]; [centerOffsetX] shifts it so it centers on
/// the whole draw+discard pile row rather than just the discard pile (pass
/// `0` when the two piles are the same width and already share a centre —
/// e.g. Bust — or the row's true-centre offset when they're asymmetric).
class StackBlockBannerOverlay extends StatelessWidget {
  const StackBlockBannerOverlay({
    super.key,
    required this.text,
    required this.color,
    required this.appTheme,
    required this.discardPileKey,
    this.centerOffsetX = 0.0,
    this.minTop,
  });

  final String text;
  final Color color;
  final AppThemeData appTheme;
  final GlobalKey discardPileKey;
  final double centerOffsetX;
  final double? minTop;

  @override
  Widget build(BuildContext context) {
    return GlobalKeyFollower(
      targetKey: discardPileKey,
      targetAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      offset: Offset(centerOffsetX, -10),
      minTop: minTop,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: appTheme.surfacePanel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
