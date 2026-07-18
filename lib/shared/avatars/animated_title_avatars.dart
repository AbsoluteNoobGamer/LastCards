import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'avatar_catalog.dart';

/// Full-scene animated face for a leaderboard title (not a static PNG + aura).
class AnimatedTitleAvatar extends StatefulWidget {
  const AnimatedTitleAvatar({
    super.key,
    required this.kind,
    required this.size,
  });

  final AvatarExclusiveKind kind;
  final double size;

  @override
  State<AnimatedTitleAvatar> createState() => _AnimatedTitleAvatarState();
}

class _AnimatedTitleAvatarState extends State<AnimatedTitleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs(widget.kind)),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedTitleAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _loop
        ..duration = Duration(milliseconds: _durationMs(widget.kind))
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  static int _durationMs(AvatarExclusiveKind kind) => switch (kind) {
        AvatarExclusiveKind.comboKing => 3200,
        AvatarExclusiveKind.bustOnline => 2800,
        AvatarExclusiveKind.tourneyAi ||
        AvatarExclusiveKind.tourneyOnline =>
          2600,
        _ => 2400,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) {
            return CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _TitleScenePainter(
                kind: widget.kind,
                t: _loop.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TitleScenePainter extends CustomPainter {
  _TitleScenePainter({required this.kind, required this.t});

  final AvatarExclusiveKind kind;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    switch (kind) {
      case AvatarExclusiveKind.comboKing:
        _paintComboKing(canvas, size, c, r);
      case AvatarExclusiveKind.rankedCrown:
        _paintRanked(canvas, size, c, r);
      case AvatarExclusiveKind.hardcoreCrown:
        _paintHardcore(canvas, size, c, r);
      case AvatarExclusiveKind.casualAce:
        _paintCasual(canvas, size, c, r);
      case AvatarExclusiveKind.tourneyAi:
        _paintTourney(canvas, size, c, r, online: false);
      case AvatarExclusiveKind.tourneyOnline:
        _paintTourney(canvas, size, c, r, online: true);
      case AvatarExclusiveKind.bustOnline:
        _paintBust(canvas, size, c, r);
    }
  }

  // ── Combo King: cards drop and stack into a pile ─────────────────────────

  void _paintComboKing(Canvas canvas, Size size, Offset c, double r) {
    // Dark felt + gold rim.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF2A1810), Color(0xFF0A0604)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = const Color(0xFFC9A84C),
    );

    // Flickering flames behind the pile.
    _paintFlames(canvas, c, r, t);

    // Cards drop one-by-one onto a growing pile, then the loop resets.
    const n = 5;
    // Leave the last ~15% of the cycle as a hold on the full pile.
    const buildEnd = 0.85;
    for (var i = 0; i < n; i++) {
      final appearAt = (i / n) * buildEnd;
      final age = t - appearAt;
      if (age < 0) continue;

      const dropDur = 0.12;
      final dropT = (age / dropDur).clamp(0.0, 1.0);
      final ease = Curves.easeOutCubic.transform(dropT);

      final restAngle = -0.32 + i * 0.16;
      final restY = c.dy + r * 0.1 - i * r * 0.045;
      final restX = c.dx + (i - 2) * r * 0.035;

      final startY = c.dy - r * 1.4;
      final y = startY + (restY - startY) * ease;
      final angle = restAngle * ease;

      canvas.save();
      canvas.translate(restX, y);
      canvas.rotate(angle);
      _drawMiniCard(
        canvas,
        Size(r * 0.55, r * 0.78),
        faceDark: true,
        crestGold: true,
      );
      canvas.restore();
    }

    // Embers rising.
    final ember = Paint()..color = const Color(0xFFFFB300);
    for (var i = 0; i < 8; i++) {
      final p = (t + i * 0.13) % 1.0;
      final x = c.dx + math.sin(i * 2.1 + t * math.pi * 2) * r * 0.35;
      final y = c.dy + r * 0.45 - p * r * 1.1;
      ember.color = Color(0xFFFFB300).withValues(alpha: (1 - p) * 0.85);
      canvas.drawCircle(Offset(x, y), r * 0.03 * (1 - p * 0.5), ember);
    }
  }

  void _paintFlames(Canvas canvas, Offset c, double r, double t) {
    final flame = Path();
    final baseY = c.dy + r * 0.35;
    for (var i = 0; i < 7; i++) {
      final flicker = 0.85 + 0.15 * math.sin(t * math.pi * 6 + i);
      final x = c.dx + (i - 3) * r * 0.12;
      final h = r * (0.55 + 0.2 * flicker) * (1 - (i - 3).abs() * 0.08);
      flame.reset();
      flame.moveTo(x - r * 0.08, baseY);
      flame.quadraticBezierTo(
        x - r * 0.02,
        baseY - h * 0.55,
        x,
        baseY - h,
      );
      flame.quadraticBezierTo(
        x + r * 0.02,
        baseY - h * 0.55,
        x + r * 0.08,
        baseY,
      );
      flame.close();
      canvas.drawPath(
        flame,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              const Color(0xFFE65100).withValues(alpha: 0.9),
              const Color(0xFFFFD54F).withValues(alpha: 0.75),
              const Color(0xFFFFF8E1).withValues(alpha: 0.2),
            ],
          ).createShader(Rect.fromLTWH(x - r * 0.1, baseY - h, r * 0.2, h)),
      );
    }
  }

  void _drawMiniCard(
    Canvas canvas,
    Size size, {
    required bool faceDark,
    required bool crestGold,
  }) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width,
      height: size.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.12));
    canvas.drawRRect(
      rrect,
      Paint()..color = faceDark ? const Color(0xFF1A1410) : Colors.white,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.06
        ..color = const Color(0xFFC9A84C),
    );
    if (crestGold) {
      final crest = Path()
        ..moveTo(0, -size.height * 0.18)
        ..lineTo(size.width * 0.12, size.height * 0.05)
        ..lineTo(0, size.height * 0.16)
        ..lineTo(-size.width * 0.12, size.height * 0.05)
        ..close();
      canvas.drawPath(crest, Paint()..color = const Color(0xFFE8CC7A));
    }
  }

  // ── Ranked: trophy bob + gem pulse + shine sweep ─────────────────────────

  void _paintRanked(Canvas canvas, Size size, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1A0A2E));
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = const Color(0xFFC9A84C),
    );

    final bob = math.sin(t * math.pi * 2) * r * 0.03;
    final cupC = Offset(c.dx, c.dy + bob);

    // Cup body.
    final cup = Path()
      ..moveTo(cupC.dx - r * 0.22, cupC.dy - r * 0.05)
      ..quadraticBezierTo(
        cupC.dx - r * 0.28,
        cupC.dy - r * 0.35,
        cupC.dx,
        cupC.dy - r * 0.38,
      )
      ..quadraticBezierTo(
        cupC.dx + r * 0.28,
        cupC.dy - r * 0.35,
        cupC.dx + r * 0.22,
        cupC.dy - r * 0.05,
      )
      ..lineTo(cupC.dx + r * 0.12, cupC.dy + r * 0.15)
      ..lineTo(cupC.dx - r * 0.12, cupC.dy + r * 0.15)
      ..close();
    canvas.drawPath(cup, Paint()..color = const Color(0xFFE8CC7A));

    // Stem + base.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cupC.dx, cupC.dy + r * 0.28),
          width: r * 0.1,
          height: r * 0.22,
        ),
        Radius.circular(r * 0.02),
      ),
      Paint()..color = const Color(0xFFC9A84C),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cupC.dx, cupC.dy + r * 0.42),
          width: r * 0.38,
          height: r * 0.1,
        ),
        Radius.circular(r * 0.03),
      ),
      Paint()..color = const Color(0xFF8A6D28),
    );

    // Pulsing gem.
    final gemPulse = 0.7 + 0.3 * math.sin(t * math.pi * 4);
    canvas.drawCircle(
      Offset(cupC.dx, cupC.dy - r * 0.12),
      r * 0.07 * gemPulse,
      Paint()..color = Color(0xFFCE93D8).withValues(alpha: gemPulse),
    );

    // Shine sweep across cup.
    final shineX = cupC.dx - r * 0.3 + (t * r * 0.6);
    canvas.drawLine(
      Offset(shineX, cupC.dy - r * 0.35),
      Offset(shineX + r * 0.08, cupC.dy + r * 0.1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = r * 0.04
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Hardcore: skull with pulsing eyes / jaw flicker ──────────────────────

  void _paintHardcore(Canvas canvas, Size size, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0A0000));
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = const Color(0xFFE53935),
    );

    // Red aura shards.
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3 + t * 0.4;
      final pulse = 0.7 + 0.3 * math.sin(t * math.pi * 2 + i);
      final tip = Offset(
        c.dx + math.cos(a) * r * 0.85 * pulse,
        c.dy + math.sin(a) * r * 0.85 * pulse,
      );
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(
          c.dx + math.cos(a - 0.15) * r * 0.4,
          c.dy + math.sin(a - 0.15) * r * 0.4,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          c.dx + math.cos(a + 0.15) * r * 0.4,
          c.dy + math.sin(a + 0.15) * r * 0.4,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFE53935).withValues(alpha: 0.35),
      );
    }

    // Skull.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx, c.dy - r * 0.05), width: r * 0.9, height: r * 1.0),
      Paint()..color = const Color(0xFFF5EFE0),
    );

    // Eyes pulse red.
    final eyeGlow = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 3));
    final eyePaint = Paint()
      ..color = Color(0xFFE53935).withValues(alpha: eyeGlow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.18, c.dy - r * 0.08),
        width: r * 0.22,
        height: r * 0.28,
      ),
      Paint()..color = Colors.black,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.18, c.dy - r * 0.08),
        width: r * 0.22,
        height: r * 0.28,
      ),
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(Offset(c.dx - r * 0.18, c.dy - r * 0.08), r * 0.06, eyePaint);
    canvas.drawCircle(Offset(c.dx + r * 0.18, c.dy - r * 0.08), r * 0.06, eyePaint);

    // Crown gem.
    canvas.drawCircle(
      Offset(c.dx, c.dy - r * 0.55),
      r * 0.08 * (0.85 + 0.15 * math.sin(t * math.pi * 4)),
      Paint()..color = const Color(0xFFE53935),
    );
  }

  // ── Casual: ace card tilts, network nodes travel ─────────────────────────

  void _paintCasual(Canvas canvas, Size size, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D3A3A));
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = const Color(0xFFB0BEC5),
    );

    // Orbiting player nodes.
    for (var i = 0; i < 3; i++) {
      final a = t * math.pi * 2 + i * (math.pi * 2 / 3);
      final p = Offset(
        c.dx + math.cos(a) * r * 0.62,
        c.dy + math.sin(a) * r * 0.62,
      );
      canvas.drawCircle(p, r * 0.09, Paint()..color = const Color(0xFF4DD0E1));
      canvas.drawCircle(p, r * 0.05, Paint()..color = Colors.white70);
    }
    // Arc connectors.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.62),
      t * math.pi * 2,
      math.pi * 1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.02
        ..color = const Color(0xFF4DD0E1).withValues(alpha: 0.55),
    );

    // Tilting ace.
    final tilt = 0.18 * math.sin(t * math.pi * 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    _drawMiniCard(
      canvas,
      Size(r * 0.7, r * 1.0),
      faceDark: false,
      crestGold: false,
    );
    // Red diamond.
    final dia = Path()
      ..moveTo(0, -r * 0.22)
      ..lineTo(r * 0.16, 0)
      ..lineTo(0, r * 0.22)
      ..lineTo(-r * 0.16, 0)
      ..close();
    canvas.drawPath(dia, Paint()..color = const Color(0xFFE53935));
    canvas.restore();
  }

  // ── Tournament: brackets light up, star spins ────────────────────────────

  void _paintTourney(
    Canvas canvas,
    Size size,
    Offset c,
    double r, {
    required bool online,
  }) {
    canvas.drawCircle(
      c,
      r,
      Paint()..color = online ? const Color(0xFF0D1B3A) : const Color(0xFF0D2B1A),
    );
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = const Color(0xFFC0C0C0),
    );

    // Sequential bracket glow (4 → 2 → 1).
    final stage = (t * 3).floor() % 3;
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.035
      ..strokeCap = StrokeCap.round;

    void drawBracket(double xSign, int litStage) {
      final baseX = c.dx + xSign * r * 0.35;
      bracketPaint.color = stage >= litStage
          ? const Color(0xFFE8CC7A)
          : const Color(0xFF607D8B);
      // Two outer slots → merge.
      canvas.drawLine(
        Offset(baseX, c.dy - r * 0.28),
        Offset(baseX + xSign * r * 0.12, c.dy - r * 0.28),
        bracketPaint,
      );
      canvas.drawLine(
        Offset(baseX, c.dy + r * 0.28),
        Offset(baseX + xSign * r * 0.12, c.dy + r * 0.28),
        bracketPaint,
      );
      canvas.drawLine(
        Offset(baseX + xSign * r * 0.12, c.dy - r * 0.28),
        Offset(baseX + xSign * r * 0.12, c.dy + r * 0.28),
        bracketPaint,
      );
      canvas.drawLine(
        Offset(baseX + xSign * r * 0.12, c.dy),
        Offset(c.dx + xSign * r * 0.08, c.dy),
        bracketPaint,
      );
    }

    drawBracket(-1, 0);
    drawBracket(1, 1);

    // Center star spins / pulses when final stage.
    final starScale = stage >= 2 ? 1.0 + 0.15 * math.sin(t * math.pi * 8) : 0.85;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * math.pi * 2);
    canvas.scale(starScale);
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rad = i.isEven ? r * 0.22 : r * 0.08;
      final p = Offset(math.cos(a) * rad, math.sin(a) * rad);
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFE8CC7A));
    canvas.restore();

    // Crown bob at top.
    final bob = math.sin(t * math.pi * 2) * r * 0.02;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy - r * 0.55 + bob),
          width: r * 0.35,
          height: r * 0.14,
        ),
        Radius.circular(r * 0.02),
      ),
      Paint()..color = const Color(0xFFC0C0C0),
    );
  }

  // ── Bust: card rises from crack, debris flies, blast pulses ──────────────

  void _paintBust(Canvas canvas, Size size, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1A0C08));
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = const Color(0xFFB87333),
    );

    // Explosion rays.
    final blast = 0.7 + 0.3 * math.sin(t * math.pi * 4);
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + t * 0.5;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(
          c.dx + math.cos(a - 0.08) * r * 0.3,
          c.dy + math.sin(a - 0.08) * r * 0.3,
        )
        ..lineTo(
          c.dx + math.cos(a) * r * 0.75 * blast,
          c.dy + math.sin(a) * r * 0.75 * blast,
        )
        ..lineTo(
          c.dx + math.cos(a + 0.08) * r * 0.3,
          c.dy + math.sin(a + 0.08) * r * 0.3,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.55),
      );
    }

    // Rising card (0→0.5 up, 0.5→1 hold/shake).
    final rise = Curves.easeOutBack.transform((t / 0.5).clamp(0.0, 1.0));
    final shake = t > 0.5 ? math.sin(t * math.pi * 16) * r * 0.015 : 0.0;
    final cardY = c.dy + r * 0.35 - rise * r * 0.45;
    canvas.save();
    canvas.translate(c.dx + shake, cardY);
    canvas.rotate(0.12);
    _drawMiniCard(
      canvas,
      Size(r * 0.55, r * 0.8),
      faceDark: true,
      crestGold: false,
    );
    // Orange X.
    final xPaint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.12, -r * 0.12), Offset(r * 0.12, r * 0.12), xPaint);
    canvas.drawLine(Offset(r * 0.12, -r * 0.12), Offset(-r * 0.12, r * 0.12), xPaint);
    canvas.restore();

    // Debris.
    for (var i = 0; i < 6; i++) {
      final p = (t + i * 0.15) % 1.0;
      final a = -math.pi / 2 + (i - 2.5) * 0.35;
      final dist = p * r * 0.7;
      final pos = Offset(
        c.dx + math.cos(a) * dist,
        c.dy + r * 0.25 + math.sin(a) * dist * 0.4,
      );
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: r * 0.06, height: r * 0.05),
        Paint()..color = const Color(0xFF5D4037).withValues(alpha: 1 - p),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TitleScenePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.kind != kind;
  }
}
