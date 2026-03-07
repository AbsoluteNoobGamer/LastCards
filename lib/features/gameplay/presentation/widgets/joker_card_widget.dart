import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';

/// Dramatic Joker card — dark inverted background, themed accent text,
/// geometric jester motif, iridescent shimmer animation.
///
/// Visual colours are driven by the active [AppThemeData] via [themeProvider].
/// When a theme defines [AppThemeData.jokerAccentColor] /
/// [AppThemeData.jokerBackgroundColors] / [AppThemeData.jokerBorderColor],
/// those values are used; otherwise the widget falls back to its original
/// dark-navy / gold appearance so themes without overrides remain unchanged.
class JokerCardWidget extends ConsumerStatefulWidget {
  const JokerCardWidget({
    super.key,
    this.width = AppDimensions.cardWidthMedium,
    this.onTap,
  });

  final double width;
  final VoidCallback? onTap;

  @override
  ConsumerState<JokerCardWidget> createState() => _JokerCardWidgetState();
}

class _JokerCardWidgetState extends ConsumerState<JokerCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  // Default values used when the active theme has no Joker override.
  static const _defaultBg1 = Color(0xFF1A1A2E);
  static const _defaultBg2 = Color(0xFF0D0D1A);

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
    final theme = ref.watch(themeProvider).theme;
    final height = AppDimensions.cardHeight(widget.width);

    final bgColors = theme.jokerBackgroundColors ?? [_defaultBg1, _defaultBg2];
    final borderColor = theme.jokerBorderColor ?? AppColors.goldDark;
    final accentColor = theme.jokerAccentColor ?? AppColors.goldPrimary;
    final accentLight = theme.jokerAccentColor != null
        ? Color.lerp(theme.jokerAccentColor!, Colors.white, 0.25)!
        : AppColors.goldLight;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bgColors,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: borderColor, width: 1),
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
                      colors: [
                        Colors.transparent,
                        accentColor.withValues(alpha: 0.33),
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
                painter: _JesterMotifPainter(
                  strokeColor: borderColor,
                  fillColor: accentColor.withValues(alpha: 0.75),
                ),
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
                    color: accentLight,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.9),
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
  const _JesterMotifPainter({
    required this.strokeColor,
    required this.fillColor,
  });

  final Color strokeColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fill = Paint()
      ..color = fillColor
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
  bool shouldRepaint(_JesterMotifPainter old) =>
      old.strokeColor != strokeColor || old.fillColor != fillColor;
}
