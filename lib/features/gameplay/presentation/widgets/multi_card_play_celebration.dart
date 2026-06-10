import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

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

/// Full-screen gold pulse when a player stacks many cards in one turn.
/// [tierIndex] is 0–2 from [multiPlayCelebrationTierIndex].
class MultiCardPlayCelebrationOverlay extends StatefulWidget {
  const MultiCardPlayCelebrationOverlay({
    super.key,
    required this.trigger,
    required this.tierIndex,
  });

  final int trigger;
  final int tierIndex;

  @override
  State<MultiCardPlayCelebrationOverlay> createState() =>
      _MultiCardPlayCelebrationOverlayState();
}

class _MultiCardPlayCelebrationOverlayState
    extends State<MultiCardPlayCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _tierDurations = [
    Duration(milliseconds: 780),
    Duration(milliseconds: 1020),
    Duration(milliseconds: 1320),
  ];

  static const _tierMaxOpacity = [0.20, 0.28, 0.38];

  static const _tierColors = [
    AppColors.goldPrimary,
    AppColors.goldLight,
    Color(0xFFFFD54F), // amber accent for largest stacks
  ];

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
    final fi = 0.28;
    if (t <= fi) return (t / fi).clamp(0.0, 1.0);
    final u = (t - fi) / (1.0 - fi);
    return (1.0 - u).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    final tier = widget.tierIndex.clamp(0, 2);
    final color = _tierColors[tier];
    final maxOp = _tierMaxOpacity[tier];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final s = _strength(_c.value);
        if (s <= 0.001) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RadialEdgePulsePainter(
                color: color,
                opacity: s * maxOp,
              ),
              size: Size.infinite,
            ),
            if (tier >= 2)
              CustomPaint(
                painter: _CenterGlowPulsePainter(
                  color: AppColors.goldLight,
                  opacity: s * maxOp * 0.45,
                ),
                size: Size.infinite,
              ),
          ],
        );
      },
    );
  }
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
