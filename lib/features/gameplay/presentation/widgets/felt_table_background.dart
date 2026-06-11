import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/features/settings/presentation/widgets/settings_modal.dart';

/// Animated casino felt table background shared by [TableScreen] and Bust.
class FeltTableBackground extends ConsumerStatefulWidget {
  const FeltTableBackground({super.key});

  @override
  ConsumerState<FeltTableBackground> createState() =>
      FeltTableBackgroundState();
}

class FeltTableBackgroundState extends ConsumerState<FeltTableBackground>
    with TickerProviderStateMixin {
  late AnimationController _breath;
  late AnimationController _particles;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _breath.repeat(reverse: true);
        _particles.repeat();
      }
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    // Static (uTime frozen at 0) when reduce-motion or budget-device mode is on,
    // so the premium felt look is preserved without per-frame shader cost.
    final animateFelt = !MediaQuery.disableAnimationsOf(context) &&
        !ref.watch(budgetDeviceModeProvider);
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _FeltShaderLayer(
              feltColor: theme.backgroundDeep,
              animate: animateFelt,
              child: CustomPaint(
                painter: TableBackgroundPainter(
                  themeId: theme.id,
                  baseColor: theme.backgroundDeep,
                  midColor: theme.backgroundMid,
                  accentColor: theme.accentPrimary,
                  accentDark: theme.accentDark,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _breath,
              builder: (_, __) {
                // Animate opacity only — changing [RadialGradient.radius] every
                // frame can contribute to relayout-boundary assertions on some GPUs.
                final v = 0.5 + 0.5 * math.sin(_breath.value * 2 * math.pi);
                final spotlightY = theme.id == 'gold'
                    ? -0.25
                    : theme.id == 'crimson_velvet'
                        ? -0.05
                        : theme.id == 'arctic'
                            ? -0.30
                            : -0.15;
                return IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, spotlightY),
                        radius: 0.89,
                        colors: [
                          theme.accentPrimary.withValues(alpha: 0.16 * v),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!MediaQuery.disableAnimationsOf(context))
              AnimatedBuilder(
                animation: _particles,
                builder: (_, __) {
                  return CustomPaint(
                    painter: TableAmbientParticlesPainter(
                      progress: _particles.value,
                      accentColor: theme.accentPrimary,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Generative "premium casino felt" shader layer (`shaders/felt_background.frag`)
/// drawn over the themed felt: a breathing centre spotlight, faint fabric grain
/// and a slow vignette, tinted in the active theme's deep base colour.
///
/// When [animate] is false (reduce-motion or budget-device mode) the shader is
/// rendered once with `uTime` frozen at 0 — a static version, not disabled — so
/// no [Ticker] runs and there is no per-frame cost.
class _FeltShaderLayer extends StatefulWidget {
  const _FeltShaderLayer({
    required this.feltColor,
    required this.animate,
    required this.child,
  });

  /// Base felt colour fed to `uFeltColor` (the active theme's deep background).
  final Color feltColor;

  /// When false, renders a single static frame with no [Ticker].
  final bool animate;

  /// The themed felt painted underneath; the shader composites over it.
  final Widget child;

  @override
  State<_FeltShaderLayer> createState() => _FeltShaderLayerState();
}

class _FeltShaderLayerState extends State<_FeltShaderLayer>
    with SingleTickerProviderStateMixin {
  // How strongly the generative felt overlays the themed felt underneath.
  // Tasteful and low-contrast: the spotlight/grain/vignette read clearly while
  // the themed pattern still shows through.
  static const double _overlayOpacity = 0.7;

  /// Strength of the felt effect (`uIntensity`).
  static const double _intensity = 1.0;

  Ticker? _ticker;
  double _timeSeconds = 0.0;

  void _ensureTickerRunning() {
    _ticker ??= createTicker((elapsed) {
      setState(() {
        _timeSeconds =
            elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      });
    });
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _stopTicker() {
    if (_ticker?.isActive ?? false) _ticker!.stop();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.animate) {
      _ensureTickerRunning();
    } else {
      _stopTicker();
      _timeSeconds = 0.0;
    }

    final felt = widget.feltColor;

    return ShaderBuilder(
      (context, shader, child) {
        return AnimatedSampler(
          (ui.Image image, Size size, Canvas canvas) {
            // Themed felt first, then the generative felt composited over it.
            canvas.drawImage(image, Offset.zero, Paint());
            shader
              ..setFloat(0, size.width)
              ..setFloat(1, size.height)
              ..setFloat(2, _timeSeconds)
              ..setFloat(3, _intensity)
              ..setFloat(4, felt.r)
              ..setFloat(5, felt.g)
              ..setFloat(6, felt.b);
            final rect = Offset.zero & size;
            canvas.saveLayer(
              rect,
              Paint()..color = Colors.white.withValues(alpha: _overlayOpacity),
            );
            canvas.drawRect(rect, Paint()..shader = shader);
            canvas.restore();
          },
          child: child!,
        );
      },
      assetKey: 'shaders/felt_background.frag',
      child: widget.child,
    );
  }
}

/// Subtle drifting particles (~55) for ambient depth; max opacity capped at 0.20.
class TableAmbientParticlesPainter extends CustomPainter {
  TableAmbientParticlesPainter({
    required this.progress,
    required this.accentColor,
  });

  final double progress;
  final Color accentColor;

  static const int _count = 55;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const phi = 0.6180339887;
    const phi2 = 0.3819660113;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _count; i++) {
      final nx = ((i + 1) * phi) % 1.0;
      final ny = ((i + 1) * phi2) % 1.0;
      final baseX = nx * size.width;
      final baseY = ny * size.height;
      final driftY = progress * 0.30 * size.height;
      final y = (baseY + driftY) % size.height;
      final wobbleX =
          math.sin(progress * math.pi * 2 + i * 0.41) * (3.0 + (i % 4));
      final x = baseX + wobbleX;
      final twinkle =
          (0.5 + 0.5 * math.sin(progress * math.pi * 2 * 0.7 + i * 0.35))
              .clamp(0.0, 1.0);
      final alpha = (0.08 + 0.12 * twinkle).clamp(0.0, 0.20);
      paint.color = accentColor.withValues(alpha: alpha);
      final r = 1.2 + (i % 5) * 0.35;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(TableAmbientParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
}

// ── Painter ────────────────────────────────────────────────────────────────────

class TableBackgroundPainter extends CustomPainter {
  const TableBackgroundPainter({
    required this.themeId,
    required this.baseColor,
    required this.midColor,
    required this.accentColor,
    required this.accentDark,
  });

  final String themeId;
  final Color baseColor;
  final Color midColor;
  final Color accentColor;
  final Color accentDark;

  @override
  void paint(Canvas canvas, Size size) {
    switch (themeId) {
      case 'carbon':
        _paintCarbon(canvas, size);
      case 'classic_felt':
        _paintClassicFelt(canvas, size);
      case 'gold':
        _paintGold(canvas, size);
      case 'midnight_navy':
        _paintNightSky(canvas, size);
      case 'crimson_velvet':
        _paintVelvet(canvas, size);
      case 'obsidian':
        _paintObsidian(canvas, size);
      case 'emerald_royale':
        _paintEmeraldRoyale(canvas, size);
      case 'sapphire':
        _paintSapphire(canvas, size);
      case 'copper_noir':
        _paintCopperNoir(canvas, size);
      case 'arctic':
        _paintArctic(canvas, size);
      case 'volcanic':
        _paintVolcanic(canvas, size);
      case 'neon_grid':
        _paintNeonGrid(canvas, size);
      case 'monte_carlo':
        _paintMonteCarlo(canvas, size);
      default:
        _paintGeneric(canvas, size);
    }

    // Universal vignette on top of every theme
    _paintVignette(canvas, size, opacity: 0.55);
  }

  // ── Carbon Fibre ────────────────────────────────────────────────────────────
  void _paintCarbon(Canvas canvas, Size size) {
    // 1. Deep near-black base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // 2. Carbon fibre weave — two crossed sets of fine diagonal lines
    //    creating the classic 45° diamond/square weave pattern
    const cell = 12.0;  // weave cell size

    final weavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Set A: top-left to bottom-right diagonals
    weavePaint.color = midColor.withValues(alpha: 0.75);
    for (double d = -size.height; d < size.width + size.height; d += cell) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        weavePaint,
      );
    }

    // Set B: top-right to bottom-left diagonals
    weavePaint.color = const Color(0xFF080808).withValues(alpha: 0.85);
    for (double d = size.width + size.height; d > -size.height; d -= cell) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d - size.height, size.height),
        weavePaint,
      );
    }

    // 3. Subtle highlight squares at weave intersections (every other cell)
    final dotPaint = Paint()
      ..color = const Color(0xFFB0B8C1).withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += cell * 2) {
      for (double y = 0; y < size.height; y += cell * 2) {
        canvas.drawRect(
          Rect.fromLTWH(x + cell * 0.15, y + cell * 0.15, cell * 0.7, cell * 0.7),
          dotPaint,
        );
      }
    }

    // 4. Central silver radial bloom
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: [
            const Color(0xFF2A2A2E).withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.longestSide * 0.6),
        ),
    );
  }

  // ── Classic Felt ────────────────────────────────────────────────────────────
  void _paintClassicFelt(Canvas canvas, Size size) {
    // Rich casino felt — deep green with diagonal texture weave
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Felt diagonal cross-hatch texture
    final hatch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = midColor.withValues(alpha: 0.40);

    const gap = 8.0;
    for (double d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), hatch);
    }
    for (double d = size.width + size.height; d > -size.height; d -= gap) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), hatch);
    }

    // Small felt dots at every other intersection
    final dot = Paint()
      ..color = midColor.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += gap * 2) {
      for (double y = 0; y < size.height; y += gap * 2) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }

    // Warm overhead light glow center
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.55,
          colors: [
            const Color(0xFF2A6040).withValues(alpha: 0.60),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55),
        ),
    );
  }

  // ── Gold ─────────────────────────────────────────────────────────────────────
  void _paintGold(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Diagonal diagonal thin grid — lattice pattern
    final lattice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.12);
    const gap = 20.0;
    for (double d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), lattice);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), lattice);
    }

    // Gold shimmer radial from center-top (like a chandelier)
    final centre = Offset(size.width / 2, size.height * 0.3);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0, -0.55),
          radius: 0.85,
          colors: [
            const Color(0xFF3A2800).withValues(alpha: 0.75),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.longestSide * 0.7),
        ),
    );

    // Faint gold corner accents
    final cornerPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, 0), size.shortestSide * 0.4, cornerPaint);
    canvas.drawCircle(Offset(size.width, 0), size.shortestSide * 0.4, cornerPaint);
    canvas.drawCircle(Offset(0, size.height), size.shortestSide * 0.4, cornerPaint);
    canvas.drawCircle(Offset(size.width, size.height), size.shortestSide * 0.4, cornerPaint);
  }

  // ── Midnight Navy ────────────────────────────────────────────────────────────
  void _paintNightSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Star field — tiny dots
    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    final rng = _seededPoints(size, seed: 42);
    for (final pt in rng) {
      canvas.drawCircle(pt, 0.7, starPaint);
    }

    // A few brighter stars
    final brightStar = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    final bright = _seededPoints(size, seed: 7, count: 12);
    for (final pt in bright) {
      canvas.drawCircle(pt, 1.2, brightStar);
    }

    // Extra-bright accent stars
    final extraBrightStar = Paint()
      ..color = Colors.white.withValues(alpha: 1.0)
      ..style = PaintingStyle.fill;
    final extraBright = _seededPoints(size, seed: 19, count: 5);
    for (final pt in extraBright) {
      canvas.drawCircle(pt, 1.8, extraBrightStar);
    }

    // Deep space radial gradient — midnight blue bloom
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.7,
          colors: [
            const Color(0xFF0D1A38).withValues(alpha: 0.80),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.longestSide * 0.55),
        ),
    );
  }

  // ── Crimson Velvet ────────────────────────────────────────────────────────
  void _paintVelvet(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Velvet directional brush strokes (near-horizontal thin lines)
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const gap = 5.0;
    for (double y = 0; y < size.height; y += gap) {
      stroke.color = midColor.withValues(
        alpha: ((y / size.height) * 0.14 + 0.08),
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 4), stroke);
    }

    // Velvet sheen — diagonal highlight from top-right
    final centre = Offset(size.width * 0.7, size.height * 0.1);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, -0.7),
          radius: 0.9,
          colors: [
            const Color(0xFF5A1020).withValues(alpha: 0.62),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.longestSide * 0.8),
        ),
    );
  }

  // ── Obsidian ────────────────────────────────────────────────────────────────
  void _paintObsidian(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Obsidian sheen — concentric ring-like gradient layers
    final centre = Offset(size.width / 2, size.height / 2);
    for (int i = 3; i >= 1; i--) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: i * 0.4,
            colors: [
              Colors.transparent,
              midColor.withValues(alpha: 0.12),
            ],
          ).createShader(
            Rect.fromCircle(center: centre, radius: size.longestSide * i * 0.35),
          ),
      );
    }

    // Fine chevron-like pattern
    final chevron = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFFC0C0C0).withValues(alpha: 0.09);
    const gap = 14.0;
    for (double y = 0; y < size.height + gap; y += gap) {
      final path = Path()
        ..moveTo(0, y)
        ..lineTo(size.width / 2, y - gap / 2)
        ..lineTo(size.width, y);
      canvas.drawPath(path, chevron);
    }

    // Silver sheen centre bloom
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.6,
          colors: [
            const Color(0xFF303038).withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.5),
        ),
    );
  }

  // ── Emerald Royale ─────────────────────────────────────────────────────────
  void _paintEmeraldRoyale(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Ornate diamond grid
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0xFF50C878).withValues(alpha: 0.14);
    const cell = 28.0;
    for (double x = 0; x < size.width + cell; x += cell) {
      for (double y = 0; y < size.height + cell; y += cell) {
        final path = Path()
          ..moveTo(x, y - cell / 2)
          ..lineTo(x + cell / 2, y)
          ..lineTo(x, y + cell / 2)
          ..lineTo(x - cell / 2, y)
          ..close();
        canvas.drawPath(path, grid);
      }
    }

    // Gold champagne centre radiance
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.65,
          colors: [
            const Color(0xFF1A4A28).withValues(alpha: 0.68),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55),
        ),
    );
  }

  // ── Sapphire ────────────────────────────────────────────────────────────────
  void _paintSapphire(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Hexagonal honeycomb pattern (just the edges)
    final hex = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFF2979FF).withValues(alpha: 0.18);
    const r = 18.0;
    final dx = r * 1.732; // sqrt(3) * r
    final dy = r * 1.5;
    for (double col = 0; col < size.width + dx; col += dx) {
      for (double row = 0; row < size.height + dy * 2; row += dy * 2) {
        final offset = (col ~/ dx) % 2 == 0 ? 0.0 : dy;
        _drawHex(canvas, Offset(col, row + offset), r, hex);
      }
    }

    // Deep sapphire radial glow
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.7,
          colors: [
            const Color(0xFF0A1060).withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.6),
        ),
    );
  }

  void _drawHex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // ── Copper Noir ─────────────────────────────────────────────────────────────
  void _paintCopperNoir(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Art deco fan pattern — semi-circular arcs
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = accentColor.withValues(alpha: 0.12);
    const fanR = 60.0;
    for (double x = 0; x < size.width + fanR; x += fanR) {
      for (double y = 0; y < size.height + fanR; y += fanR) {
        for (double r = fanR * 0.25; r <= fanR; r += fanR * 0.25) {
          canvas.drawArc(
            Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 2),
            0, math.pi, false, arc,
          );
        }
      }
    }

    // Warm copper radial glow
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.7,
          colors: [
            const Color(0xFF2A1008).withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55),
        ),
    );
  }

  // ── Arctic ──────────────────────────────────────────────────────────────────
  void _paintArctic(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Ice crystal fractal — thin radiating lines from a point
    final crystal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.11);
    final centres = [
      Offset(size.width * 0.2, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.15),
      Offset(size.width * 0.5, size.height * 0.65),
      Offset(size.width * 0.1, size.height * 0.75),
      Offset(size.width * 0.88, size.height * 0.8),
    ];
    for (final ctr in centres) {
      for (int i = 0; i < 12; i++) {
        final angle = (i * 30) * math.pi / 180;
        const len = 55.0;
        canvas.drawLine(
          ctr,
          Offset(ctr.dx + len * math.cos(angle), ctr.dy + len * math.sin(angle)),
          crystal,
        );
        // Small crossbar at 2/3 length
        final bx = ctr.dx + len * 0.6 * math.cos(angle);
        final by = ctr.dy + len * 0.6 * math.sin(angle);
        final perp = angle + math.pi / 2;
        canvas.drawLine(
          Offset(bx - 6 * math.cos(perp), by - 6 * math.sin(perp)),
          Offset(bx + 6 * math.cos(perp), by + 6 * math.sin(perp)),
          crystal,
        );
      }
    }

    // Cold blue-white centre glow
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.65,
          colors: [
            const Color(0xFF1A2030).withValues(alpha: 0.68),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55),
        ),
    );
  }

  // ── Volcanic ────────────────────────────────────────────────────────────────
  void _paintVolcanic(Canvas canvas, Size size) {
    // 1. Deep near-black base
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0D0500));

    // 2. Lava crack network — irregular diagonal lines in glowing orange
    final crackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFF5722).withValues(alpha: 0.22);

    // Main cracks — deterministic positions using golden ratio offsets
    final crackStarts = [
      Offset(size.width * 0.15, 0),
      Offset(size.width * 0.45, 0),
      Offset(size.width * 0.72, 0),
      Offset(0, size.height * 0.30),
      Offset(0, size.height * 0.65),
      Offset(size.width, size.height * 0.20),
      Offset(size.width, size.height * 0.55),
      Offset(size.width * 0.28, size.height),
      Offset(size.width * 0.60, size.height),
    ];
    final crackEnds = [
      Offset(size.width * 0.38, size.height * 0.55),
      Offset(size.width * 0.60, size.height * 0.42),
      Offset(size.width * 0.55, size.height * 0.70),
      Offset(size.width * 0.50, size.height * 0.40),
      Offset(size.width * 0.42, size.height * 0.72),
      Offset(size.width * 0.52, size.height * 0.35),
      Offset(size.width * 0.48, size.height * 0.60),
      Offset(size.width * 0.50, size.height * 0.55),
      Offset(size.width * 0.55, size.height * 0.45),
    ];
    for (int i = 0; i < crackStarts.length; i++) {
      canvas.drawLine(crackStarts[i], crackEnds[i], crackPaint);
    }

    // Glowing core at crack intersections — orange radial
    final glowPaint = Paint()
      ..color = const Color(0xFFFF5722).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.50),
        size.shortestSide * 0.18, glowPaint);

    // 3. Ember glow from bottom (heat rising effect)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFBF360C).withValues(alpha: 0.50),
            const Color(0xFFFF5722).withValues(alpha: 0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 0.7],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  // ── Neon Grid ───────────────────────────────────────────────────────────────
  void _paintNeonGrid(Canvas canvas, Size size) {
    // 1. True black base
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF020008));

    // 2. Perspective grid — horizontal lines converging toward horizon
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.18);

    const horizon = 0.45; // horizon line at 45% down
    final vanishX = size.width / 2;
    final vanishY = size.height * horizon;

    // Horizontal grid lines (evenly spaced below horizon)
    const lineCount = 10;
    for (int i = 1; i <= lineCount; i++) {
      final y = vanishY + (size.height - vanishY) * (i / lineCount);
      final alpha = 0.08 + 0.14 * (i / lineCount);
      gridPaint.color = const Color(0xFF00E5FF).withValues(alpha: alpha);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines converging to vanishing point
    const vLineCount = 12;
    for (int i = 0; i <= vLineCount; i++) {
      final x = size.width * (i / vLineCount);
      final alpha = 0.06 + 0.10 * (1 - (x - vanishX).abs() / (size.width / 2));
      gridPaint.color = const Color(0xFF00E5FF).withValues(alpha: alpha.clamp(0.06, 0.18));
      canvas.drawLine(Offset(vanishX, vanishY), Offset(x, size.height), gridPaint);
    }

    // 3. Horizon glow line
    final horizonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFF00FF).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(
      Offset(0, vanishY),
      Offset(size.width, vanishY),
      horizonPaint,
    );

    // 4. Magenta corner glows
    final cornerGlow = Paint()
      ..color = const Color(0xFFFF00FF).withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(Offset(0, size.height), size.shortestSide * 0.5, cornerGlow);
    canvas.drawCircle(Offset(size.width, size.height), size.shortestSide * 0.5, cornerGlow);

    // 5. Cyan centre bloom
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.65,
          colors: [
            const Color(0xFF001A20).withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width / 2, vanishY),
          radius: size.shortestSide * 0.6,
        )),
    );
  }

  // ── Monte Carlo ─────────────────────────────────────────────────────────────
  void _paintMonteCarlo(Canvas canvas, Size size) {
    // 1. Deep burgundy base
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF12020A));

    // 2. Roulette wheel outline — concentric rings centred in background
    final centre = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final ringRadii = [0.18, 0.28, 0.36, 0.44, 0.52];
    for (int i = 0; i < ringRadii.length; i++) {
      final alpha = 0.06 + (i * 0.02);
      ringPaint.color = const Color(0xFFE8C87A).withValues(alpha: alpha);
      canvas.drawCircle(centre, size.shortestSide * ringRadii[i], ringPaint);
    }

    // Wheel spokes — 18 radial lines
    final spokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFFE8C87A).withValues(alpha: 0.05);
    for (int i = 0; i < 18; i++) {
      final angle = (i * 20) * math.pi / 180;
      final innerR = size.shortestSide * 0.18;
      final outerR = size.shortestSide * 0.52;
      canvas.drawLine(
        Offset(centre.dx + innerR * math.cos(angle),
            centre.dy + innerR * math.sin(angle)),
        Offset(centre.dx + outerR * math.cos(angle),
            centre.dy + outerR * math.sin(angle)),
        spokePaint,
      );
    }

    // Alternating red/black segments hint between spokes (very faint fills)
    for (int i = 0; i < 18; i++) {
      final angle1 = (i * 20) * math.pi / 180;
      final angle2 = ((i + 1) * 20) * math.pi / 180;
      final segPath = Path()
        ..moveTo(centre.dx + size.shortestSide * 0.18 * math.cos(angle1),
            centre.dy + size.shortestSide * 0.18 * math.sin(angle1))
        ..arcTo(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.36),
          angle1, 20 * math.pi / 180, false,
        )
        ..arcTo(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.18),
          angle2, -20 * math.pi / 180, false,
        )
        ..close();
      canvas.drawPath(
        segPath,
        Paint()
          ..color = (i % 2 == 0
              ? const Color(0xFFCC2244)
              : const Color(0xFF0A0105))
              .withValues(alpha: 0.08),
      );
    }

    // 3. Gold radial bloom over wheel
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.65,
          colors: [
            const Color(0xFF2A1008).withValues(alpha: 0.68),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55)),
    );
  }

  // ── Generic fallback ────────────────────────────────────────────────────────
  void _paintGeneric(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, midColor],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final dot = Paint()
      ..color = midColor.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += 6) {
      for (double y = 0; y < size.height; y += 6) {
        if (((x ~/ 6) + (y ~/ 6)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dot);
        }
      }
    }
  }

  // ── Universal vignette ──────────────────────────────────────────────────────
  void _paintVignette(Canvas canvas, Size size, {double opacity = 0.5}) {
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
            Colors.black.withValues(alpha: opacity),
          ],
          stops: const [0.45, 1.0],
        ).createShader(
          Rect.fromCircle(center: centre, radius: radius),
        ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Generates deterministic pseudo-random points using formula-based offsets.
  /// Avoids large integer multiplication so it works on Dart web (JS ints).
  List<Offset> _seededPoints(Size size, {int seed = 1, int count = 80}) {
    final points = <Offset>[];
    // Golden ratio-based Halton sequence — no large multiplications.
    const phi1 = 0.6180339887; // 1/φ
    const phi2 = 0.3819660113; // 1/φ²
    var x = (seed * phi1) % 1.0;
    var y = (seed * phi2) % 1.0;
    for (int i = 0; i < count; i++) {
      x = (x + phi1) % 1.0;
      y = (y + phi2) % 1.0;
      points.add(Offset(x * size.width, y * size.height));
    }
    return points;
  }



  @override
  bool shouldRepaint(TableBackgroundPainter old) =>
      old.themeId != themeId ||
      old.baseColor != baseColor ||
      old.midColor != midColor ||
      old.accentColor != accentColor;
}
