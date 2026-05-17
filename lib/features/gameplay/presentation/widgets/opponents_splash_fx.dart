import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Animated backdrop: rotating light beams, pulsing core, floating embers.
class OpponentsSplashBackdrop extends StatefulWidget {
  const OpponentsSplashBackdrop({
    required this.theme,
    required this.intensity,
    super.key,
  });

  final AppThemeData theme;
  final double intensity;

  @override
  State<OpponentsSplashBackdrop> createState() => _OpponentsSplashBackdropState();
}

class _OpponentsSplashBackdropState extends State<OpponentsSplashBackdrop>
    with TickerProviderStateMixin {
  late AnimationController _rotate;
  late AnimationController _pulse;
  late final List<_Ember> _embers;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _embers = List.generate(28, (i) {
      return _Ember(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.5 + rng.nextDouble() * 3.5,
        speed: 0.15 + rng.nextDouble() * 0.35,
        phase: rng.nextDouble() * math.pi * 2,
        drift: (rng.nextDouble() - 0.5) * 0.08,
      );
    });
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotate.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return ColoredBox(color: widget.theme.backgroundDeep);
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_rotate, _pulse]),
      builder: (context, _) {
        return CustomPaint(
          painter: _BackdropPainter(
            theme: widget.theme,
            rotation: _rotate.value,
            pulse: _pulse.value,
            embers: _embers,
            time: _rotate.value * 18,
            intensity: widget.intensity,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Ember {
  const _Ember({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.drift,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;
  final double drift;
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.theme,
    required this.rotation,
    required this.pulse,
    required this.embers,
    required this.time,
    required this.intensity,
  });

  final AppThemeData theme;
  final double rotation;
  final double pulse;
  final List<_Ember> embers;
  final double time;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final base = theme.backgroundDeep;

    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final coreRadius = size.shortestSide * (0.35 + pulse * 0.08);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          theme.accentPrimary.withValues(alpha: 0.22 * intensity),
          theme.accentLight.withValues(alpha: 0.06 * intensity),
          base,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawRect(Offset.zero & size, corePaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * math.pi * 2);
    const beamCount = 5;
    for (var i = 0; i < beamCount; i++) {
      final angle = (i / beamCount) * math.pi * 2;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.55, -size.width * 0.04)
        ..lineTo(size.width * 0.55, size.width * 0.04)
        ..close();
      canvas.save();
      canvas.rotate(angle);
      final beamPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            theme.accentLight.withValues(alpha: 0.0),
            theme.accentPrimary.withValues(alpha: 0.07 * intensity),
            theme.accentLight.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, -40, size.width * 0.55, 80));
      canvas.drawPath(path, beamPaint);
      canvas.restore();
    }
    canvas.restore();

    for (var i = 0; i < embers.length; i++) {
      final e = embers[i];
      final t = (time * e.speed + e.phase) % 1.0;
      final y = (e.y - t) % 1.2;
      final x = e.x + math.sin(time * 2 + e.phase) * e.drift;
      final pos = Offset(x * size.width, y * size.height);
      final alpha = (math.sin(t * math.pi) * 0.55 + 0.15) * intensity;
      canvas.drawCircle(
        pos,
        e.size,
        Paint()
          ..color = (i.isEven ? theme.accentLight : theme.accentPrimary)
              .withValues(alpha: alpha),
      );
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [
          Colors.transparent,
          base.withValues(alpha: 0.85),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.rotation != rotation ||
      old.pulse != pulse ||
      old.intensity != intensity;
}

/// Full-screen flash on countdown ticks (and stronger on GO).
class OpponentsSplashFlashOverlay extends StatelessWidget {
  const OpponentsSplashFlashOverlay({
    required this.progress,
    required this.color,
    super.key,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.001) return const SizedBox.shrink();
    final fade = (1 - progress) * (1 - progress);
    return IgnorePointer(
      child: ColoredBox(
        color: color.withValues(alpha: fade * 0.45),
      ),
    );
  }
}

/// Expanding ring burst behind the countdown number.
class OpponentsSplashCountdownBurst extends StatelessWidget {
  const OpponentsSplashCountdownBurst({
    required this.progress,
    required this.theme,
    super.key,
  });

  final double progress;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.001) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _CountdownRingPainter(
          progress: progress,
          accent: theme.accentPrimary,
          accentLight: theme.accentLight,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.accent,
    required this.accentLight,
  });

  final double progress;
  final Color accent;
  final Color accentLight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.88);
    final maxR = size.shortestSide * 0.42;
    final r = progress * maxR;
    final fade = (1 - progress) * (1 - progress);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + (1 - progress) * 6
      ..color = accentLight.withValues(alpha: 0.5 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, r, ring);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18 * (1 - progress)
      ..color = accent.withValues(alpha: 0.18 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(center, r * 0.95, glow);
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter old) =>
      old.progress != progress;
}
