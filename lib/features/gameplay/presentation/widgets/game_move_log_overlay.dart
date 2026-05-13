import 'package:flutter/material.dart';

import 'package:last_cards/core/models/move_log_entry.dart';

import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';

import 'last_move_panel_widget.dart';

/// Styled panel for recent moves (newest first, capped in [LastMovePanelWidget]).
class GameMoveLogPanel extends StatelessWidget {
  const GameMoveLogPanel({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return FractionalTranslation(
      translation: const Offset(0, -0.5),
      child: IgnorePointer(
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
      ),
    );
  }
}

/// Floating move log — centred horizontally, anchored from the safe-area top.
///
/// Geometry matches offline Bust and [TableScreen] via [TableChromeLayout].
/// [GameMoveLogPanel] applies the same fractional upward shift as centre piles
/// (`FractionalTranslation` −0.5 of panel height).
class GameMoveLogOverlay extends StatelessWidget {
  const GameMoveLogOverlay({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    return Positioned(
      top: media.padding.top +
          TableChromeLayout.moveLogTopInsetBelowSafeAreaPx(context),
      left: size.width * TableChromeLayout.moveLogHorizontalInsetFraction,
      right: size.width * TableChromeLayout.moveLogHorizontalInsetFraction,
      child: GameMoveLogPanel(entries: entries),
    );
  }
}
