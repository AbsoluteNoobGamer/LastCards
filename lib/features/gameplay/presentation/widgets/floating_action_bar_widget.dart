import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/game_state.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/providers/theme_provider.dart';

class FloatingActionBarWidget extends ConsumerWidget {
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
    this.compact = false,
  });

  /// When true, uses smaller padding/fonts for landscape layout.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final accent = theme.accentPrimary;
    final accentLight = theme.accentLight;
    final accentDark = theme.accentDark;
    final surface = theme.surfacePanel;
    final textSec = theme.textSecondary;
    final bgDeep = theme.backgroundDeep;

    final bool isCw = direction == PlayDirection.clockwise;
    final String dirIcon = isCw ? '↻' : '↺';
    final String dirText = isCw ? 'Clockwise' : 'Counter-Clockwise';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use shorter dimension: in landscape, maxWidth is the long axis.
        final isMobile = math.min(constraints.maxWidth, constraints.maxHeight) <
            AppDimensions.breakpointMobile;
        final useCompact = compact || (isMobile && constraints.maxWidth > constraints.maxHeight);

        Widget endTurnButton() {
          return AnimatedOpacity(
            opacity: canEndTurn ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 250),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: canEndTurn
                      ? [accentLight, accentDark]
                      : [surface, surface],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusButton),
                boxShadow: canEndTurn
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: canEndTurn && onEndTurn != null
                    ? () {
                        game_audio.AudioService.instance
                            .playSound(GameSound.endTurnButton);
                        onEndTurn!();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: canEndTurn ? bgDeep : textSec,
                  disabledForegroundColor: textSec,
                  padding: EdgeInsets.symmetric(
                    horizontal: useCompact ? 8 : (isMobile ? 12 : 20),
                    vertical: useCompact ? 6 : (isMobile ? 10 : 12),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'End Turn',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: useCompact ? 11 : (isMobile ? 13 : 16),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: useCompact ? 8 : (isMobile ? AppDimensions.sm : AppDimensions.md),
            vertical: useCompact ? 4 : (isMobile ? 6 : 8),
          ),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(useCompact ? 20 : 32),
            border: Border.all(
              color: accentDark.withValues(alpha: 0.6),
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
                width: useCompact ? 64 : (isMobile ? 90 : 120),
                child: Row(
                  children: [
                    Icon(
                      isCw ? Icons.rotate_right : Icons.rotate_left,
                      color: accent,
                      size: useCompact ? 12 : (isMobile ? 14 : 16),
                    ),
                    SizedBox(width: useCompact ? 2 : 4),
                    Expanded(
                      child: Text(
                        '$dirIcon $dirText',
                        style: TextStyle(
                          color: textSec.withValues(alpha: 0.9),
                          fontSize: useCompact ? 9 : (isMobile ? 10 : 12),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                height: useCompact ? 18 : 24,
                color: accentDark.withValues(alpha: 0.3),
                margin: EdgeInsets.symmetric(horizontal: useCompact ? 4 : 8),
              ),

              // Center: Whose turn
              Expanded(
                child: Text(
                  activePlayerName == 'You'
                      ? 'Your Turn'
                      : "$activePlayerName's Turn",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontSize: useCompact ? 12 : (isMobile ? 14 : 16),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              Container(
                width: 1,
                height: useCompact ? 18 : 24,
                color: accentDark.withValues(alpha: 0.3),
                margin: EdgeInsets.symmetric(horizontal: useCompact ? 4 : 8),
              ),

              // Right: End Turn Button
              SizedBox(
                width: useCompact ? 64 : (isMobile ? 90 : 120),
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
