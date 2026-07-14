import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Fixed-layout mini scene every tutorial demo animates within: three seat
/// labels plus a discard-pile and draw-pile anchor. The layout never
/// changes, so demos position against these constant offsets directly
/// instead of the `GlobalKey`/`RenderBox` lookups the live table needs.
class TutorialDemoStage extends StatelessWidget {
  const TutorialDemoStage({super.key, required this.theme, this.foreground});

  final AppThemeData theme;

  /// Animated content layered on top of the static stage.
  final Widget? foreground;

  static const double width = 320;
  static const double height = 210;

  static const Offset youSeat = Offset(160, 196);
  static const Offset p2Seat = Offset(38, 18);
  static const Offset p3Seat = Offset(282, 18);
  static const Offset discardAnchor = Offset(140, 104);
  static const Offset drawAnchor = Offset(192, 104);
  static const Offset handAnchor = Offset(160, 176);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surfacePanel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.28)),
              ),
            ),
          ),
          _SeatLabel(offset: youSeat, label: 'You', theme: theme, emphasize: true),
          _SeatLabel(offset: p2Seat, label: 'P2', theme: theme),
          _SeatLabel(offset: p3Seat, label: 'P3', theme: theme),
          if (foreground != null) foreground!,
        ],
      ),
    );
  }
}

class _SeatLabel extends StatelessWidget {
  const _SeatLabel({
    required this.offset,
    required this.label,
    required this.theme,
    this.emphasize = false,
  });

  final Offset offset;
  final String label;
  final AppThemeData theme;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx - 20,
      top: offset.dy - 10,
      child: Container(
        width: 40,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: emphasize
              ? theme.accentPrimary.withValues(alpha: 0.85)
              : theme.surfaceDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: emphasize ? theme.backgroundDeep : theme.textSecondary,
          ),
        ),
      ),
    );
  }
}
