import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';

/// Premium card back — deep green/burgundy base with a gold geometric
/// border pattern and a centred emblem, drawn entirely in [CustomPaint].
class CardBackWidget extends StatelessWidget {
  const CardBackWidget({
    super.key,
    this.width = AppDimensions.cardWidthMedium,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(width);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.feltMid, AppColors.feltDeep],
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: AppColors.goldDark,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard - 1),
        child: CustomPaint(
          painter: _CardBackPainter(),
        ),
      ),
    );
  }
}

// ── Card Back Painter ─────────────────────────────────────────────────────────

class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final borderPaint = Paint()
      ..color = AppColors.goldDark.withValues(alpha: 0.7)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final accentPaint = Paint()
      ..color = AppColors.goldPrimary.withValues(alpha: 0.5)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Inner border inset
    const inset = 5.0;
    final innerRect = Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2);
    final rr = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(AppDimensions.radiusCard - 2),
    );
    canvas.drawRRect(rr, borderPaint);

    // Diamond lattice pattern
    _drawLattice(canvas, size, accentPaint);

    // Centred emblem (crown)
    _drawCrownEmblem(
        canvas,
        size,
        Paint()
          ..color = AppColors.goldPrimary.withValues(alpha: 0.8)
          ..style = PaintingStyle.fill);
  }

  void _drawLattice(Canvas canvas, Size size, Paint paint) {
    const spacing = 10.0;
    final w = size.width;
    final h = size.height;

    for (double x = 0; x < w; x += spacing) {
      for (double y = 0; y < h; y += spacing) {
        final half = spacing / 2;
        // Diamond at each grid point
        final path = Path()
          ..moveTo(x, y - half * 0.55)
          ..lineTo(x + half * 0.55, y)
          ..lineTo(x, y + half * 0.55)
          ..lineTo(x - half * 0.55, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawCrownEmblem(Canvas canvas, Size size, Paint paint) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.22;

    // Simple stylised crown: base rectangle + three points
    final base = Rect.fromCenter(
      center: Offset(cx, cy + r * 0.3),
      width: r * 1.8,
      height: r * 0.55,
    );

    // Crown base
    canvas.drawRect(base, paint);

    // Erase (clip) the lattice by painting a slightly darker fill
    final bgPaint = Paint()
      ..color = AppColors.feltDeep.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawRect(base, bgPaint);
    canvas.drawRect(base, paint);

    // Three crown peaks
    final peakPaint = Paint()
      ..color = AppColors.goldPrimary.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final points = [
      // left peak
      Offset(cx - r * 0.72, cy + r * 0.05),
      // centre peak (tallest)
      Offset(cx, cy - r * 0.45),
      // right peak
      Offset(cx + r * 0.72, cy + r * 0.05),
    ];

    final baseTop = cy + r * 0.05;

    for (final peak in points) {
      final tri = Path()
        ..moveTo(peak.dx - r * 0.20, baseTop)
        ..lineTo(peak.dx, peak.dy)
        ..lineTo(peak.dx + r * 0.20, baseTop)
        ..close();
      canvas.drawPath(tri, peakPaint);
    }

    // Gem dots at each peak
    final dotPaint = Paint()
      ..color = AppColors.goldLight
      ..style = PaintingStyle.fill;
    canvas.drawCircle(points[1], r * 0.07, dotPaint); // centre
    canvas.drawCircle(points[0], r * 0.055, dotPaint);
    canvas.drawCircle(points[2], r * 0.055, dotPaint);
  }

  @override
  bool shouldRepaint(_CardBackPainter old) => false;
}
