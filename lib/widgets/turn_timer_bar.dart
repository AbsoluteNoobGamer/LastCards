import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/engine/game_turn_timer.dart';

class TurnTimerBar extends StatelessWidget {
  final Stream<int>? timeRemainingStream;
  final bool isVisible;

  const TurnTimerBar({
    super.key,
    required this.timeRemainingStream,
    this.isVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || timeRemainingStream == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: timeRemainingStream,
      initialData: GameTurnTimer.defaultDurationSeconds,
      builder: (context, snapshot) {
        final seconds = snapshot.data ?? GameTurnTimer.defaultDurationSeconds;
        final progress = seconds / GameTurnTimer.defaultDurationSeconds;
        
        Color barColor = AppColors.goldPrimary;
        if (seconds <= 10) {
          barColor = AppColors.redSoft;
        } else if (seconds <= 20) {
          barColor = Colors.amber;
        }

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: progress, end: progress),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, _) {
            return Container(
              height: 10,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: seconds <= 10 ? [
                      BoxShadow(
                        color: barColor.withAlpha(128),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ] : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
