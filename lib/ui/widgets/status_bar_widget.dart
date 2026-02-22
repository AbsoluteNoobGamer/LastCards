import 'package:flutter/material.dart';
import '../../core/models/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';

class StatusBarWidget extends StatefulWidget {
  final String activePlayerName;
  final PlayDirection direction;
  final List<String> upcomingPlayerNames;
  final int secondsLeft;
  final bool canEndTurn;
  final VoidCallback? onEndTurn;

  const StatusBarWidget({
    super.key,
    required this.activePlayerName,
    required this.direction,
    required this.upcomingPlayerNames,
    required this.secondsLeft,
    required this.canEndTurn,
    this.onEndTurn,
  });

  @override
  State<StatusBarWidget> createState() => _StatusBarWidgetState();
}

class _StatusBarWidgetState extends State<StatusBarWidget> {
  @override
  Widget build(BuildContext context) {
    final bool isCw = widget.direction == PlayDirection.clockwise;
    final String dirIcon = isCw ? '↻' : '↺';
    final String dirText = isCw ? 'Clockwise' : 'Counter-Clockwise';
    final String orderPreview = widget.upcomingPlayerNames.isNotEmpty 
        ? ' (${widget.upcomingPlayerNames.join('→')})' 
        : '';

    final bool isTimerLow = widget.secondsLeft <= 5;

    return Container(
      // 15% screen height roughly translates to dynamic height, but fixed is safer for status bar
      constraints: const BoxConstraints(minHeight: 70, maxHeight: 90),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.sm),
      decoration: BoxDecoration(
        color: AppColors.surfacePanel.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: AppColors.goldDark.withValues(alpha: 0.6), width: 2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Player Turn
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const Text('👑 ', style: TextStyle(fontSize: 22)),
                      Expanded(
                        child: Text(
                          "${widget.activePlayerName}'s Turn",
                          style: const TextStyle(
                            color: AppColors.goldPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dirIcon $dirText$orderPreview',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Right: Timer and Button
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '00:${widget.secondsLeft.toString().padLeft(2, '0')} ⏳',
                  style: TextStyle(
                    color: isTimerLow ? AppColors.redSoft : AppColors.goldLight,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: isTimerLow ? [
                      Shadow(color: AppColors.redSoft, blurRadius: 8)
                    ] : null,
                  ),
                ),
                const SizedBox(width: AppDimensions.md),
                AnimatedOpacity(
                  opacity: widget.canEndTurn ? 1.0 : 0.5,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.canEndTurn 
                          ? [AppColors.goldLight, AppColors.goldDark]
                          : [AppColors.surfacePanel, AppColors.surfacePanel],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                      boxShadow: widget.canEndTurn ? [
                        BoxShadow(
                          color: AppColors.goldPrimary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ] : null,
                    ),
                    child: ElevatedButton(
                      onPressed: widget.canEndTurn ? widget.onEndTurn : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: widget.canEndTurn ? AppColors.feltDeep : AppColors.textSecondary,
                        disabledForegroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('End Turn', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
