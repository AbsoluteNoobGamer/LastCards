part of 'start_screen.dart';

// -----------------------------------------------------------------------------
// Animated Background
// -----------------------------------------------------------------------------

class ParticleStarfieldPainter extends CustomPainter {
  final double progress;
  ParticleStarfieldPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double breath = (sin(progress * pi * 2) + 1) / 2;

    final Color darkGreen = const Color(0xFF0F2027);
    final Color darkCyan = const Color(0xFF133b3a);

    final Paint bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        size.longestSide,
        [
          Color.lerp(darkGreen, darkCyan, breath)!,
          Color.lerp(darkCyan, darkGreen, breath)!,
        ],
        [0.0, 1.0],
      );
    canvas.drawRect(rect, bgPaint);

    final Random rand = Random(42);
    final Paint particlePaint = Paint()..color = Colors.white;

    for (int i = 0; i < 150; i++) {
      final double startX = rand.nextDouble() * size.width;
      final double startY = rand.nextDouble() * size.height;
      final double speed = 0.1 + rand.nextDouble() * 0.5;
      final double sizeScale = 0.5 + rand.nextDouble() * 2.0;

      final double rawY = startY - (progress * size.height * speed);
      final double y = (rawY % size.height + size.height) % size.height;
      final double x = startX + sin(progress * pi * 2 * speed + i) * 10;

      final double opacityFunc = (sin(progress * pi * 4 * speed + i) + 1) / 2;
      particlePaint.color = Colors.cyan.withValues(alpha: 0.1 + 0.6 * opacityFunc);

      canvas.drawCircle(Offset(x, y), sizeScale, particlePaint);
    }
  }

  @override
  bool shouldRepaint(ParticleStarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// -----------------------------------------------------------------------------
// God rays (additive, slow rotation)
// -----------------------------------------------------------------------------

class GodRaysPainter extends CustomPainter {
  GodRaysPainter({
    required this.rotation,
    required this.accent,
  });

  final double rotation;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;
    canvas.save();
    canvas.translate(w / 2, h * 0.06);
    canvas.rotate(rotation);
    final Paint paint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 6; i++) {
      canvas.save();
      canvas.rotate((i / 6) * pi * 2);
      final Rect rect = Rect.fromCenter(
        center: Offset(0, h * 0.42),
        width: w * 0.55,
        height: h * 0.95,
      );
      paint.shader = ui.Gradient.linear(
        const Offset(0, -40),
        Offset(0, h * 0.9),
        [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.04),
          accent.withValues(alpha: 0.0),
        ],
        const [0.0, 0.45, 1.0],
      );
      canvas.drawRect(rect, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GodRaysPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.accent != accent;
}

// -----------------------------------------------------------------------------
// Tap shockwave ring
// -----------------------------------------------------------------------------

class ShockwavePainter extends CustomPainter {
  ShockwavePainter({
    required this.center,
    required this.progress,
    required this.accent,
  });

  final Offset center;
  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final double maxR = size.shortestSide * 0.95;
    final double r = progress * maxR;
    final double fade = (1.0 - progress) * (1.0 - progress);
    final Color c = accent.withValues(alpha: 0.55 * fade);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + (1.0 - progress) * 4
      ..color = c
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, r, ring);
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 * (1.0 - progress)
      ..color = accent.withValues(alpha: 0.12 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(center, r * 0.98, glow);
  }

  @override
  bool shouldRepaint(ShockwavePainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent;
}
