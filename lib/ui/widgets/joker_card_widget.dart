import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';

/// Dramatic Joker card — dark inverted background, gold foil "JOKER" text,
/// geometric jester motif, iridescent shimmer animation.
class JokerCardWidget extends StatefulWidget {
  const JokerCardWidget({
    super.key,
    this.width = AppDimensions.cardWidthMedium,
    this.onTap,
  });

  final double width;
  final VoidCallback? onTap;

  @override
  State<JokerCardWidget> createState() => _JokerCardWidgetState();
}

class _JokerCardWidgetState extends State<JokerCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(widget.width);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF0D0D1A)],
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          boxShadow: [
            BoxShadow(
              color: AppColors.goldPrimary.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: AppColors.goldDark, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Iridescent shimmer
              AnimatedBuilder(
                animation: _shimmerController,
                builder: (_, __) {
                  final v = _shimmerController.value;
                  return ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: const [
                        Colors.transparent,
                        Color(0x55E8CC7A),
                        Colors.transparent,
                      ],
                      stops: [
                        (v - 0.35).clamp(0.0, 1.0),
                        v.clamp(0.0, 1.0),
                        (v + 0.35).clamp(0.0, 1.0),
                      ],
                    ).createShader(bounds),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  );
                },
              ),

              // Geometric jester motif
              CustomPaint(
                size: Size(widget.width * 0.58, widget.width * 0.58),
                painter: _JesterMotifPainter(),
              ),

              // "JOKER" label
              Positioned(
                bottom: widget.width * 0.10,
                child: Text(
                  'JOKER',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: widget.width * 0.16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.goldLight,
                    shadows: [
                      Shadow(
                        color: AppColors.goldPrimary.withValues(alpha: 0.9),
                        blurRadius: 10,
                      ),
                    ],
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

// ── Geometric Jester Motif ─────────────────────────────────────────────────────

class _JesterMotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AppColors.goldDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fill = Paint()
      ..color = AppColors.goldPrimary.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.4;

    // Outer diamond frame
    final diamond = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.65, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r * 0.65, cy)
      ..close();
    canvas.drawPath(diamond, stroke);

    // Four triangular points radiating inward
    for (int i = 0; i < 4; i++) {
      final base = (i * math.pi / 2) - math.pi / 4;
      final tip = Offset(
          cx + r * 0.28 * math.cos(base), cy + r * 0.28 * math.sin(base));
      final left = Offset(
        cx + r * 0.62 * math.cos(base + math.pi / 6),
        cy + r * 0.62 * math.sin(base + math.pi / 6),
      );
      final right = Offset(
        cx + r * 0.62 * math.cos(base - math.pi / 6),
        cy + r * 0.62 * math.sin(base - math.pi / 6),
      );

      final tri = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(tri, fill);
      canvas.drawPath(tri, stroke);
    }

    // Centre circle
    canvas.drawCircle(Offset(cx, cy), r * 0.16, fill);
    canvas.drawCircle(Offset(cx, cy), r * 0.16, stroke);
  }

  @override
  bool shouldRepaint(_JesterMotifPainter old) => false;
}
