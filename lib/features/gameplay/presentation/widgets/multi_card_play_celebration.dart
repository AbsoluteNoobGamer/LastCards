import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimum cards played **this turn** (shared engine counter) to show feedback.
const int kMultiPlayCelebrationMinCards = 3;

/// Tier by cumulative cards played this turn: mild / medium / epic.
///
/// Requires [cardsPlayedThisTurn] >= [kMultiPlayCelebrationMinCards].
int multiPlayCelebrationTierIndex(int cardsPlayedThisTurn) {
  assert(cardsPlayedThisTurn >= kMultiPlayCelebrationMinCards);
  if (cardsPlayedThisTurn <= 4) return 0;
  if (cardsPlayedThisTurn <= 6) return 1;
  return 2;
}

const _tierNames = ['NICE', 'COMBO', 'LEGENDARY'];

/// Fixed "fire" palette — deliberately independent of the active theme, same
/// way suit colors stay fixed. This is the combo feature's own signature.
const _tierColors = [
  Color(0xFFFFA000), // amber
  Color(0xFFFF6D00), // deep orange
  Color(0xFFFF3D00), // red-orange (paired with gold in the gradient text)
];
const _tierColorsLight = [
  Color(0xFFFFD54F),
  Color(0xFFFFB300),
  Color(0xFFFFD54F),
];

/// Fire-themed pulse + badge + embers when a player stacks many cards in one
/// turn. [tierIndex] is 0–2 from [multiPlayCelebrationTierIndex].
///
/// [cardCount] drives the "×N" badge text; pass `null` to show the ambient
/// glow/embers only (used when this overlay is reused for a non-combo beat,
/// e.g. a stack-cancel flash, where there's no real card count to report).
class MultiCardPlayCelebrationOverlay extends StatefulWidget {
  const MultiCardPlayCelebrationOverlay({
    super.key,
    required this.trigger,
    required this.tierIndex,
    this.cardCount,
  });

  final int trigger;
  final int tierIndex;
  final int? cardCount;

  @override
  State<MultiCardPlayCelebrationOverlay> createState() =>
      _MultiCardPlayCelebrationOverlayState();
}

