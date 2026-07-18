import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/card_model.dart';

/// Soft gold / warm white palette shared by special-card table moments.
abstract final class SpecialMomentPalette {
  static const gold = Color(0xFFE8C87A);
  static const warmWhite = Color(0xFFF5E6C8);
  static const softDanger = Color(0xFFE57373);
}

Offset? globalCenterOf(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

// ── Ace / Joker suit bloom ────────────────────────────────────────────────────

/// Soft suit symbol bloom over the discard / board center.
class SuitBloomOverlay extends StatefulWidget {
  const SuitBloomOverlay({
    super.key,
    required this.trigger,
    required this.suit,
    this.anchorKey,
  });

  final int trigger;
  final Suit? suit;
  final GlobalKey? anchorKey;

  @override
  State<SuitBloomOverlay> createState() => _SuitBloomOverlayState();
}

class _SuitBloomOverlayState extends State<SuitBloomOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  Suit? _suit;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _suit = widget.suit;
  }

  @override
  void didUpdateWidget(covariant SuitBloomOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _suit = widget.suit;
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

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    final suit = _suit;
    if (suit == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _t.value;
          if (t <= 0.001 || t >= 0.999) return const SizedBox.shrink();

          final opacity = t < 0.25
              ? (t / 0.25)
              : t > 0.65
                  ? (1.0 - (t - 0.65) / 0.35)
                  : 1.0;
          final scale = 0.55 + 0.55 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

          return LayoutBuilder(
            builder: (context, constraints) {
              final stackBox = context.findRenderObject() as RenderBox?;
              Offset localCenter = Offset(
                constraints.maxWidth / 2,
                constraints.maxHeight * 0.42,
              );
              final anchor = widget.anchorKey;
              if (anchor != null && stackBox != null && stackBox.hasSize) {
                final global = globalCenterOf(anchor);
                if (global != null) {
                  localCenter = stackBox.globalToLocal(global);
                }
              }

              final color = suit.isRed
                  ? const Color(0xFFE57373)
                  : SpecialMomentPalette.warmWhite;

              return Stack(
                children: [
                  Positioned(
                    left: localCenter.dx - 48,
                    top: localCenter.dy - 48,
                    child: Opacity(
                      opacity: opacity * 0.55,
                      child: Transform.scale(
                        scale: 0.8 + t * 1.4,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                SpecialMomentPalette.gold
                                    .withValues(alpha: 0.45),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: localCenter.dx - 22,
                    top: localCenter.dy - 28,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Text(
                          suit.symbol,
                          style: TextStyle(
                            fontSize: 44,
                            color: color,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: SpecialMomentPalette.gold
                                    .withValues(alpha: 0.55 * opacity),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Eight skip arc ────────────────────────────────────────────────────────────

/// Soft gold dash that arcs from the acting seat toward skipped seat(s).
class SkipArcOverlay extends StatefulWidget {
  const SkipArcOverlay({
    super.key,
    required this.trigger,
    required this.fromKey,
    required this.toKeys,
  });

  final int trigger;
  final GlobalKey? fromKey;
  final List<GlobalKey> toKeys;

  @override
  State<SkipArcOverlay> createState() => _SkipArcOverlayState();
}

class _SkipArcOverlayState extends State<SkipArcOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  Offset? _from;
  List<Offset> _tos = const [];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(covariant SkipArcOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _capture();
        if (MediaQuery.disableAnimationsOf(context)) return;
        _c.forward(from: 0);
      });
    }
  }

  void _capture() {
    final stackBox = context.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final fromG =
        widget.fromKey != null ? globalCenterOf(widget.fromKey!) : null;
    if (fromG == null) {
      _from = null;
      _tos = const [];
      return;
    }
    _from = stackBox.globalToLocal(fromG);
    final tos = <Offset>[];
    for (final key in widget.toKeys) {
      final g = globalCenterOf(key);
      if (g != null) tos.add(stackBox.globalToLocal(g));
    }
    _tos = tos;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _t.value;
          final from = _from;
          if (t <= 0.001 || t >= 0.999 || from == null || _tos.isEmpty) {
            return const SizedBox.shrink();
          }
          return CustomPaint(
            painter: _SkipArcPainter(
              progress: t,
              from: from,
              tos: _tos,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _SkipArcPainter extends CustomPainter {
  _SkipArcPainter({
    required this.progress,
    required this.from,
    required this.tos,
  });

  final double progress;
  final Offset from;
  final List<Offset> tos;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = progress < 0.2
        ? progress / 0.2
        : progress > 0.75
            ? (1.0 - (progress - 0.75) / 0.25)
            : 1.0;

    for (final to in tos) {
      final mid = Offset(
        (from.dx + to.dx) / 2,
        math.min(from.dy, to.dy) - 36,
      );
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);

      final metric = path.computeMetrics().first;
      final end = metric.length * progress;
      final extract = metric.extractPath(0, end);

      canvas.drawPath(
        extract,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = SpecialMomentPalette.gold.withValues(alpha: 0.55 * opacity),
      );

      final tip = metric.getTangentForOffset(end)?.position ?? to;
      final iconPaint = Paint()
        ..color = SpecialMomentPalette.warmWhite.withValues(alpha: 0.85 * opacity);
      // Small chevron tip.
      final chevron = Path()
        ..moveTo(tip.dx - 5, tip.dy - 4)
        ..lineTo(tip.dx + 4, tip.dy)
        ..lineTo(tip.dx - 5, tip.dy + 4);
      canvas.drawPath(
        chevron,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = iconPaint.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkipArcPainter old) =>
      old.progress != progress || old.from != from || old.tos != tos;
}

// ── Draw-pile penalty bump / Red Jack clear ───────────────────────────────────

enum DrawPileFxKind { none, penaltyBump, redJackClear }

/// Soft moment over the draw pile (penalty weight / Red Jack cancel).
class DrawPileFxOverlay extends StatefulWidget {
  const DrawPileFxOverlay({
    super.key,
    required this.trigger,
    required this.kind,
    required this.drawPileKey,
  });

  final int trigger;
  final DrawPileFxKind kind;
  final GlobalKey drawPileKey;

  @override
  State<DrawPileFxOverlay> createState() => _DrawPileFxOverlayState();
}

class _DrawPileFxOverlayState extends State<DrawPileFxOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  DrawPileFxKind _kind = DrawPileFxKind.none;
  Offset? _center;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant DrawPileFxOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _kind = widget.kind;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _capture();
        if (MediaQuery.disableAnimationsOf(context)) return;
        _c.forward(from: 0);
      });
    }
  }

  void _capture() {
    final stackBox = context.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final g = globalCenterOf(widget.drawPileKey);
    if (g == null) {
      _center = null;
      return;
    }
    _center = stackBox.globalToLocal(g);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _t.value;
          final center = _center;
          if (t <= 0.001 ||
              t >= 0.999 ||
              center == null ||
              _kind == DrawPileFxKind.none) {
            return const SizedBox.shrink();
          }

          final opacity = t < 0.2
              ? t / 0.2
              : t > 0.7
                  ? (1.0 - (t - 0.7) / 0.3)
                  : 1.0;

          if (_kind == DrawPileFxKind.redJackClear) {
            return CustomPaint(
              painter: _RedJackClearPainter(
                center: center,
                progress: t,
                opacity: opacity,
              ),
              size: Size.infinite,
            );
          }

          // Penalty bump — soft danger ring + weight pulse.
          final scale = 1.0 + 0.12 * math.sin(t * math.pi);
          return Stack(
            children: [
              Positioned(
                left: center.dx - 40 * scale,
                top: center.dy - 40 * scale,
                child: Opacity(
                  opacity: opacity * 0.7,
                  child: Container(
                    width: 80 * scale,
                    height: 80 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SpecialMomentPalette.softDanger
                            .withValues(alpha: 0.55 * opacity),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SpecialMomentPalette.softDanger
                              .withValues(alpha: 0.25 * opacity),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RedJackClearPainter extends CustomPainter {
  _RedJackClearPainter({
    required this.center,
    required this.progress,
    required this.opacity,
  });

  final Offset center;
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final r = 18.0 + 56.0 * progress;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - progress * 0.5)
        ..color = SpecialMomentPalette.warmWhite.withValues(alpha: 0.55 * opacity),
    );
    // Soft “shatter” ticks.
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * math.pi * 2 + progress * 0.8;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (r * 0.55);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (r * 1.05);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = SpecialMomentPalette.gold.withValues(alpha: 0.45 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RedJackClearPainter old) =>
      old.progress != progress || old.opacity != opacity || old.center != center;
}

// ── Queen suit-lock ring ──────────────────────────────────────────────────────

/// Soft gold ring that follows the seat under an active Queen lock.
class QueenLockRingOverlay extends StatelessWidget {
  const QueenLockRingOverlay({
    super.key,
    required this.active,
    required this.targetKey,
    this.suit,
  });

  final bool active;
  final GlobalKey? targetKey;
  final Suit? suit;

  @override
  Widget build(BuildContext context) {
    if (!active || targetKey == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackBox = context.findRenderObject() as RenderBox?;
          if (stackBox == null || !stackBox.hasSize) {
            return const SizedBox.shrink();
          }
          final g = globalCenterOf(targetKey!);
          if (g == null) return const SizedBox.shrink();
          final c = stackBox.globalToLocal(g);
          final suitColor = suit?.isRed == true
              ? const Color(0xFFE57373)
              : SpecialMomentPalette.warmWhite;

          return Stack(
            children: [
              Positioned(
                left: c.dx - 34,
                top: c.dy - 40,
                child: _PulsingLockRing(suitColor: suitColor, suit: suit),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PulsingLockRing extends StatefulWidget {
  const _PulsingLockRing({required this.suitColor, this.suit});

  final Color suitColor;
  final Suit? suit;

  @override
  State<_PulsingLockRing> createState() => _PulsingLockRingState();
}

class _PulsingLockRingState extends State<_PulsingLockRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _ring(0.55);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => _ring(0.4 + 0.35 * _c.value),
    );
  }

  Widget _ring(double opacity) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: SpecialMomentPalette.gold.withValues(alpha: opacity),
                width: 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: SpecialMomentPalette.gold.withValues(alpha: 0.25 * opacity),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          if (widget.suit != null)
            Text(
              widget.suit!.symbol,
              style: TextStyle(
                fontSize: 14,
                color: widget.suitColor.withValues(alpha: 0.9 * opacity),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
