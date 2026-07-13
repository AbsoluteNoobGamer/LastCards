import 'package:flutter/material.dart';

import 'package:last_cards/core/models/move_log_entry.dart';

import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';

import 'last_move_panel_widget.dart';

/// Styled panel for recent moves (newest first, capped in [LastMovePanelWidget]).
class GameMoveLogPanel extends StatelessWidget {
  const GameMoveLogPanel({
    super.key,
    required this.entries,
    this.maxHeight = 140,
    this.scale = 1.0,
  });

  final List<MoveLogEntry> entries;
  final double maxHeight;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: TablePortraitGrid.moveLogMaxWidth * scale,
          maxHeight: maxHeight,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 10 * scale,
          vertical: 6 * scale,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: LastMovePanelWidget(entries: entries, scale: scale),
        ),
      ),
    );
  }
}

/// Floating move log — legacy screen-fraction positioning (landscape / Bust).
class GameMoveLogOverlay extends StatelessWidget {
  const GameMoveLogOverlay({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    return Positioned(
      top: media.padding.top +
          (TableChromeLayout.isLandscapeMobile(size) ? 96.0 : 200.0),
      left: size.width * 0.08,
      right: size.width * 0.08,
      child: GameMoveLogPanel(entries: entries),
    );
  }
}
