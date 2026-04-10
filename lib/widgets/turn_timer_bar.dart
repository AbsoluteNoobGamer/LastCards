import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/shadow_blur.dart';
import '../shared/engine/game_turn_timer.dart';

class TurnTimerBar extends StatefulWidget {
  final Stream<int>? timeRemainingStream;
  final bool isVisible;

  /// Denominator for progress (30 hardcore / 60 default).
  final int totalDurationSeconds;

  /// When true, uses shorter bar height for landscape layout.
  final bool compact;

  const TurnTimerBar({
    super.key,
    required this.timeRemainingStream,
    this.totalDurationSeconds = GameTurnTimer.defaultDurationSeconds,
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
      initialData: widget.totalDurationSeconds > 0
          ? widget.totalDurationSeconds
          : GameTurnTimer.defaultDurationSeconds,
      builder: (context, snapshot) {
        final total = widget.totalDurationSeconds > 0
            ? widget.totalDurationSeconds
            : GameTurnTimer.defaultDurationSeconds;
        final seconds = snapshot.data ?? total;
        final progress = (seconds / total).clamp(0.0, 1.0);

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

        return AnimatedBuilder(
          animation: _urgentCtrl,
          builder: (context, _) {
            final pulse = seconds <= 10
                ? 1.0 + 0.08 * math.sin(_urgentCtrl.value * 2 * math.pi)
                : 1.0;
            return Transform.scale(
              scale: pulse,
              alignment: Alignment.center,
              child: _AnimatedTimerProgressFill(
                targetWidthFactor: progress,
                barHeight: barHeight,
                radius: radius,
                barColor: barColor,
                urgentGlow: seconds <= 10,
                urgentCtrlValue: _urgentCtrl.value.clamp(0.0, 1.0),
              ),
            );
          },
        );
      },
    );
  }
}

/// Smoothly animates the fill when [targetWidthFactor] changes (stream ticks).
class _AnimatedTimerProgressFill extends StatefulWidget {
  const _AnimatedTimerProgressFill({
    required this.targetWidthFactor,
    required this.barHeight,
    required this.radius,
    required this.barColor,
    required this.urgentGlow,
    required this.urgentCtrlValue,
  });

  final double targetWidthFactor;
  final double barHeight;
  final double radius;
  final Color barColor;
  final bool urgentGlow;
  final double urgentCtrlValue;

  @override
  State<_AnimatedTimerProgressFill> createState() =>
      _AnimatedTimerProgressFillState();
}

class _AnimatedTimerProgressFillState extends State<_AnimatedTimerProgressFill>
    with SingleTickerProviderStateMixin {
  late AnimationController _fillCtrl;

  @override
  void initState() {
    super.initState();
    _fillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fillCtrl.value = widget.targetWidthFactor;
  }

  @override
  void didUpdateWidget(_AnimatedTimerProgressFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetWidthFactor != oldWidget.targetWidthFactor) {
      _fillCtrl.animateTo(
        widget.targetWidthFactor,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fillCtrl,
      builder: (context, _) {
        final value = _fillCtrl.value.clamp(0.0, 1.0);
        return Container(
          height: widget.barHeight,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: widget.barColor,
                borderRadius: BorderRadius.circular(widget.radius),
                boxShadow: widget.urgentGlow
                    ? [
                        BoxShadow(
                          color: widget.barColor.withAlpha(160),
                          blurRadius: nonNegativeShadowBlur(
                            10 + 6 * widget.urgentCtrlValue,
                          ),
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
