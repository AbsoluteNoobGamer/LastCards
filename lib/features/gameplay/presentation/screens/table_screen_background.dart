part of 'table_screen.dart';

// ── Background ────────────────────────────────────────────────────────────────

class _FeltTableBackground extends ConsumerWidget {
  const _FeltTableBackground();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Positioned.fill(
      child: CustomPaint(
        painter: _TableBackgroundPainter(
          themeId: theme.id,
          baseColor: theme.backgroundDeep,
          midColor: theme.backgroundMid,
          accentColor: theme.accentPrimary,
          accentDark: theme.accentDark,
        ),
      ),
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _TableBackgroundPainter extends CustomPainter {
  const _TableBackgroundPainter({
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
    weavePaint.color = midColor.withValues(alpha: 0.55);
    for (double d = -size.height; d < size.width + size.height; d += cell) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        weavePaint,
      );
    }

    // Set B: top-right to bottom-left diagonals
    weavePaint.color = const Color(0xFF080808).withValues(alpha: 0.7);
    for (double d = size.width + size.height; d > -size.height; d -= cell) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d - size.height, size.height),
        weavePaint,
      );
    }

    // 3. Subtle highlight squares at weave intersections (every other cell)
    final dotPaint = Paint()
      ..color = const Color(0xFFB0B8C1).withValues(alpha: 0.07)
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
            const Color(0xFF2A2A2E).withValues(alpha: 0.5),
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
      ..color = midColor.withValues(alpha: 0.25);

    const gap = 8.0;
    for (double d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), hatch);
    }
    for (double d = size.width + size.height; d > -size.height; d -= gap) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), hatch);
    }

    // Small felt dots at every other intersection
    final dot = Paint()
      ..color = midColor.withValues(alpha: 0.12)
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
            const Color(0xFF2A6040).withValues(alpha: 0.45),
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
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.06);
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
          center: Alignment(0, -0.4),
          radius: 0.85,
          colors: [
            const Color(0xFF3A2800).withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.longestSide * 0.7),
        ),
    );

    // Faint gold corner accents
    final cornerPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.04)
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
      ..color = Colors.white.withValues(alpha: 0.55)
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

    // Deep space radial gradient — midnight blue bloom
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.7,
          colors: [
            const Color(0xFF0D1A38).withValues(alpha: 0.7),
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
        alpha: ((y / size.height) * 0.12 + 0.04),
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
            const Color(0xFF5A1020).withValues(alpha: 0.45),
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
              midColor.withValues(alpha: 0.06),
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
      ..color = const Color(0xFFC0C0C0).withValues(alpha: 0.04);
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
            const Color(0xFF303038).withValues(alpha: 0.5),
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
      ..color = const Color(0xFF50C878).withValues(alpha: 0.07);
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
            const Color(0xFF1A4A28).withValues(alpha: 0.55),
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
      ..color = const Color(0xFF2979FF).withValues(alpha: 0.09);
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
            const Color(0xFF0A1060).withValues(alpha: 0.6),
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
      ..color = accentColor.withValues(alpha: 0.06);
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
            const Color(0xFF2A1008).withValues(alpha: 0.6),
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
      ..color = Colors.white.withValues(alpha: 0.05);
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
            const Color(0xFF1A2030).withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.shortestSide * 0.55),
        ),
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
  bool shouldRepaint(_TableBackgroundPainter old) =>
      old.themeId != themeId ||
      old.baseColor != baseColor ||
      old.midColor != midColor ||
      old.accentColor != accentColor;
}

// ── Placeholder widgets ───────────────────────────────────────────────────────

class _EmptyOpponentZone extends StatelessWidget {
  const _EmptyOpponentZone();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 80);
  }
}