class _MultiCardPlayCelebrationOverlayState
    extends State<MultiCardPlayCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _tierDurations = [
    Duration(milliseconds: 850),
    Duration(milliseconds: 1150),
    Duration(milliseconds: 1550),
  ];

  static const _tierMaxOpacity = [0.30, 0.42, 0.56];
  static const _tierEmberCounts = [8, 16, 28];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: _tierDurations[0],
    );
  }

  @override
  void didUpdateWidget(covariant MultiCardPlayCelebrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) {
      final tier = widget.tierIndex.clamp(0, 2);
      _c.duration = _tierDurations[tier];
      if (!MediaQuery.disableAnimationsOf(context)) {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _strength(double t) {
    final fi = 0.22;
    if (t <= fi) return (t / fi).clamp(0.0, 1.0);
    final u = (t - fi) / (1.0 - fi);
    return (1.0 - u).clamp(0.0, 1.0);
  }

  /// Bounce-in scale for the badge: overshoots past 1.0 then settles.
  double _badgeScale(double t) {
    const inEnd = 0.22;
    if (t <= inEnd) {
      final u = (t / inEnd).clamp(0.0, 1.0);
      return Curves.easeOutBack.transform(u);
    }
    final u = ((t - inEnd) / (1.0 - inEnd)).clamp(0.0, 1.0);
    return 1.0 - 0.06 * (1 - (1 - u).abs()) * math.sin(u * math.pi * 3);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    final tier = widget.tierIndex.clamp(0, 2);
    final color = _tierColors[tier];
    final colorLight = _tierColorsLight[tier];
    final maxOp = _tierMaxOpacity[tier];
    final emberCount = _tierEmberCounts[tier];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final s = _strength(t);
        if (s <= 0.001) return const SizedBox.shrink();

        // Brief impact shake at the top tier only — decays fast.
        final shakeT = (t / 0.35).clamp(0.0, 1.0);
        final shakeDamp = tier >= 2 ? (1.0 - shakeT) : 0.0;
        final dx = tier >= 2
            ? math.sin(t * math.pi * 26) * 3.2 * shakeDamp
            : 0.0;

        return Transform.translate(
          offset: Offset(dx, 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _RadialEdgePulsePainter(
                  color: color,
                  opacity: s * maxOp,
                ),
                size: Size.infinite,
              ),
              if (tier >= 1)
                CustomPaint(
                  painter: _CenterGlowPulsePainter(
                    color: colorLight,
                    opacity: s * maxOp * 0.5,
                  ),
                  size: Size.infinite,
                ),
              CustomPaint(
                painter: _EmberPainter(
                  progress: t,
                  strength: s,
                  count: emberCount,
                  color: color,
                  colorLight: colorLight,
                  seed: widget.trigger,
                ),
                size: Size.infinite,
              ),
              if (widget.cardCount != null)
                Align(
                  alignment: const Alignment(0, -0.06),
                  child: Opacity(
                    opacity: s,
                    child: Transform.scale(
                      scale: _badgeScale(t),
                      child: _ComboBadge(
                        tierName: _tierNames[tier],
                        cardCount: widget.cardCount!,
                        color: color,
                        colorLight: colorLight,
                        tier: tier,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({
    required this.tierName,
    required this.cardCount,
    required this.color,
    required this.colorLight,
    required this.tier,
  });

  final String tierName;
  final int cardCount;
  final Color color;
  final Color colorLight;
  final int tier;

  @override
  Widget build(BuildContext context) {
    final fontSize = 22.0 + tier * 8.0;
    final countFontSize = fontSize + 10;

    Widget text(String s, double size, {Gradient? gradient}) {
      final style = TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: gradient == null ? colorLight : Colors.white,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.9), blurRadius: 14),
          Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      );
      if (gradient == null) return Text(s, style: style);
      return ShaderMask(
        shaderCallback: (rect) => gradient.createShader(rect),
        child: Text(s, style: style),
      );
    }

    final gradient = tier >= 2
        ? LinearGradient(colors: [colorLight, color, colorLight])
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        text(tierName, fontSize, gradient: gradient),
        text('×$cardCount', countFontSize, gradient: gradient),
      ],
    );
  }
}

class _EmberPainter extends CustomPainter {
  _EmberPainter({
    required this.progress,
    required this.strength,
    required this.count,
    required this.color,
    required this.colorLight,
    required this.seed,
  });

  final double progress;
  final double strength;
  final int count;
  final Color color;
  final Color colorLight;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || strength <= 0) return;
    const phi = 0.6180339887;
    final origin = Offset(size.width / 2, size.height * 0.58);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final seedVal = (i + 1 + seed * 0.01);
      final angle = ((seedVal * phi) % 1.0) * math.pi * 2;
      final spread = 40.0 + ((seedVal * 2.7) % 1.0) * size.shortestSide * 0.32;
      final rise = progress * (60.0 + ((seedVal * 1.9) % 1.0) * 90.0);
      final wobble = math.sin(progress * math.pi * 4 + i) * 8.0;

      final dx = origin.dx + math.cos(angle) * spread * progress + wobble;
      final dy = origin.dy + math.sin(angle) * spread * 0.4 * progress - rise;

      final flicker = 0.5 + 0.5 * math.sin(progress * math.pi * 10 + i * 1.7);
      final alpha = (strength * flicker).clamp(0.0, 1.0);
      final t = (i % 3 == 0) ? colorLight : color;
      paint.color = t.withValues(alpha: alpha * 0.85);
      final r = 1.4 + (i % 4) * 0.7;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strength != strength;
}

class _RadialEdgePulsePainter extends CustomPainter {
  _RadialEdgePulsePainter({
    required this.color,
    required this.opacity,
  });

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0),
          color.withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _RadialEdgePulsePainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color;
}

class _CenterGlowPulsePainter extends CustomPainter {
  _CenterGlowPulsePainter({
    required this.color,
    required this.opacity,
  });

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.42);
    final r = size.shortestSide * 0.55;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _CenterGlowPulsePainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
