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

// -----------------------------------------------------------------------------
// Logo Animation
// -----------------------------------------------------------------------------

class AnimatedLogo extends StatefulWidget {
  final AnimationController controller;
  const AnimatedLogo({super.key, required this.controller});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
          parent: widget.controller,
          curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic)),
    );
    final opacityAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: widget.controller,
          curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _pulseController]),
      builder: (context, child) {
        final double pulse = _pulseController.value;

        return SlideTransition(
          position: slideAnim,
          child: Opacity(
            opacity: opacityAnim.value,
            child: ShaderMask(
              shaderCallback: (bounds) {
                return ui.Gradient.linear(
                  const Offset(0, 0),
                  Offset(0, bounds.height),
                  [
                    Colors.white,
                    Colors.white.withOpacity(0.6),
                    Colors.white,
                  ],
                  [
                    (pulse * 2 - 0.2).clamp(0.0, 1.0),
                    (pulse * 2).clamp(0.0, 1.0),
                    (pulse * 2 + 0.2).clamp(0.0, 1.0)
                  ],
                );
              },
              child: Text(
                "STACK FLOW",
                style: GoogleFonts.outfit(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 60 * 0.05,
                  shadows: [
                    Shadow(
                      color: const Color(0xFFCCFF00)
                          .withOpacity(0.4 + (pulse * 0.6)),
                      blurRadius: 15 + (pulse * 20),
                      offset: const Offset(0, 0),
                    ),
                    Shadow(
                      color: const Color(0xFFCCFF00)
                          .withOpacity(0.2 + (pulse * 0.4)),
                      blurRadius: 30 + (pulse * 30),
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
