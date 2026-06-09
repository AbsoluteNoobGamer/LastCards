import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Win celebration shown behind the win dialog (~5s, then auto-disposes).
///
/// A hand-rolled [CustomPainter] particle system (no game-engine dependency):
/// a staggered burst of gold confetti + sparkles fountains up from the winner's
/// zone with gravity, drag, spin and lifetime fade, layered with radial gold
/// pulses in the style of [MultiCardPlayCelebrationOverlay].
///
/// Honours the app-wide accessibility / performance settings:
///   * Reduce-motion → a simple **static** "Winner" flourish, no particle motion.
///   * Budget-device mode → particle count is capped low (≈40 instead of a few
///     hundred).
class WinCelebrationOverlay extends StatefulWidget {
  const WinCelebrationOverlay({
    super.key,
    required this.theme,
    required this.onFinished,
    this.budgetDevice = false,
  });

  final AppThemeData theme;
  final VoidCallback onFinished;

  /// When true, caps the particle count for low-end devices.
  final bool budgetDevice;

  @override
  State<WinCelebrationOverlay> createState() => _WinCelebrationOverlayState();
}

class _WinCelebrationOverlayState extends State<WinCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  static const int _kDuration = 5000;
  static const int _kFullCount = 220;
  static const int _kBudgetCount = 40;

  late final AnimationController _ctrl;
  late final List<_Confetti> _particles;
  final _rand = math.Random(42);

  bool _reduceMotion = false;
  Timer? _staticTimer;

  @override
  void initState() {
    super.initState();
    final count = widget.budgetDevice ? _kBudgetCount : _kFullCount;
    _particles = List.generate(count, (_) => _spawnConfetti());
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kDuration),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        // Reduce-motion: hold a static flourish briefly, then clean up.
        setState(() => _reduceMotion = true);
        _staticTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) widget.onFinished();
        });
        return;
      }
      _ctrl.forward().whenComplete(() {
        if (mounted) widget.onFinished();
      });
    });
  }

  /// One confetti/sparkle particle. Motion is evaluated analytically in the
  /// painter (closed-form linear-drag projectile), so the model only stores the
  /// initial conditions.
  _Confetti _spawnConfetti() {
    final isSparkle = _rand.nextDouble() < 0.32;
    // Fountain out of the winner's zone (bottom-centre of the table).
    final originX = 0.5 + (_rand.nextDouble() - 0.5) * 0.42;
    final originY = 0.80 + _rand.nextDouble() * 0.10;
    // Mostly upward, fanned out to the sides.
    final spread = (_rand.nextDouble() - 0.5) * 1.8; // ±0.9 rad off vertical
    final speed = 0.5 + _rand.nextDouble() * 0.95;
    return _Confetti(
      // Stagger emission across the first ~400ms.
      spawnDelay: _rand.nextDouble() * 0.4,
      originX: originX,
      originY: originY,
      vx: math.sin(spread) * speed,
      vy: -math.cos(spread) * speed, // negative = up (screen y is down)
      gravity: 1.0 + _rand.nextDouble() * 0.6,
      drag: 0.7 + _rand.nextDouble() * 0.6,
      size: isSparkle
          ? 2.0 + _rand.nextDouble() * 3.0
          : 6.0 + _rand.nextDouble() * 7.0,
      rotation: _rand.nextDouble() * math.pi * 2,
      angularVelocity: (_rand.nextDouble() - 0.5) * 12.0,
      lifetime: 2.6 + _rand.nextDouble() * 2.0,
      colorIndex: _rand.nextInt(4),
      twinklePhase: _rand.nextDouble() * math.pi * 2,
      shape: isSparkle ? _ConfettiShape.sparkle : _ConfettiShape.confetti,
    );
  }

  @override
  void dispose() {
    _staticTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _StaticWinnerFlourishPainter(theme: widget.theme),
          size: Size.infinite,
        ),
      );
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

enum _ConfettiShape { confetti, sparkle }

class _WinCelebrationPainter extends CustomPainter {
  _WinCelebrationPainter({
    required this.progress,
    required this.theme,
    required this.particles,
  });

  final double progress;
  final AppThemeData theme;
  final List<_Confetti> particles;

  static const double _totalSeconds = 5.0;
  static const double _flashPhase = 320 / 5000;
  static const double _pulsePhase = 1100 / 5000;

  Color _particleColor(int colorIndex) {
    switch (colorIndex) {
      case 0:
        return theme.accentPrimary;
      case 1:
        return theme.accentLight;
      case 2:
        return const Color(0xFFF7EFD6); // cream
      default:
        return Colors.white;
    }
  }

  /// Bright white core flash at the very start.
  void _paintRadialFlash(Canvas canvas, Size size, Offset origin) {
    if (progress > _flashPhase) return;
    final t = progress / _flashPhase;
    final opacity = (1.0 - t) * 0.5;
    final r = t * size.longestSide * 0.5;
    canvas.drawCircle(
      origin,
      r,
      Paint()..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }

  /// Radial gold pulses in the style of the multi-card celebration: a gold edge
  /// bloom plus an expanding ring rising from the winner's zone.
  void _paintGoldPulses(Canvas canvas, Size size, Offset origin) {
    if (progress > _pulsePhase) return;
    final t = (progress / _pulsePhase).clamp(0.0, 1.0);
    // Rise then fall over the pulse window.
    final strength = t < 0.28 ? t / 0.28 : (1.0 - (t - 0.28) / 0.72);
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.001) return;

    final rect = Offset.zero & size;
    // Gold edge bloom.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            theme.accentPrimary.withValues(alpha: 0),
            theme.accentPrimary.withValues(alpha: 0.30 * s),
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );

