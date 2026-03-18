import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/entities/game_state.dart';
import '../../../../core/theme/app_colors.dart';

class TurnIndicatorOverlay extends StatelessWidget {
  final PlayDirection direction;

  /// Where the “direction reversed” banner sits (below central draw/discard).
  final Alignment bannerAlignment;

  const TurnIndicatorOverlay({
    super.key,
    required this.direction,
    this.bannerAlignment = const Alignment(0, 0.20),
  });

  @override
  Widget build(BuildContext context) {
    final bool isCw = direction == PlayDirection.clockwise;
    final String symbol = isCw ? '↻' : '↺';

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: bannerAlignment,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(direction),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(seconds: 1),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                if (val >= 1.0) {
                  return const SizedBox.shrink();
                }
                final opacity = (1.0 - val).clamp(0.0, 1.0);
                final offsetX =
                    math.sin(val * math.pi * 4) * 10 * (1 - val);
                final scale = 1.0 + (val * 0.2);
                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(offsetX, 0),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                            color: AppColors.goldDark.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.goldPrimary, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.goldPrimary
                                    .withValues(alpha: 0.8 * opacity),
                                blurRadius: 30,
                                spreadRadius: 10,
                              )
                            ]),
                        child: Text(
                          '$symbol DIRECTION REVERSED!',
                          style: const TextStyle(
                            color: AppColors.feltDeep,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
