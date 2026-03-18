import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/engine/game_turn_timer.dart';

class TurnTimerBar extends StatefulWidget {
  final Stream<int>? timeRemainingStream;
  final bool isVisible;

  /// When true, uses shorter bar height for landscape layout.
  final bool compact;

  const TurnTimerBar({
    super.key,
    required this.timeRemainingStream,
    this.isVisible = false,
    this.compact = false,
  });

  @override
  State<TurnTimerBar> createState() => _TurnTimerBarState();
}

class _TurnTimerBarState extends State<TurnTimerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _urgentCtrl;

  @override
  void initState() {
    super.initState();
    _urgentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _urgentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.timeRemainingStream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<int>(
      stream: widget.timeRemainingStream,
      initialData: GameTurnTimer.defaultDurationSeconds,
      builder: (context, snapshot) {
        final seconds = snapshot.data ?? GameTurnTimer.defaultDurationSeconds;
        final progress = seconds / GameTurnTimer.defaultDurationSeconds;

        if (seconds <= 10) {
          if (!_urgentCtrl.isAnimating) _urgentCtrl.repeat(reverse: true);
        } else {
          _urgentCtrl.stop();
          _urgentCtrl.value = 0;
        }

        Color barColor = AppColors.goldPrimary;
        if (seconds <= 10) {
          barColor = AppColors.redSoft;
        } else if (seconds <= 20) {
          barColor = Colors.amber;
        }

        final barHeight = widget.compact ? 6.0 : 10.0;
        final radius = widget.compact ? 3.0 : 5.0;
        final pulse =
            seconds <= 10 ? 1.0 + 0.08 * math.sin(_urgentCtrl.value * 2 * math.pi) : 1.0;

        return AnimatedBuilder(
          animation: _urgentCtrl,
          builder: (context, _) {
            return Transform.scale(
              scale: seconds <= 10 ? pulse : 1.0,
              alignment: Alignment.center,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: progress, end: progress),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, _) {
                  return Container(
                    height: barHeight,
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(radius),
                          boxShadow: seconds <= 10
                              ? [
                                  BoxShadow(
                                    color: barColor.withAlpha(160),
                                    blurRadius: 10 + 6 * _urgentCtrl.value,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
