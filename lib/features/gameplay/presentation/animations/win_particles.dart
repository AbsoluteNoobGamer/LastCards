import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Gold / accent / white particles, radial flash, and vertical shimmer behind the win dialog (~5s).
class WinCelebrationOverlay extends StatefulWidget {
  const WinCelebrationOverlay({
    super.key,
    required this.theme,
    required this.onFinished,
  });

  final AppThemeData theme;
  final VoidCallback onFinished;

  @override
  State<WinCelebrationOverlay> createState() => _WinCelebrationOverlayState();
}

class _WinCelebrationOverlayState extends State<WinCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;
  final _rand = math.Random(42);

  @override
  void initState() {
    super.initState();
    _particles = List.generate(90, (i) {
      final shapeRoll = _rand.nextInt(3);
      return _Particle(
        x: _rand.nextDouble(),
        yStart: -0.2 - _rand.nextDouble() * 0.5,
        sway: (_rand.nextDouble() - 0.5) * 0.04,
        size: 1.2 + _rand.nextDouble() * 2.8,
        phase: _rand.nextDouble() * math.pi * 2,
        shape: _ParticleShape.values[shapeRoll],
        colorIndex: _rand.nextInt(3),
      );
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        widget.onFinished();
        return;
      }
      _ctrl.forward().whenComplete(() {
        if (mounted) widget.onFinished();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _WinCelebrationPainter(
              progress: _ctrl.value,
              theme: widget.theme,
              particles: _particles,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

enum _ParticleShape { circle, square, diamond }

class _WinCelebrationPainter extends CustomPainter {
  _WinCelebrationPainter({
    required this.progress,
    required this.theme,
    required this.particles,
  });

  final double progress;
  final AppThemeData theme;
  final List<_Particle> particles;

  static const double _flashPhase = 300 / 5000;

  Color _particleColor(int colorIndex) {
    switch (colorIndex) {
      case 0:
        return Color.lerp(theme.accentPrimary, theme.accentLight, 0.35)!;
      case 1:
        return theme.accentPrimary;
      default:
        return Colors.white;
    }
  }

  void _paintRadialFlash(Canvas canvas, Size size) {
    if (progress > _flashPhase) return;
    final t = progress / _flashPhase;
    final opacity = (1.0 - t) * 0.5;
    final center = Offset(size.width / 2, size.height / 2);
    final r = t * size.longestSide * 0.55;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, p);
  }

  void _drawParticleShape(
    Canvas canvas,
    Offset center,
    double r,
    _ParticleShape shape,
    Paint paint,
  ) {
    switch (shape) {
      case _ParticleShape.circle:
        canvas.drawCircle(center, r * 0.55, paint);
      case _ParticleShape.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: r, height: r),
            const Radius.circular(1),
          ),
          paint,
        );
      case _ParticleShape.diamond:
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: r * 1.15,
              height: r * 1.15,
            ),
            const Radius.circular(1),
          ),
          paint,
        );
        canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    _paintRadialFlash(canvas, size);

    final shimmerPaint = Paint()..style = PaintingStyle.fill;
    for (var b = 0; b < 5; b++) {
      final baseY = (b / 5.0 + progress * 0.35) % 1.0;
      final y = baseY * size.height;
      final h = size.height * 0.08;
      final t = (math.sin(progress * math.pi * 2 + b) + 1) / 2;
      shimmerPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          theme.accentPrimary.withValues(alpha: 0.0),
          theme.accentLight.withValues(alpha: 0.06 * t),
          theme.accentPrimary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y, size.width, h));
      canvas.drawRect(Rect.fromLTWH(0, y - h / 2, size.width, h), shimmerPaint);
    }

    for (final p in particles) {
      final t = (progress + p.yStart + 0.15) % 1.4 / 1.4;
      final py = t * (size.height * 1.15);
      final px = p.x * size.width +
          math.sin(progress * math.pi * 2 + p.phase) * p.sway * size.width;
      final fadeIn = (t * 4).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - t) * 3).clamp(0.0, 1.0);
      final a = (fadeIn * fadeOut).clamp(0.0, 1.0);
      if (a <= 0.01) continue;

      final base = _particleColor(p.colorIndex);
      final paint = Paint()
        ..color = base.withValues(alpha: 0.12 + 0.48 * a)
        ..style = PaintingStyle.fill;

      final r = p.size * (0.85 + 0.15 * math.sin(p.phase + progress * 6));
      _drawParticleShape(canvas, Offset(px, py), r, p.shape, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WinCelebrationPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.theme != theme;
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.yStart,
    required this.sway,
    required this.size,
    required this.phase,
    required this.shape,
    required this.colorIndex,
  });

  final double x;
  final double yStart;
  final double sway;
  final double size;
  final double phase;
  final _ParticleShape shape;
  final int colorIndex;
}
