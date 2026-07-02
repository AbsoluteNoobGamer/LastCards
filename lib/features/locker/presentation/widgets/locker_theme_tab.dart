import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_themes.dart';

/// "Table theme" tab — the app-wide visual theme (not level-gated; every
/// theme is unlocked from the start, this is a preference, not a cosmetic
/// grind).
class LockerThemeTab extends ConsumerWidget {
  const LockerThemeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: kAppThemes.length,
      itemBuilder: (context, index) {
        final theme = kAppThemes[index];
        final isActive = themeState.activeIndex == index;
        final swatch = theme.swatchPreview;
        final accent = theme.accentPrimary;

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            notifier.setTheme(index);
          },
          child: Container(
            decoration: BoxDecoration(
              color: swatch.isNotEmpty ? swatch.first : colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? accent : accent.withValues(alpha: 0.25),
                width: isActive ? 2.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                  child: Text(
                    theme.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
                if (isActive)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, size: 14, color: swatch.first),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
