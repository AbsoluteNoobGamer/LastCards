import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Priority for ticker messages — higher wins when replacing the current line.
enum TableEventPriority {
  move(0),
  reshuffle(1),
  reverse(2),
  stack(3),
  lastCards(4),
  bluff(5),
  penalty(6);

  const TableEventPriority(this.rank);
  final int rank;
}

class TableEventMessage {
  const TableEventMessage({
    required this.id,
    required this.text,
    required this.priority,
    this.accent,
    this.dwell = const Duration(milliseconds: 2200),
  });

  final int id;
  final String text;
  final TableEventPriority priority;
  final Color? accent;
  final Duration dwell;
}

/// Owns a short queue of broadcast ticker lines for the reserved event lane.
class TableEventTickerController extends ChangeNotifier {
  TableEventTickerController();

  final Queue<TableEventMessage> _queue = Queue<TableEventMessage>();
  TableEventMessage? _current;
  Timer? _dismissTimer;
  int _seq = 0;

  TableEventMessage? get current => _current;

  void push(
    String text, {
    TableEventPriority priority = TableEventPriority.move,
    Color? accent,
    Duration? dwell,
  }) {
    final msg = TableEventMessage(
      id: ++_seq,
      text: text,
      priority: priority,
      accent: accent,
      dwell: dwell ?? _defaultDwell(priority),
    );

    if (_current == null) {
      _show(msg);
      return;
    }

    // Higher or equal priority replaces immediately; else enqueue (cap 3).
    if (msg.priority.rank >= _current!.priority.rank) {
      _queue.clear();
      _show(msg);
      return;
    }

    _queue.addLast(msg);
    while (_queue.length > 3) {
      _queue.removeFirst();
    }
  }

  Duration _defaultDwell(TableEventPriority p) {
    switch (p) {
      case TableEventPriority.bluff:
      case TableEventPriority.penalty:
        return const Duration(milliseconds: 2500);
      case TableEventPriority.lastCards:
        return const Duration(milliseconds: 2200);
      case TableEventPriority.stack:
      case TableEventPriority.reverse:
        return const Duration(milliseconds: 1800);
      case TableEventPriority.reshuffle:
        return const Duration(milliseconds: 1600);
      case TableEventPriority.move:
        return const Duration(milliseconds: 1400);
    }
  }

  void _show(TableEventMessage msg) {
    _dismissTimer?.cancel();
    _current = msg;
    notifyListeners();
    _dismissTimer = Timer(msg.dwell, _advance);
  }

  void _advance() {
    if (_queue.isNotEmpty) {
      _show(_queue.removeFirst());
      return;
    }
    _current = null;
    notifyListeners();
  }

  void clear() {
    _dismissTimer?.cancel();
    _queue.clear();
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }
}

/// Reserved event lane between opponent rail and board piles.
class TableEventTicker extends ConsumerWidget {
  const TableEventTicker({
    super.key,
    required this.controller,
    this.compact = false,
    this.scale = 1.0,
    this.fallbackText,
    this.fillHeight = false,
  });

  final TableEventTickerController controller;
  final bool compact;
  final double scale;

  /// Shown when the queue is idle (e.g. Last Cards strip summary).
  final String? fallbackText;

  /// When true, expands to parent height (used inside [ArenaInfoBand]).
  final bool fillHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final height = (compact ? 28.0 : 34.0) * scale;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final msg = controller.current;
        final text = msg?.text ?? fallbackText;
        if (text == null || text.isEmpty) {
          return SizedBox(
            height: fillHeight ? null : height,
            width: fillHeight ? double.infinity : null,
            child: fillHeight
                ? Align(
                    alignment: Alignment.center,
                    child: Text(
                      '…',
                      style: TextStyle(
                        color: theme.textSecondary.withValues(alpha: 0.35),
                        fontSize: (compact ? 14.0 : 16.0) * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : null,
          );
        }

        final accent = msg?.accent ?? theme.accentPrimary;
        final fontSize = (compact ? 11.0 : 12.5) * scale;

        final chip = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Container(
            key: ValueKey(msg?.id ?? 'fallback-$text'),
            width: fillHeight ? double.infinity : null,
            margin: fillHeight
                ? EdgeInsets.zero
                : EdgeInsets.symmetric(horizontal: 16 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 10 * scale,
              vertical: 5 * scale,
            ),
            constraints: fillHeight
                ? const BoxConstraints()
                : BoxConstraints(maxWidth: 360 * scale),
            decoration: BoxDecoration(
              color: theme.surfacePanel.withValues(alpha: 0.94),
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusButton * 0.4),
              border: Border.all(
                color: accent.withValues(alpha: 0.9),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: fillHeight ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        );

        if (fillHeight) {
          return Align(alignment: Alignment.center, child: chip);
        }
        return SizedBox(height: height, child: Center(child: chip));
      },
    );
  }
}
