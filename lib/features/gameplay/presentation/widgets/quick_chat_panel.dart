import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../shared/constants/quick_chat_messages.dart';

export '../../../../shared/constants/quick_chat_messages.dart' show kQuickMessages;

/// Compact panel listing preset quick chat messages.
/// Styled to match the game log box — same font, background, and accent border.
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kQuickMessages.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ChatOption(
                message: kQuickMessages[i],
                theme: theme,
                onTap: () => onMessageSelected(i),
              ),
            ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _ChatOption extends StatelessWidget {
  const _ChatOption({
    required this.message,
    required this.theme,
    required this.onTap,
  });

  final String message;
  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.accentDark.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
