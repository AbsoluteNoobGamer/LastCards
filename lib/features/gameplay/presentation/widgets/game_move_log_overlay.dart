import 'package:flutter/material.dart';

import 'package:last_cards/core/models/move_log_entry.dart';
import 'package:last_cards/core/models/move_log_merge.dart';

import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';

import 'last_move_panel_widget.dart';

/// Styled panel for recent moves (newest first, capped in [LastMovePanelWidget]).
class GameMoveLogPanel extends StatelessWidget {
  const GameMoveLogPanel({
    super.key,
    required this.entries,
    this.maxHeight = 140,
    this.scale = 1.0,
    this.maxVisible = 3,
    this.interactive = false,
    this.fillHeight = false,
    this.maxWidth,
  });

  final List<MoveLogEntry> entries;
  final double maxHeight;
  final double scale;

  /// Cap on rendered lines. Use [kMoveLogMaxEntries] when expanded.
  final int maxVisible;

  /// When true, the list can scroll / receive taps (expanded band).
  final bool interactive;

  /// When true, expands to the parent height instead of hugging content.
  final bool fillHeight;

  /// Optional width cap. Null uses the table chrome default.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      physics: interactive
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: LastMovePanelWidget(
        entries: entries,
        scale: scale,
        maxVisible: maxVisible,
      ),
    );

    final Widget panel;
    if (fillHeight) {
      panel = SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * scale,
            vertical: 6 * scale,
          ),
          child: scrollView,
        ),
      );
    } else {
      panel = Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? TablePortraitGrid.moveLogMaxWidth * scale,
          maxHeight: maxHeight,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 10 * scale,
          vertical: 6 * scale,
        ),
        child: scrollView,
      );
    }

    if (interactive) return panel;
    return IgnorePointer(child: panel);
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
