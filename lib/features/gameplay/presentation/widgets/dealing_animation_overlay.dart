import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import 'card_back_widget.dart';

class DealingAnimationOverlay extends StatefulWidget {
  const DealingAnimationOverlay({
    super.key,
    required this.drawPileKey,
    required this.playerKeys,
  });

  /// The global key attached to the draw pile to act as origin.
  final GlobalKey drawPileKey;

  /// A map of player IDs to their respective player zone keys for destinations.
  final Map<String, GlobalKey> playerKeys;

  @override
  DealingAnimationOverlayState createState() => DealingAnimationOverlayState();
}

class DealingAnimationOverlayState extends State<DealingAnimationOverlay>
    with TickerProviderStateMixin {
  
  // A queued list of currently animating flying cards
  final List<_FlyingCard> _flyingCards = [];

  /// Imperatively called by the parent screen to launch a card.
  /// Returns a Future that completes when the card finishes its flight.
  Future<void> animateCardDeal(String targetPlayerId) {
    // 1. Calculate positions
    final originBox = widget.drawPileKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox = widget.playerKeys[targetPlayerId]?.currentContext?.findRenderObject() as RenderBox?;

    if (originBox == null || targetBox == null) {
      // If we can't find layout rects (common in some widget tests before settle)
      // gracefully simulate the flight time without rendering.
      return Future.delayed(const Duration(milliseconds: 150));
    }

    final originPos = originBox.localToGlobal(
      Offset(originBox.size.width / 2, originBox.size.height / 2)
    );
    final targetPos = targetBox.localToGlobal(
      Offset(targetBox.size.width / 2, targetBox.size.height / 2)
    );

    // 2. Setup the animation
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    final completer = Completer<void>();
    
    final flyingCard = _FlyingCard(
      origin: originPos,
      target: targetPos,
      controller: controller,
    );

    setState(() {
      _flyingCards.add(flyingCard);
    });

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _flyingCards.remove(flyingCard);
        });
        controller.dispose();
      }
      completer.complete();
    });

    return completer.future;
  }

  @override
  void dispose() {
    for (var card in _flyingCards) {
      card.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_flyingCards.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        children: _flyingCards.map((card) {
          return AnimatedBuilder(
            animation: card.controller,
            builder: (context, child) {
              final t = card.controller.value;

              // Quadratic Bezier Curve:
              // P1 (control point) biases the curve into an arc. We shift it "up" visually.
              final p0 = card.origin;
              final p2 = card.target;
              
              // We want the arc to swing outward slightly based on distance.
              final midX = (p0.dx + p2.dx) / 2;
              final midY = (p0.dy + p2.dy) / 2;
              final controlPoint = Offset(midX, midY - 150); 
              
              final invT = 1.0 - t;
              final currentX = invT * invT * p0.dx + 2 * invT * t * controlPoint.dx + t * t * p2.dx;
              final currentY = invT * invT * p0.dy + 2 * invT * t * controlPoint.dy + t * t * p2.dy;

              // Scale animation: starts at 1.0, peaks at 1.4 midway, returns to 1.0
              final scale = 1.0 + (math.sin(t * math.pi) * 0.4);

              // Rotation animation: spins a bit during flight
              final rotation = t * math.pi;

              const cardW = AppDimensions.cardWidthMedium;
              const cardH = cardW * 1.4; // approximate standard height

              return Positioned(
                left: currentX - (cardW / 2),
                top: currentY - (cardH / 2),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(scale, scale, 1.0)
                    ..rotateZ(rotation),
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                           // The shadow drops further away and gets softer at the peak of the arc
                           color: Colors.black.withValues(alpha: 0.5 * (1 - (math.sin(t * math.pi) * 0.5))),
                           blurRadius: 10 + (20 * math.sin(t * math.pi)),
                           offset: Offset(0, 5 + (15 * math.sin(t * math.pi))),
                        )
                      ]
                    ),
                    child: const CardBackWidget(width: cardW),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _FlyingCard {
  _FlyingCard({
    required this.origin,
    required this.target,
    required this.controller,
  });

  final Offset origin;
  final Offset target;
  final AnimationController controller;
}
