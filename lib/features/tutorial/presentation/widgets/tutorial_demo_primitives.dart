import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/card_model.dart';
import '../../../gameplay/presentation/widgets/card_widget.dart';
import '../../../settings/presentation/widgets/settings_modal.dart' show reduceMotionProvider;

/// Local progress (0..1) of [t] within the [start]-[end] window of an
/// overall 0..1 animation — the building block every demo phase is
/// expressed against instead of hand-rolled `Interval`s.
double phaseProgress(double t, double start, double end) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return (t - start) / (end - start);
}

/// Drives a single looping (or, under Reduce Motion, frozen-at-end) 0..1
/// animation and hands the current value to [builder] on every tick. This
/// is the only widget in the tutorial that owns an [AnimationController] —
/// every demo primitive below is a stateless function of that shared `t`,
/// so a slide only ever runs one ticker at a time.
class LoopingDemo extends ConsumerStatefulWidget {
  const LoopingDemo({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 3200),
    this.pause = const Duration(milliseconds: 900),
  });

  final Widget Function(BuildContext context, double t) builder;
  final Duration duration;
  final Duration pause;

  @override
  ConsumerState<LoopingDemo> createState() => _LoopingDemoState();
}

class _LoopingDemoState extends ConsumerState<LoopingDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _startLoop();
  }

  Future<void> _startLoop() async {
    if (_running) return;
    _running = true;
    while (mounted) {
      if (ref.read(reduceMotionProvider)) {
        _controller.value = 1.0;
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      await _controller.forward(from: 0);
      if (!mounted) return;
      await Future.delayed(widget.pause);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reduceMotionProvider);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// A card that flies from [from] to [to] as [t] moves 0 → 1, easing in/out
/// and fading in from nothing so it doesn't "pop" at its start offset
/// before its phase begins.
class FlightCard extends StatelessWidget {
  const FlightCard({
    super.key,
    required this.card,
    required this.from,
    required this.to,
    required this.t,
    this.width = 40,
    this.faceUp = true,
  });

  final CardModel card;
  final Offset from;
  final Offset to;
  final double t;
  final double width;
  final bool faceUp;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final eased = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final pos = Offset.lerp(from, to, eased)!;
    final height = width * 1.4;
    return Positioned(
      left: pos.dx - width / 2,
      top: pos.dy - height / 2,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: CardWidget(card: card, width: width, faceUp: faceUp, animateFlip: false),
      ),
    );
  }
}

/// A static card rendered at a fixed anchor (e.g. the discard pile's
/// current top card, or a draw-pile back) — no animation of its own.
class AnchoredCard extends StatelessWidget {
  const AnchoredCard({
    super.key,
    required this.card,
    required this.at,
    this.width = 40,
    this.faceUp = true,
    this.opacity = 1.0,
  });

  final CardModel card;
  final Offset at;
  final double width;
  final bool faceUp;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.4;
    return Positioned(
      left: at.dx - width / 2,
      top: at.dy - height / 2,
      child: Opacity(
        opacity: opacity,
        child: CardWidget(card: card, width: width, faceUp: faceUp, animateFlip: false),
      ),
    );
  }
}

/// Dims a seat to show it's been skipped/targeted, fading in over [t].
class SeatGreyOut extends StatelessWidget {
  const SeatGreyOut({super.key, required this.at, required this.t});

  final Offset at;
  final double t;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    return Positioned(
      left: at.dx - 22,
      top: at.dy - 12,
      child: Opacity(
        opacity: (t * 0.75).clamp(0.0, 0.75),
        child: Container(
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// A small badge (e.g. "+2", a suit glyph, a padlock, "Declared: Q♠") that
/// pops in with a scale + fade as [t] moves 0 → 1.
class PopBadge extends StatelessWidget {
  const PopBadge({
    super.key,
    required this.at,
    required this.t,
    required this.child,
    required this.color,
  });

  final Offset at;
  final double t;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final scale = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale.clamp(0.0, 1.2),
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A skip icon arcing up and over a seat as [t] moves 0 → 1.
class SkipArc extends StatelessWidget {
  const SkipArc({super.key, required this.at, required this.t, required this.color});

  final Offset at;
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final lift = -24 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    return Positioned(
      left: at.dx - 10,
      top: at.dy - 30 + lift,
      child: Opacity(
        opacity: (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0),
        child: Icon(Icons.fast_forward_rounded, size: 20, color: color),
      ),
    );
  }
}

/// A curved arrow ring around the table that flips orientation as [t]
/// moves 0 → 1 (used for the King's direction-reversal demo).
class DirectionArrowRing extends StatelessWidget {
  const DirectionArrowRing({super.key, required this.center, required this.t, required this.color});

  final Offset center;
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final angle = eased * 3.14159265;
    return Positioned(
      left: center.dx - 60,
      top: center.dy - 60,
      child: Transform.rotate(
        angle: angle,
        child: SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(painter: _ArrowRingPainter(color: color)),
        ),
      ),
    );
  }
}

class _ArrowRingPainter extends CustomPainter {
  const _ArrowRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawArc(rect.deflate(8), -1.2, 4.6, false, paint);

    final tipAngle = -1.2 + 4.6;
    final radius = size.width / 2 - 8;
    final tip = Offset(
      size.width / 2 + radius * math.cos(tipAngle),
      size.height / 2 + radius * math.sin(tipAngle),
    );
    final arrowPaint = Paint()..color = color.withValues(alpha: 0.9);
    canvas.drawCircle(tip, 4, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _ArrowRingPainter oldDelegate) => oldDelegate.color != color;
}
