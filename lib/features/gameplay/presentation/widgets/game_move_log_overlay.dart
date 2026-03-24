import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';

import 'last_move_panel_widget.dart';

/// Centred move log panel below player avatars — same layout as single-player
/// [TableScreen] (online and offline).
///
/// Parent must wrap in [Stack] and only include when [entries] is non-empty.
class GameMoveLogOverlay extends StatelessWidget {
  const GameMoveLogOverlay({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscapeMobile =
            math.min(constraints.maxWidth, constraints.maxHeight) <
                    AppDimensions.breakpointMobile &&
                constraints.maxWidth > constraints.maxHeight;
        final media = MediaQuery.of(context);
        return Positioned(
          top: media.padding.top + (isLandscapeMobile ? 72 : 175),
          left: media.size.width * 0.08,
          right: media.size.width * 0.08,
          child: IgnorePointer(
            child: Container(
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
          ),
        );
      },
    );
  }
}
