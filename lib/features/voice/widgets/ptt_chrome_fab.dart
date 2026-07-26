import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../gameplay/presentation/widgets/arena_chrome_fab.dart';
import '../voice_providers.dart';

/// Hold-to-talk control matching [ArenaChromeFab] chrome.
class PttChromeFab extends ConsumerWidget {
  const PttChromeFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final voice = ref.watch(voiceRoomControllerProvider);
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        if (!voice.shouldShowPtt) return const SizedBox.shrink();
        final transmitting = voice.ptt.isTransmitting;
        final remaining = voice.ptt.secondsRemaining;
        final border = transmitting ? theme.secondaryAccent : theme.accentPrimary;
        final enabled = voice.isConnected && voice.canPublish;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tooltip(
            message: !voice.isConnected
                ? (voice.isConnecting
                    ? 'Connecting voice…'
                    : 'Voice unavailable')
                : !voice.canPublish
                    ? 'You are muted'
                    : transmitting
                        ? 'Release to stop ($remaining s)'
                        : 'Hold to talk (max 10s)',
            child: Listener(
              onPointerDown:
                  enabled ? (_) => voice.onPttPointerDown() : null,
              onPointerUp: (_) => voice.onPttPointerUp(),
              onPointerCancel: (_) => voice.onPttPointerUp(),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: Ink(
                      width: ArenaChromeFab.size,
                      height: ArenaChromeFab.size,
                      decoration: BoxDecoration(
                        color: theme.surfacePanel.withValues(
                          alpha: enabled ? 0.95 : 0.55,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusButton),
                        border: Border.all(color: border, width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: border.withValues(alpha: 0.45),
                            blurRadius: 14,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        transmitting
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: theme.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                  if (transmitting)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.secondaryAccent,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: theme.surfaceDark, width: 1),
                        ),
                        child: Text(
                          '$remaining',
                          style: TextStyle(
                            color: theme.backgroundDeep,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
