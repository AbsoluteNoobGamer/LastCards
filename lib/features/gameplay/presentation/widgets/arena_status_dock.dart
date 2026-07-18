import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/player_model.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../domain/entities/card.dart';
import 'hud_overlay_widget.dart';

/// Soft right panel for suit lock + penalty — fixed so the centre never jumps.
class ArenaStatusDock extends ConsumerWidget {
  const ArenaStatusDock({
    super.key,
    required this.activeSuit,
    required this.queenSuitLock,
    required this.penaltyCount,
    this.penaltyTargetPosition,
    this.onPenaltyIncreased,
    this.compact = false,
    this.scale = 1.0,
  });

  final Suit? activeSuit;
  final Suit? queenSuitLock;
  final int penaltyCount;
  final TablePosition? penaltyTargetPosition;
  final VoidCallback? onPenaltyIncreased;
  final bool compact;
  final double scale;

  static double width({required bool compact, double scale = 1.0}) =>
      (compact ? 68.0 : 80.0) * scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final w = width(compact: compact, scale: scale);
    final inset = 8.0 * scale;
    final slotH = HudOverlayWidget.slotHeight(compact: true, scale: scale);

    return SizedBox(
      width: w,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset * 0.5, inset, inset, inset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfacePanel.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: theme.accentPrimary.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: slotH,
                child: Center(
                  child: penaltyCount > 0
                      ? HudOverlayWidget(
                          penaltyCount: penaltyCount,
                          penaltyTargetPosition: penaltyTargetPosition,
                          onPenaltyIncreased: onPenaltyIncreased,
                          compact: true,
                          scale: scale,
                        )
                      : Icon(
                          Icons.add_circle_outline_rounded,
                          size: 18 * scale,
                          color: theme.textSecondary.withValues(alpha: 0.28),
                        ),
                ),
              ),
              SizedBox(height: 16 * scale),
              SizedBox(
                height: slotH,
                child: Center(
                  child: (activeSuit != null || queenSuitLock != null)
                      ? HudOverlayWidget(
                          activeSuit: activeSuit,
                          queenSuitLock: queenSuitLock,
                          compact: true,
                          scale: scale,
                        )
                      : Icon(
                          Icons.style_outlined,
                          size: 18 * scale,
                          color: theme.textSecondary.withValues(alpha: 0.28),
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
