import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';

/// High-visibility corner control for the arena table (settings / leave / chat).
class ArenaChromeFab extends ConsumerWidget {
  const ArenaChromeFab({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
    this.emphasized = false,
  });

  /// Button footprint (matches [Ink] size below).
  static const double size = 48;

  /// Horizontal clearance the local hand must leave on each side so edge
  /// cards stay tappable under the corner FAB stacks.
  static const double handClearance = size + 12;

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final String? badge;
  final bool emphasized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final border = emphasized ? theme.secondaryAccent : theme.accentPrimary;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: theme.surfacePanel.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                border: Border.all(color: border, width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: border.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: theme.textPrimary, size: 22),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: theme.secondaryAccent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.surfaceDark, width: 1),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  color: theme.backgroundDeep,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
