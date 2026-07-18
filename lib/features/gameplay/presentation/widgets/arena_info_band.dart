import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/move_log_entry.dart';
import '../../../../core/models/move_log_merge.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import 'game_move_log_overlay.dart';
import 'last_move_panel_widget.dart';
import 'table_event_ticker.dart';

/// Slim full-width band: move log + event flash.
///
/// Layout always reserves [heightFor]. Expanding opens a taller overlay that
/// paints over the board so the table column never reflows.
class ArenaInfoBand extends ConsumerStatefulWidget {
  const ArenaInfoBand({
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

  /// Collapsed reservation used by table layout math — never the expanded size.
  static double heightFor({required bool compact, double scale = 1.0}) =>
      (compact ? 48.0 : 56.0) * scale;

  static double expandedHeightFor({required bool compact, double scale = 1.0}) =>
      (compact ? 240.0 : 280.0) * scale;

  @override
  ConsumerState<ArenaInfoBand> createState() => _ArenaInfoBandState();
}

class _ArenaInfoBandState extends ConsumerState<ArenaInfoBand> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final scale = widget.scale;
    final compact = widget.compact;
    final collapsedH = ArenaInfoBand.heightFor(compact: compact, scale: scale);
    final expandedH =
        ArenaInfoBand.expandedHeightFor(compact: compact, scale: scale);
    final headerH = (compact ? 40.0 : 44.0) * scale;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Fixed layout slot — parent Column sizes against this only.
          SizedBox(
            height: collapsedH,
            width: double.infinity,
            child: ClipRect(
              child: _BandShell(
                theme: theme,
                scale: scale,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _expanded
                          // Avoid laying out preview rows under the overlay
                          // (that was the BOTTOM OVERFLOWED stripe).
                          ? const SizedBox.expand()
                          : _MovesCollapsed(
                              entries: widget.moveLogEntries,
                              theme: theme,
                              compact: compact,
                              scale: scale,
                              bandHeight: collapsedH,
                              onToggle: _toggleExpanded,
                            ),
                    ),
                    Container(
                      width: 1,
                      margin: EdgeInsets.symmetric(
                        horizontal: 6 * scale,
                        vertical: 4 * scale,
                      ),
                      color: theme.textSecondary.withValues(alpha: 0.2),
                    ),
                    Expanded(
                      flex: 2,
                      child: TableEventTicker(
                        controller: widget.eventTicker,
                        compact: true,
                        scale: scale * 0.9,
                        fallbackText: widget.eventTickerFallback,
                        fillHeight: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Positioned(
              top: collapsedH,
              left: -10 * scale,
              right: -10 * scale,
              height: MediaQuery.sizeOf(context).height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _collapse,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: theme.surfacePanel,
                elevation: 12,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(14 * scale),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: expandedH,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: headerH,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Move log',
                                  style: TextStyle(
                                    color: theme.textPrimary,
                                    fontSize: (compact ? 12.0 : 13.0) * scale,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.moveLogEntries.isNotEmpty)
                                Text(
                                  '${widget.moveLogEntries.length}',
                                  style: TextStyle(
                                    color: theme.textSecondary
                                        .withValues(alpha: 0.7),
                                    fontSize: (compact ? 11.0 : 12.0) * scale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              SizedBox(width: 4 * scale),
                              InkWell(
                                onTap: _collapse,
                                borderRadius: BorderRadius.circular(16 * scale),
                                child: Padding(
                                  padding: EdgeInsets.all(6 * scale),
                                  child: Icon(
                                    Icons.expand_less_rounded,
                                    color: theme.accentPrimary,
                                    size: 22 * scale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: theme.textSecondary.withValues(alpha: 0.18),
                      ),
                      Expanded(
                        child: widget.moveLogEntries.isEmpty
                            ? Center(
                                child: Text(
                                  'No moves yet',
                                  style: TextStyle(
                                    color: theme.textSecondary
                                        .withValues(alpha: 0.5),
                                    fontSize: (compact ? 12.0 : 13.0) * scale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  10 * scale,
                                  8 * scale,
                                  10 * scale,
                                  10 * scale,
                                ),
                                physics: const ClampingScrollPhysics(),
                                itemCount: widget.moveLogEntries
                                    .take(kMoveLogMaxEntries)
                                    .length,
                                itemBuilder: (context, index) {
                                  final entry = widget.moveLogEntries[index];
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 4 * scale),
                                    child: LastMovePanelWidget(
                                      entries: [entry],
                                      scale: scale * (compact ? 0.92 : 1.0),
                                      maxVisible: 1,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BandShell extends StatelessWidget {
  const _BandShell({
    required this.theme,
    required this.scale,
    required this.child,
  });

  final AppThemeData theme;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surfacePanel.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * scale,
          vertical: 4 * scale,
        ),
        child: child,
      ),
    );
  }
}

class _MovesCollapsed extends StatelessWidget {
  const _MovesCollapsed({
    required this.entries,
    required this.theme,
    required this.compact,
    required this.scale,
    required this.bandHeight,
    required this.onToggle,
  });

  final List<MoveLogEntry> entries;
  final AppThemeData theme;
  final bool compact;
  final double scale;
  final double bandHeight;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10 * scale),
        child: Row(
          children: [
            Expanded(
              child: entries.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Moves',
                        style: TextStyle(
                          color: theme.textSecondary.withValues(alpha: 0.45),
                          fontSize: (compact ? 11.0 : 12.0) * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : GameMoveLogPanel(
                      entries: entries,
                      maxHeight: bandHeight - 8 * scale,
                      scale: scale * (compact ? 0.85 : 0.92),
                      maxVisible: 1,
                    ),
            ),
            Icon(
              Icons.expand_more_rounded,
              color: theme.accentPrimary.withValues(alpha: 0.85),
              size: 20 * scale,
            ),
          ],
        ),
      ),
    );
  }
}
