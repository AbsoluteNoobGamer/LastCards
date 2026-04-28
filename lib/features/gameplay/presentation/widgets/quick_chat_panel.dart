import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../shared/constants/quick_chat_messages.dart';

export '../../../../shared/constants/quick_chat_messages.dart' show kQuickMessages;

/// Emoji reaction picker — same presets as server ([kQuickMessages]), CR-style grid.
class QuickChatPanel extends ConsumerWidget {
  const QuickChatPanel({
    required this.onMessageSelected,
    super.key,
  });

  final void Function(int messageIndex) onMessageSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < kQuickMessages.length; i++)
              _EmojiOption(
                emoji: kQuickMessages[i],
                theme: theme.accentDark,
                onTap: () => onMessageSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmojiOption extends StatelessWidget {
  const _EmojiOption({
    required this.emoji,
    required this.theme,
    required this.onTap,
  });

  final String emoji;
  final Color theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.42),
            border: Border.all(
              color: theme.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 26, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}