    // Expanding ring from the winner's zone.
    final ringR = size.shortestSide * (0.15 + t * 0.85);
    final ringRect = Rect.fromCircle(center: origin, radius: ringR);
    canvas.drawCircle(
      origin,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + 6.0 * s
        ..shader = RadialGradient(
          colors: [
            theme.accentLight.withValues(alpha: 0.0),
            theme.accentLight.withValues(alpha: 0.45 * s),
          ],
          stops: const [0.7, 1.0],
        ).createShader(ringRect),
    );
  }

  void _drawConfetti(
    Canvas canvas,
    Offset center,
    double size,
    double rotation,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    // A thin rectangular streamer — the classic confetti look.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size, height: size * 0.5),
        const Radius.circular(1),
      ),
      paint,
    );
    canvas.restore();
  }

  void _drawSparkle(Canvas canvas, Offset center, double r, Paint paint) {
    // 4-point star: two crossed thin diamonds.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final path = Path()
      ..moveTo(0, -r)
      ..lineTo(r * 0.22, 0)
      ..lineTo(0, r)
      ..lineTo(-r * 0.22, 0)
      ..close()
      ..moveTo(-r, 0)
      ..lineTo(0, r * 0.22)
      ..lineTo(r, 0)
      ..lineTo(0, -r * 0.22)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final origin = Offset(size.width * 0.5, size.height * 0.82);
    final elapsed = progress * _totalSeconds;
    final reference = size.shortestSide;

    _paintRadialFlash(canvas, size, origin);
    _paintGoldPulses(canvas, size, origin);

    for (final p in particles) {
      final localT = elapsed - p.spawnDelay;
      if (localT <= 0) continue;
      final lifeFrac = localT / p.lifetime;
      if (lifeFrac >= 1.0) continue;

      // Closed-form linear-drag projectile (cheap: one exp per particle).
      final k = p.drag;
      final ex = 1.0 - math.exp(-k * localT);
      final dx = (p.vx / k) * ex;
      final dy = ((p.vy + p.gravity / k) / k) * ex - (p.gravity / k) * localT;
      final px = p.originX * size.width + dx * reference;
      final py = p.originY * size.height + dy * reference;

      final fadeIn = (localT / 0.12).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - lifeFrac) / 0.35).clamp(0.0, 1.0);
      final alpha = (fadeIn * fadeOut).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;

      final color = _particleColor(p.colorIndex);

      if (p.shape == _ConfettiShape.sparkle) {
        final twinkle =
            0.55 + 0.45 * math.sin(localT * 9.0 + p.twinklePhase);
        final paint = Paint()
          ..color = color.withValues(alpha: (alpha * twinkle).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        _drawSparkle(canvas, Offset(px, py), p.size * (0.8 + 0.2 * twinkle),
            paint);
      } else {
        final rotation = p.rotation + p.angularVelocity * localT;
        // Fake foreshortening so streamers feel like they flutter.
        final flutter = (0.55 + 0.45 * math.sin(rotation)).abs();
        final paint = Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.fill;
        _drawConfetti(
          canvas,
          Offset(px, py),
          p.size * (0.5 + 0.5 * flutter),
          rotation,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WinCelebrationPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.theme != theme;
  }
}

/// Static, motion-free "Winner" flourish for reduce-motion: a soft gold radial
/// bloom over the winner's zone with a fixed ring of sparkles.
class _StaticWinnerFlourishPainter extends CustomPainter {
  _StaticWinnerFlourishPainter({required this.theme});

  final AppThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width * 0.5, size.height * 0.5);

    // Soft gold bloom.
    final bloomR = size.shortestSide * 0.55;
    canvas.drawCircle(
      center,
      bloomR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            theme.accentPrimary.withValues(alpha: 0.22),
            theme.accentPrimary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: bloomR)),
    );

    // A static ring of sparkles framing the dialog.
    final ringR = size.shortestSide * 0.42;
    final sparklePaint = Paint()
      ..color = theme.accentLight.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    const count = 16;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final pos = center +
          Offset(math.cos(angle) * ringR, math.sin(angle) * ringR * 0.7);
      final r = (i.isEven) ? 3.0 : 2.0;
      canvas.drawCircle(pos, r, sparklePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StaticWinnerFlourishPainter oldDelegate) =>
      oldDelegate.theme != theme;
}

class _Confetti {
  _Confetti({
    required this.spawnDelay,
    required this.originX,
    required this.originY,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.drag,
    required this.size,
    required this.rotation,
    required this.angularVelocity,
    required this.lifetime,
    required this.colorIndex,
    required this.twinklePhase,
    required this.shape,
  });

  /// Seconds before this particle is emitted (staggered over the first ~400ms).
  final double spawnDelay;

  /// Emission origin in normalized screen coords (winner's zone).
  final double originX;
  final double originY;

  /// Initial velocity in reference-units (shortest side) per second.
  final double vx;
  final double vy;

  /// Downward acceleration, reference-units per second².
  final double gravity;

  /// Linear drag coefficient.
  final double drag;

  /// Draw size in logical pixels.
  final double size;

  final double rotation;
  final double angularVelocity;

  /// Total visible lifetime in seconds; alpha fades to 0 by the end.
  final double lifetime;

  final int colorIndex;
  final double twinklePhase;
  final _ConfettiShape shape;
}
