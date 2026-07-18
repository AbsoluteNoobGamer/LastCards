import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/move_log_entry.dart';
import '../../../../core/providers/theme_provider.dart';
import 'game_move_log_overlay.dart';
import 'table_event_ticker.dart';

/// Soft left panel for events + recent moves.
/// Intentionally lounge-card, not a tactical FPS rail.
class ArenaMoveDock extends ConsumerWidget {
  const ArenaMoveDock({
    super.key,
    required this.moveLogEntries,
    required this.eventTicker,
    this.eventTickerFallback,
    this.compact = false,
    this.scale = 1.0,
  });

  final List<MoveLogEntry> moveLogEntries;
  final TableEventTickerController eventTicker;
  final String? eventTickerFallback;
  final bool compact;
  final double scale;

  static double width({required bool compact, double scale = 1.0}) =>
      (compact ? 92.0 : 108.0) * scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final w = width(compact: compact, scale: scale);
    final inset = 8.0 * scale;

    return SizedBox(
      width: w,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, inset, inset * 0.5, inset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfacePanel.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: theme.accentPrimary.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (compact ? 40.0 : 48.0) * scale,
                child: Padding(
                  padding: EdgeInsets.all(6 * scale),
                  child: TableEventTicker(
                    controller: eventTicker,
                    compact: true,
                    scale: scale * 0.92,
                    fallbackText: eventTickerFallback,
                    fillHeight: true,
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                indent: 10 * scale,
                endIndent: 10 * scale,
                color: theme.textSecondary.withValues(alpha: 0.18),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(6 * scale),
                  child: moveLogEntries.isEmpty
                      ? Center(
                          child: Text(
                            'Moves',
                            style: TextStyle(
                              color: theme.textSecondary.withValues(alpha: 0.4),
                              fontSize: (compact ? 11.0 : 12.0) * scale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : GameMoveLogPanel(
                          entries: moveLogEntries,
                          maxHeight: 400,
                          scale: scale * (compact ? 0.88 : 0.95),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
