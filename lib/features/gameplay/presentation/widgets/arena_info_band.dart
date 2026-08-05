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
/// Layout always reserves [heightFor]. Expanding opens a taller panel via a
/// root [Overlay] entry (not a local overflowing [Stack]) so it — and its
/// tap-outside-to-dismiss scrim — are hit-testable across the whole screen
/// regardless of how small this band's own ancestor Stack is bounded to.
class ArenaInfoBand extends ConsumerStatefulWidget {
  const ArenaInfoBand({
    super.key,
    required this.moveLogEntries,
    required this.eventTicker,
    required this.expandedNotifier,
    this.eventTickerFallback,
    this.compact = false,
    this.scale = 1.0,
  });

  final List<MoveLogEntry> moveLogEntries;
  final TableEventTickerController eventTicker;

  /// Owned by the table screen (see [TableScreen._moveLogExpanded]) purely
  /// so other code can query/force-collapse it; the overlay lifecycle below
  /// is what actually makes tap-outside-to-dismiss work.
  final ValueNotifier<bool> expandedNotifier;

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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.expandedNotifier.addListener(_onExpandedChanged);
  }

  @override
  void didUpdateWidget(covariant ArenaInfoBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandedNotifier != widget.expandedNotifier) {
      oldWidget.expandedNotifier.removeListener(_onExpandedChanged);
      widget.expandedNotifier.addListener(_onExpandedChanged);
    }
    // Keep an already-open overlay's content (entries/theme/scale) current.
    // Deferred to post-frame: calling markNeedsBuild() synchronously here
    // runs during this element's own build phase, which throws ("widgets
    // must be built by their parents" / "called during build").
    if (_overlayEntry != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _overlayEntry?.markNeedsBuild());
    }
  }

  @override
  void dispose() {
    widget.expandedNotifier.removeListener(_onExpandedChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onExpandedChanged() {
    if (widget.expandedNotifier.value) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _collapse() => widget.expandedNotifier.value = false;

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final box = context.findRenderObject() as RenderBox?;
    final bandWidth = box?.size.width ?? MediaQuery.sizeOf(context).width;
    final collapsedH =
        ArenaInfoBand.heightFor(compact: widget.compact, scale: widget.scale);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _collapse,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, collapsedH),
            child: SizedBox(
              width: bandWidth,
              child: _ExpandedMoveLogPanel(
                moveLogEntries: widget.moveLogEntries,
                compact: widget.compact,
                scale: widget.scale,
                onCollapse: _collapse,
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final collapsedH =
        ArenaInfoBand.heightFor(compact: widget.compact, scale: widget.scale);

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 10 * widget.scale, vertical: 4 * widget.scale),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          height: collapsedH,
          width: double.infinity,
          child: ClipRect(
            child: _BandShell(
              theme: theme,
              scale: widget.scale,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    // Keyed on the entry count so a new top move forces a
                    // clean remount (fresh TweenAnimationBuilder) instead of
                    // updating in place — this band stays mounted
                    // continuously now (see class doc), so without this an
                    // in-flight entrance animation for the previous top
                    // entry could still be settling when the next one
                    // arrives, painting both at once.
                    child: _MovesCollapsed(
                      key: ValueKey(widget.moveLogEntries.length),
                      entries: widget.moveLogEntries,
                      theme: theme,
                      compact: widget.compact,
                      scale: widget.scale,
                      bandHeight: collapsedH,
                      onToggle: () => widget.expandedNotifier.value = true,
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: EdgeInsets.symmetric(
                      horizontal: 6 * widget.scale,
                      vertical: 4 * widget.scale,
                    ),
                    color: theme.textSecondary.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    flex: 2,
                    child: TableEventTicker(
                      controller: widget.eventTicker,
                      compact: true,
                      scale: widget.scale * 0.9,
                      fallbackText: widget.eventTickerFallback,
                      fillHeight: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanded move log panel, rendered via a root [Overlay] entry so its
/// scrim and content are hit-testable across the whole screen. See
/// [ArenaInfoBand] for why a local overflowing [Stack] doesn't work.
class _ExpandedMoveLogPanel extends ConsumerWidget {
  const _ExpandedMoveLogPanel({
    required this.moveLogEntries,
    required this.compact,
    required this.scale,
    required this.onCollapse,
  });

  final List<MoveLogEntry> moveLogEntries;
  final bool compact;
  final double scale;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final expandedH =
        ArenaInfoBand.expandedHeightFor(compact: compact, scale: scale);
    final headerH = (compact ? 40.0 : 44.0) * scale;

    return Material(
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
                    if (moveLogEntries.isNotEmpty)
                      Text(
                        '${moveLogEntries.length}',
                        style: TextStyle(
                          color: theme.textSecondary.withValues(alpha: 0.7),
                          fontSize: (compact ? 11.0 : 12.0) * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    SizedBox(width: 4 * scale),
                    InkWell(
                      onTap: onCollapse,
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
              child: moveLogEntries.isEmpty
                  ? Center(
                      child: Text(
                        'No moves yet',
                        style: TextStyle(
                          color: theme.textSecondary.withValues(alpha: 0.5),
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
                      itemCount:
                          moveLogEntries.take(kMoveLogMaxEntries).length,
                      itemBuilder: (context, index) {
                        final entry = moveLogEntries[index];
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
    super.key,
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
                  // interactive: true lets the collapsed strip scroll
                  // through recent history in place (same footprint as
                  // before — just draggable instead of a single frozen
                  // line) without needing to open the full expanded panel.
                  : GameMoveLogPanel(
                      entries: entries,
                      maxHeight: bandHeight - 8 * scale,
                      scale: scale * (compact ? 0.85 : 0.92),
                      maxVisible: kMoveLogMaxEntries,
                      interactive: true,
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
