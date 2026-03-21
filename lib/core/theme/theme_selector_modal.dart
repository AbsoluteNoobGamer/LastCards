import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/theme_provider.dart';
import 'app_themes.dart';

class ThemeSelectorModal extends ConsumerWidget {
  const ThemeSelectorModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    final media = MediaQuery.of(context);
    final isMobile = math.min(media.size.width, media.size.height) < 600;

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.88 : 0.80,
      minChildSize: isMobile ? 0.55 : 0.45,
      maxChildSize: isMobile ? 0.96 : 0.90,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.4),
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Handle ───────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Title ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Theme',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: isMobile ? 22 : 26,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a visual style — no gameplay changes.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Grid ─────────────────────────────────────────────────────
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 28,
                    0,
                    isMobile ? 16 : 28,
                    24 + media.viewInsets.bottom,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobile ? 2 : 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  itemCount: kAppThemes.length,
                  itemBuilder: (context, index) {
                    final theme = kAppThemes[index];
                    final isActive = themeState.activeIndex == index;

                    return _ThemeSwatch(
                      theme: theme,
                      isActive: isActive,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setTheme(index);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Swatch tile ──────────────────────────────────────────────────────────────

class _ThemeSwatch extends StatefulWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.isActive,
    required this.onTap,
  });

  final dynamic theme; // AppThemeData
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_ThemeSwatch> createState() => _ThemeSwatchState();
}

class _ThemeSwatchState extends State<_ThemeSwatch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.theme.swatchPreview as List<Color>;
    final accent = widget.theme.accentPrimary as Color;
    final name = widget.theme.name as String;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors.length >= 2
                  ? [colors[0], colors[1]]
                  : [colors[0], colors[0]],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isActive
                  ? accent
                  : accent.withValues(alpha: 0.25),
              width: widget.isActive ? 2.5 : 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            children: [
              // ── Accent stripe ─────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                  ),
                ),
              ),

              // ── Name label ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                    letterSpacing: 0.3,
                    shadows: const [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Active check ─────────────────────────────────────────
              if (widget.isActive)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: colors[0],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
