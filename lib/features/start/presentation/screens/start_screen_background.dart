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
      particlePaint.color = Colors.cyan.withOpacity(0.1 + 0.6 * opacityFunc);

      canvas.drawCircle(Offset(x, y), sizeScale, particlePaint);
    }
  }

  @override
  bool shouldRepaint(ParticleStarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
