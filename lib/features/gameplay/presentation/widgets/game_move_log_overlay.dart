import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';

import 'last_move_panel_widget.dart';

/// Styled panel for recent moves (newest first, capped in [LastMovePanelWidget]).
class GameMoveLogPanel extends StatelessWidget {
  const GameMoveLogPanel({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 140),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        child: LastMovePanelWidget(entries: entries),
      ),
    );
  }
}

/// Floating move log — centred horizontally, anchored from the safe-area top.
///
/// Previously used `+175` / `+72` below padding; nudged **down** slightly (`+200` / `+96`)
/// so it sits a bit lower without overlapping the centre HUD on typical phones.
class GameMoveLogOverlay extends StatelessWidget {
  const GameMoveLogOverlay({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  static double _topOffsetPx(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscapeMobile =
        math.min(size.width, size.height) < AppDimensions.breakpointMobile &&
            size.width > size.height;
    // Portrait: was 175 — a bit lower on screen.
    // Landscape mobile: was 72 — same nudge.
    return isLandscapeMobile ? 96 : 200;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    return Positioned(
      top: media.padding.top + _topOffsetPx(context),
      left: size.width * 0.08,
      right: size.width * 0.08,
      child: GameMoveLogPanel(entries: entries),
    );
  }
}
