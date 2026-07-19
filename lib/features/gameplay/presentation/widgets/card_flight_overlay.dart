import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/utils/shadow_blur.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../domain/entities/card.dart';
import 'card_back_widget.dart';
import 'card_widget.dart';

/// Full-screen overlay that animates a card along a quadratic Bézier arc
/// between two widgets identified by [GlobalKey]s (hand → discard or similar).
class CardFlightOverlay extends ConsumerStatefulWidget {
  const CardFlightOverlay({super.key, this.scale = 1.0});

  /// Tablet/desktop scale multiplier (1.0 on phones) — keeps the flying
  /// card sized to match the real (already-scaled) hand/pile it travels
  /// between, since its screen position already tracks their real
  /// GlobalKey geometry.
  final double scale;

  @override
  CardFlightOverlayState createState() => CardFlightOverlayState();
}

class CardFlightOverlayState extends ConsumerState<CardFlightOverlay>
    with TickerProviderStateMixin {
  final List<_Flight> _flights = [];

  /// Animates one card from [originKey] centre to [targetKey] centre.
  /// [faceUp] false uses card back (e.g. draw flight).
  Future<void> flyCard({
    required GlobalKey? originKey,
    required GlobalKey? targetKey,
    required CardModel card,
    bool faceUp = true,
    Duration duration = const Duration(milliseconds: 420),
    double arcLift = 140,

    /// Winning / go-out play: taller arc, glow, and wobble.
    bool lastCardFromHand = false,
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

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final effectiveDuration = reduceMotion
        ? Duration.zero
        : (lastCardFromHand ? const Duration(milliseconds: 680) : duration);
    final effectiveArc = lastCardFromHand ? math.max(arcLift, 220.0) : arcLift;

    final controller =
        AnimationController(vsync: this, duration: effectiveDuration);
    final flight = _Flight(
      origin: origin,
      target: target,
      card: card,
      faceUp: faceUp,
      arcLift: effectiveArc,
      lastCardFromHand: lastCardFromHand,
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
    final center = Offset(o.dx + box.size.width / 2, o.dy + box.size.height / 2);
    // A degenerate (zero-height/width) ancestor upstream can make an inner
    // FittedBox's scale resolve to NaN, which poisons this offset. Treat that
    // the same as "key not resolvable yet" — flyCard already skips the
    // animation gracefully rather than feeding NaN into Positioned/painting.
    if (!center.dx.isFinite || !center.dy.isFinite) return null;
    return center;
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

    final theme = ref.watch(themeProvider).theme;
    final w = AppDimensions.cardWidthMedium * widget.scale;
    final h = AppDimensions.cardWidthMedium * 1.4 * widget.scale;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: _flights.map((f) {
          return AnimatedBuilder(
            animation: f.controller,
            builder: (_, __) {
              final tRaw = f.controller.value;
              // Ease travel so the arc decelerates into the discard (snappier feel).
              final t = Curves.easeOutCubic.transform(tRaw);
              final p0 = f.origin;
              final p2 = f.target;
              final midX = (p0.dx + p2.dx) / 2;
              final midY = (p0.dy + p2.dy) / 2 - f.arcLift;
              final cp = Offset(midX, midY);
              final invT = 1.0 - t;
              final x =
                  invT * invT * p0.dx + 2 * invT * t * cp.dx + t * t * p2.dx;
              final y =
                  invT * invT * p0.dy + 2 * invT * t * cp.dy + t * t * p2.dy;
              final baseScale = 1.0 +
                  math.sin(t * math.pi) * (f.lastCardFromHand ? 0.2 : 0.12);
              var scale = f.lastCardFromHand
                  ? baseScale * (1.0 + 0.06 * math.sin(t * math.pi * 3))
                  : baseScale;
              // Subtle landing “bounce” on normal plays (last-card uses its own wobble).
              if (!f.lastCardFromHand && tRaw > 0.86) {
                final u = (tRaw - 0.86) / 0.14;
                scale *= 1.0 + math.sin(u * math.pi) * 0.065;
              }

              var rotation = 0.0;
              if (!f.lastCardFromHand) {
                final peakRotation = f.faceUp ? 0.18 : 0.10;
                rotation = math.sin(t * math.pi) * peakRotation;
                if (tRaw >= 0.95) {
                  final settleU = (tRaw - 0.95) / 0.05;
                  rotation += -0.03 * (1.0 - settleU);
                }
              }

              Widget child = f.faceUp
                  ? CardWidget(
                      card: f.card,
                      width: w,
                      faceUp: true,
                      animateFlip: false,
                    )
                  : CardBackWidget(width: w);

              if (!f.lastCardFromHand) {
                final shadowBlur = 8.0 + 16.0 * math.sin(t * math.pi);
                final shadowOffset = 2.0 + 6.0 * math.sin(t * math.pi);
                child = Transform.rotate(
                  angle: rotation,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: shadowBlur,
                          offset: Offset(0, shadowOffset),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              }

              if (f.lastCardFromHand) {
                final pulse = (math.sin(t * math.pi * 2) + 1) / 2;
                final glowAlpha = 0.25 + 0.55 * pulse;
                child = Transform.rotate(
                  angle: 0.1 * math.sin(t * math.pi * 2.5),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.accentPrimary
                              .withValues(alpha: glowAlpha),
                          blurRadius: nonNegativeShadowBlur(32 + 28 * t),
                          spreadRadius: 2 + 8 * pulse,
                        ),
                        BoxShadow(
                          color: theme.accentLight
                              .withValues(alpha: 0.15 + 0.35 * pulse),
                          blurRadius: nonNegativeShadowBlur(
                            48 + 24 * math.sin(t * math.pi),
                          ),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              }

              return Positioned(
                left: x - w / 2,
                top: y - h / 2,
                // Isolates this widget's compositing layer (Transform + the
                // shadow/glow decorations above both force their own layer)
                // from whatever else the shared render tree retains — without
                // this, a stale layer from an unrelated widget elsewhere can
                // trip Flutter's internal 'debugOldOffset == updatedLayer.offset'
                // consistency assertion as this repositions every frame.
                child: RepaintBoundary(
                  child: Transform.scale(scale: scale, child: child),
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
    required this.lastCardFromHand,
    required this.controller,
  });

  final Offset origin;
  final Offset target;
  final CardModel card;
  final bool faceUp;
  final double arcLift;
  final bool lastCardFromHand;
  final AnimationController controller;
}
