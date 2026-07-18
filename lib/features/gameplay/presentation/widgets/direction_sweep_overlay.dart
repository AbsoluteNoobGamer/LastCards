import 'package:flutter/material.dart';

import '../../../../core/models/game_state.dart';

/// Soft gold shimmer across the board when play direction reverses (King).
///
/// IgnorePointer — never blocks taps. Classic warm shimmer, not neon HUD.
class DirectionSweepOverlay extends StatefulWidget {
  const DirectionSweepOverlay({
    super.key,
    required this.trigger,
    required this.direction,
  });

  /// Bump when a King reverse should play.
  final int trigger;
  final PlayDirection direction;

  @override
  State<DirectionSweepOverlay> createState() => _DirectionSweepOverlayState();
}

class _DirectionSweepOverlayState extends State<DirectionSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _travel;

  static const _gold = Color(0xFFE8C87A);
  static const _warmWhite = Color(0xFFF5E6C8);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _travel = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(covariant DirectionSweepOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    final clockwise = widget.direction == PlayDirection.clockwise;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _travel.value;
          if (t <= 0.001 || t >= 0.999) return const SizedBox.shrink();

          // Soft fade in then out.
          final opacity = t < 0.22
              ? (t / 0.22)
              : t > 0.72
                  ? (1.0 - (t - 0.72) / 0.28)
                  : 1.0;

          return CustomPaint(
            painter: _DirectionSweepPainter(
              progress: t,
              clockwise: clockwise,
              gold: _gold,
              warmWhite: _warmWhite,
              opacity: opacity.clamp(0.0, 1.0),
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _DirectionSweepPainter extends CustomPainter {
  _DirectionSweepPainter({
    required this.progress,
    required this.clockwise,
    required this.gold,
    required this.warmWhite,
    required this.opacity,
  });

  final double progress;
  final bool clockwise;
  final Color gold;
  final Color warmWhite;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.42;
    // Thinner, longer band than the old neon streak.
    final bandH = size.height * 0.055;
    final travel = size.width + bandH * 2;
    final x = clockwise
        ? -bandH + travel * progress
        : size.width + bandH - travel * progress;

    final rect = Rect.fromCenter(
      center: Offset(x, y),
      width: bandH * 4.4,
      height: bandH,
    );

    final paint = Paint()
      ..shader = LinearGradient(
        begin: clockwise ? Alignment.centerLeft : Alignment.centerRight,
        end: clockwise ? Alignment.centerRight : Alignment.centerLeft,
        colors: [
          Colors.transparent,
          gold.withValues(alpha: 0.18 * opacity),
          warmWhite.withValues(alpha: 0.42 * opacity),
          gold.withValues(alpha: 0.38 * opacity),
          warmWhite.withValues(alpha: 0.22 * opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.18, 0.42, 0.58, 0.82, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(bandH)),
      paint,
    );

    // Soft leading chevron — warm gold, no neon bloom.
    final tipX = clockwise ? rect.right - bandH * 0.35 : rect.left + bandH * 0.35;
    final path = Path();
    if (clockwise) {
      path
        ..moveTo(tipX - 9, y - 7)
        ..lineTo(tipX + 3, y)
        ..lineTo(tipX - 9, y + 7);
    } else {
      path
        ..moveTo(tipX + 9, y - 7)
        ..lineTo(tipX - 3, y)
        ..lineTo(tipX + 9, y + 7);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = warmWhite.withValues(alpha: 0.7 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionSweepPainter old) =>
      old.progress != progress ||
      old.clockwise != clockwise ||
      old.opacity != opacity ||
      old.gold != gold ||
      old.warmWhite != warmWhite;
}
