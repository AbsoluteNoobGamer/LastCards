import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimum cards played **this turn** (shared engine counter) to show feedback.
const int kMultiPlayCelebrationMinCards = 3;

/// Live chip appears once the turn has stacked at least this many cards.
const int kComboLiveChipMinCards = 2;

/// Soft-gold lounge palette — matches King direction sweep, not fire/arcade.
const _kGold = Color(0xFFE8C87A);
const _kChampagne = Color(0xFFF5E6C8);
const _kGoldDeep = Color(0xFFC9A04A);

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

/// Soft-gold pulse + badge when a player stacks many cards in one turn.
/// [tierIndex] is 0–2 from [multiPlayCelebrationTierIndex].
///
/// [cardCount] drives the "×N" badge text; pass `null` to show the ambient
/// glow only (used when this overlay is reused for a non-combo beat,
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
    Duration(milliseconds: 1100),
    Duration(milliseconds: 1400),
  ];

  static const _tierMaxOpacity = [0.18, 0.26, 0.34];
  static const _tierSparkleCounts = [0, 3, 6];

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

  double _badgeScale(double t) {
    const inEnd = 0.22;
    if (t <= inEnd) {
      final u = (t / inEnd).clamp(0.0, 1.0);
      return Curves.easeOutBack.transform(u);
    }
    final u = ((t - inEnd) / (1.0 - inEnd)).clamp(0.0, 1.0);
    return 1.0 - 0.04 * math.sin(u * math.pi * 2);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    final tier = widget.tierIndex.clamp(0, 2);
    final maxOp = _tierMaxOpacity[tier];
    final sparkleCount = _tierSparkleCounts[tier];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final s = _strength(t);
        if (s <= 0.001) return const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _SoftGoldEdgePulsePainter(
                opacity: s * maxOp,
              ),
              size: Size.infinite,
            ),
            if (tier >= 1)
              CustomPaint(
                painter: _SoftGoldCenterGlowPainter(
                  opacity: s * maxOp * 0.55,
                ),
                size: Size.infinite,
              ),
            if (sparkleCount > 0)
              CustomPaint(
                painter: _SoftSparklePainter(
                  progress: t,
                  strength: s,
                  count: sparkleCount,
                  seed: widget.trigger,
                ),
                size: Size.infinite,
              ),
            if (widget.cardCount != null)
              Align(
                alignment: const Alignment(0, 0.42),
                child: Opacity(
                  opacity: s,
                  child: Transform.scale(
                    scale: _badgeScale(t),
                    child: _ComboBadge(
                      tierName: _tierNames[tier],
                      cardCount: widget.cardCount!,
                      tier: tier,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Live `×N` pill under the info band while a turn is stacking cards.
class ComboLiveChip extends StatelessWidget {
  const ComboLiveChip({
    super.key,
    required this.count,
    this.scale = 1.0,
  });

  /// Cards played this turn. Hidden when below [kComboLiveChipMinCards].
  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final visible = count >= kComboLiveChipMinCards;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedScale(
          scale: visible ? 1 : 0.85,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: visible
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: FadeTransition(opacity: anim, child: child),
                    );
                  },
                  child: _ComboLivePill(
                    key: ValueKey(count),
                    count: count,
                    scale: scale,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ComboLivePill extends StatelessWidget {
  const _ComboLivePill({
    super.key,
    required this.count,
    required this.scale,
  });

  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final hPad = 12.0 * scale;
    final vPad = 5.0 * scale;
    final fontSize = 15.0 * scale;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1408),
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(
          color: _kGold.withValues(alpha: 0.75),
          width: 1.2 * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: _kGold.withValues(alpha: 0.28),
            blurRadius: 10 * scale,
            spreadRadius: 0.5 * scale,
          ),
        ],
      ),
      child: Text(
        '×$count',
        style: TextStyle(
          color: _kChampagne,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          height: 1.1,
          shadows: [
            Shadow(
              color: _kGold.withValues(alpha: 0.55),
              blurRadius: 6 * scale,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({
    required this.tierName,
    required this.cardCount,
    required this.tier,
  });

  final String tierName;
  final int cardCount;
  final int tier;

  @override
  Widget build(BuildContext context) {
    final labelSize = 11.0 + tier * 1.5;
    final countSize = 22.0 + tier * 4.0;
    final hPad = 18.0 + tier * 4.0;
    final vPad = 10.0 + tier * 2.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: const Color(0xE61A1408),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kGold.withValues(alpha: 0.85),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: _kGold.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tierName,
            style: TextStyle(
              fontSize: labelSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: _kGold.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '×$cardCount',
            style: TextStyle(
              fontSize: countSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: _kChampagne,
              shadows: [
                Shadow(
                  color: _kGoldDeep.withValues(alpha: 0.7),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftSparklePainter extends CustomPainter {
  _SoftSparklePainter({
    required this.progress,
    required this.strength,
    required this.count,
    required this.seed,
  });

  final double progress;
  final double strength;
  final int count;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || strength <= 0 || count <= 0) return;
    const phi = 0.6180339887;
    final origin = Offset(size.width / 2, size.height * 0.55);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final seedVal = (i + 1 + seed * 0.01);
      final angle = ((seedVal * phi) % 1.0) * math.pi * 2;
      final spread = 28.0 + ((seedVal * 2.7) % 1.0) * size.shortestSide * 0.18;
      final rise = progress * (36.0 + ((seedVal * 1.9) % 1.0) * 48.0);

      final dx = origin.dx + math.cos(angle) * spread * progress;
      final dy = origin.dy + math.sin(angle) * spread * 0.35 * progress - rise;

      final flicker = 0.55 + 0.45 * math.sin(progress * math.pi * 6 + i);
      final alpha = (strength * flicker * 0.7).clamp(0.0, 1.0);
      paint.color = (i.isEven ? _kChampagne : _kGold).withValues(alpha: alpha);
      canvas.drawCircle(Offset(dx, dy), 1.2 + (i % 2) * 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoftSparklePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strength != strength;
}

class _SoftGoldEdgePulsePainter extends CustomPainter {
  _SoftGoldEdgePulsePainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [
          Colors.transparent,
          _kGold.withValues(alpha: 0),
          _kGold.withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.68, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SoftGoldEdgePulsePainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class _SoftGoldCenterGlowPainter extends CustomPainter {
  _SoftGoldCenterGlowPainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.42);
    final r = size.shortestSide * 0.48;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          _kChampagne.withValues(alpha: opacity),
          _kGold.withValues(alpha: opacity * 0.35),
          _kGold.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(rect);
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _SoftGoldCenterGlowPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
