import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';

/// Broadcast “stage” frame around the draw/discard/HUD cluster.
///
/// Hard angular corners + dual-accent bracket rails — reads as a live arena
/// camera crop, not a floating casino badge cluster.
class ArenaBoardStage extends ConsumerWidget {
  const ArenaBoardStage({
    super.key,
    required this.child,
    this.compact = false,
    this.scale = 1.0,
  });

  final Widget child;
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final pad = (compact ? 10.0 : 14.0) * scale;
    final radius = 6.0 * scale;

    return Container(
      padding: EdgeInsets.fromLTRB(pad, pad * 0.7, pad, pad * 0.85),
      decoration: BoxDecoration(
        color: theme.surfaceDark.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.55),
          width: 1.4 * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.18),
            blurRadius: 22 * scale,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: theme.secondaryAccent.withValues(alpha: 0.12),
            blurRadius: 36 * scale,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 16 * scale,
            offset: Offset(0, 6 * scale),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.surfacePanel.withValues(alpha: 0.55),
            theme.surfaceDark.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Inner scan-line wash
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanlinePainter(
                  color: theme.accentPrimary.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
          // Corner brackets
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  primary: theme.accentPrimary,
                  secondary: theme.secondaryAccent,
                  stroke: 2.2 * scale,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => old.color != color;
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({
    required this.primary,
    required this.secondary,
    required this.stroke,
  });

  final Color primary;
  final Color secondary;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final len = size.shortestSide * 0.12;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..color = primary.withValues(alpha: 0.9);

    void bracket(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(len * dx, 0), p);
      canvas.drawLine(o, o + Offset(0, len * dy), p);
    }

    bracket(Offset(2, 2), 1, 1);
    p.color = secondary.withValues(alpha: 0.85);
    bracket(Offset(size.width - 2, 2), -1, 1);
    p.color = primary.withValues(alpha: 0.9);
    bracket(Offset(2, size.height - 2), 1, -1);
    p.color = secondary.withValues(alpha: 0.85);
    bracket(Offset(size.width - 2, size.height - 2), -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.stroke != stroke;
}
