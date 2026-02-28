import 'package:flutter/material.dart';

import '../../domain/entities/game_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';

class FloatingActionBarWidget extends StatelessWidget {
  final String activePlayerName;
  final PlayDirection direction;
  final bool canEndTurn;
  final VoidCallback? onEndTurn;

  const FloatingActionBarWidget({
    super.key,
    required this.activePlayerName,
    required this.direction,
    required this.canEndTurn,
    this.onEndTurn,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCw = direction == PlayDirection.clockwise;
    final String dirIcon = isCw ? '↻' : '↺';
    final String dirText = isCw ? 'Clockwise' : 'Counter-Clockwise';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppDimensions.breakpointMobile;

        Widget endTurnButton() {
          return AnimatedOpacity(
            opacity: canEndTurn ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 250),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: canEndTurn
                      ? [AppColors.goldLight, AppColors.goldDark]
                      : [AppColors.surfacePanel, AppColors.surfacePanel],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                boxShadow: canEndTurn
                    ? [
                        BoxShadow(
                          color: AppColors.goldPrimary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: canEndTurn ? onEndTurn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor:
                      canEndTurn ? AppColors.feltDeep : AppColors.textSecondary,
                  disabledForegroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 10 : 12,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'End Turn',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isMobile ? 13 : 16,
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? AppDimensions.sm : AppDimensions.md,
            vertical: isMobile ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfacePanel.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: AppColors.goldDark.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left: Direction
              SizedBox(
                width: isMobile ? 90 : 120, // keep widths fixed so center title doesn't jitter
                child: Row(
                  children: [
                    Icon(
                      isCw ? Icons.rotate_right : Icons.rotate_left,
                      color: AppColors.goldPrimary,
                      size: isMobile ? 14 : 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$dirIcon $dirText',
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                          fontSize: isMobile ? 10 : 12,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Center: Whose turn
              Container(
                width: 1,
                height: 24,
                color: AppColors.goldDark.withValues(alpha: 0.3),
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              
              Expanded(
                child: Text(
                  activePlayerName == 'You' ? 'Your Turn' : "\${activePlayerName}'s Turn",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.goldPrimary,
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              Container(
                width: 1,
                height: 24,
                color: AppColors.goldDark.withValues(alpha: 0.3),
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),

              // Right: End Turn Button
              SizedBox(
                width: isMobile ? 90 : 120,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: endTurnButton(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
