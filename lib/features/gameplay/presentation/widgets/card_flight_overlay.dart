import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../domain/entities/card.dart';
import 'card_back_widget.dart';
import 'card_widget.dart';

/// Full-screen overlay that animates a card along a quadratic Bézier arc
/// between two widgets identified by [GlobalKey]s (hand → discard or similar).
class CardFlightOverlay extends StatefulWidget {
  const CardFlightOverlay({super.key});

  @override
  CardFlightOverlayState createState() => CardFlightOverlayState();
}

class CardFlightOverlayState extends State<CardFlightOverlay>
    with TickerProviderStateMixin {
  final List<_Flight> _flights = [];

  /// Animates one card from [originKey] centre to [targetKey] centre.
  /// [faceUp] false uses card back (opponent plays).
  Future<void> flyCard({
    required GlobalKey? originKey,
    required GlobalKey? targetKey,
    required CardModel card,
    bool faceUp = true,
    Duration duration = const Duration(milliseconds: 420),
    double arcLift = 140,
  }) {
    final completer = Completer<void>();
    final origin = _centerGlobal(originKey);
    final target = _centerGlobal(targetKey);

    if (origin == null || target == null) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!completer.isCompleted) completer.complete();
      });
      return completer.future;
    }

    final controller = AnimationController(vsync: this, duration: duration);
    final flight = _Flight(
      origin: origin,
      target: target,
      card: card,
      faceUp: faceUp,
      arcLift: arcLift,
      controller: controller,
    );

    setState(() => _flights.add(flight));

    controller.forward().then((_) {
      if (mounted) {
        setState(() => _flights.remove(flight));
        controller.dispose();
      }
      completer.complete();
    });

    return completer.future;
  }

  /// Draw pile → player zone (card back).
  Future<void> flyDrawToPlayer({
    required GlobalKey? drawPileKey,
    required GlobalKey? playerKey,
    Duration duration = const Duration(milliseconds: 320),
  }) {
    final dummy = CardModel(
      id: '_draw_flight',
      rank: Rank.two,
      suit: Suit.spades,
    );
    return flyCard(
      originKey: drawPileKey,
      targetKey: playerKey,
      card: dummy,
      faceUp: false,
      duration: duration,
      arcLift: 100,
    );
  }

  Offset? _centerGlobal(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final o = box.localToGlobal(Offset.zero);
    return Offset(o.dx + box.size.width / 2, o.dy + box.size.height / 2);
  }

  @override
  void dispose() {
    for (final f in _flights) {
      f.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_flights.isEmpty) return const SizedBox.shrink();

    const w = AppDimensions.cardWidthMedium;
    const h = AppDimensions.cardWidthMedium * 1.4;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: _flights.map((f) {
          return AnimatedBuilder(
            animation: f.controller,
            builder: (_, __) {
              final t = f.controller.value;
              final p0 = f.origin;
              final p2 = f.target;
              final midX = (p0.dx + p2.dx) / 2;
              final midY = (p0.dy + p2.dy) / 2 - f.arcLift;
              final cp = Offset(midX, midY);
              final invT = 1.0 - t;
              final x = invT * invT * p0.dx +
                  2 * invT * t * cp.dx +
                  t * t * p2.dx;
              final y = invT * invT * p0.dy +
                  2 * invT * t * cp.dy +
                  t * t * p2.dy;
              final scale = 1.0 + math.sin(t * math.pi) * 0.15;
              final rot = t * 0.4 * math.pi;

              return Positioned(
                left: x - w / 2,
                top: y - h / 2,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(scale, scale, 1)
                    ..rotateZ(rot),
                  child: f.faceUp
                      ? CardWidget(card: f.card, width: w, faceUp: true)
                      : CardBackWidget(width: w),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _Flight {
  _Flight({
    required this.origin,
    required this.target,
    required this.card,
    required this.faceUp,
    required this.arcLift,
    required this.controller,
  });

  final Offset origin;
  final Offset target;
  final CardModel card;
  final bool faceUp;
  final double arcLift;
  final AnimationController controller;
}
