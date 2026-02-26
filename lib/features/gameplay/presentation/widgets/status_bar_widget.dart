import 'package:flutter/material.dart';
import '../../domain/entities/game_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';

class StatusBarWidget extends StatefulWidget {
  final String activePlayerName;
  final PlayDirection direction;
  final List<String> upcomingPlayerNames;
  final bool canEndTurn;
  final VoidCallback? onEndTurn;

  const StatusBarWidget({
    super.key,
    required this.activePlayerName,
    required this.direction,
    required this.upcomingPlayerNames,
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



    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppDimensions.breakpointMobile;

        Widget endTurnButton() {
          return AnimatedOpacity(
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
                boxShadow: widget.canEndTurn
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
                onPressed: widget.canEndTurn ? widget.onEndTurn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: widget.canEndTurn
                      ? AppColors.feltDeep
                      : AppColors.textSecondary,
                  disabledForegroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 10 : 12,
                  ),
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
          constraints: BoxConstraints(
            minHeight: isMobile ? 84 : 70,
            maxHeight: isMobile ? 132 : 100,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? AppDimensions.md : AppDimensions.lg,
            vertical: AppDimensions.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfacePanel.withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: AppColors.goldDark.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
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
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('👑 ', style: TextStyle(fontSize: 18)),
                          Expanded(
                            child: Text(
                              "${widget.activePlayerName}'s Turn",
                              style: const TextStyle(
                                color: AppColors.goldPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$dirIcon $dirText$orderPreview',
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [

                          endTurnButton(),
                        ],
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                const Text('👑 ',
                                    style: TextStyle(fontSize: 22)),
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
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.9),
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [


                          endTurnButton(),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
