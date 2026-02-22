part of 'table_screen.dart';

// ── Background ────────────────────────────────────────────────────────────────

class _FeltTableBackground extends StatelessWidget {
  const _FeltTableBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _FeltPainter()),
    );
  }
}

class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base felt fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.feltDeep,
    );

    // Subtle micro-texture via semi-transparent noise dots
    final dotPaint = Paint()
      ..color = AppColors.feltMid.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Simple dot grid as texture approximation
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if (((x ~/ 4) + (y ~/ 4)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
        }
      }
    }

    // Vignette — radial darkening toward edges
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide * 0.75;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
          stops: const [0.45, 1.0],
        ).createShader(
          Rect.fromCircle(center: centre, radius: radius),
        ),
    );

    // Faint inner highlight (overhead light)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.5,
          colors: [
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.4),
        ),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter _) => false;
}

// ── Placeholder widgets ───────────────────────────────────────────────────────

class _EmptyOpponentZone extends StatelessWidget {
  const _EmptyOpponentZone();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 80);
  }
}
