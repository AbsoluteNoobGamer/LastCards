import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../rules/presentation/screens/rules_screen.dart';
import '../widgets/tutorial_slide.dart';
import '../widgets/tutorial_slides.dart';

/// A short, skippable, animated slideshow demonstrating the special cards
/// and basic turn structure — shown once on first launch, and reachable
/// again any time from the Rules screen.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _finishToRules() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RulesScreen()),
    );
  }

  TextStyle _headingStyle(AppThemeData theme, {required double size}) {
    return theme.headingFontFamily == 'cinzel'
        ? GoogleFonts.cinzel(
            fontSize: size,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: theme.accentPrimary,
          )
        : GoogleFonts.playfairDisplay(
            fontSize: size,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: theme.accentPrimary,
          );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final slides = tutorialSlides;
    final isLast = _index == slides.length - 1;
    final isFirst = _index == 0;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundMid,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: theme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
        title: Text('HOW TO PLAY', style: _headingStyle(theme, size: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Skip',
              style: TextStyle(color: theme.accentPrimary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressDots(count: slides.length, index: _index, theme: theme),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _TutorialSlideView(slide: slides[i], theme: theme),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: isLast
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _finishToRules,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.accentPrimary,
                              side: BorderSide(color: theme.accentPrimary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Read the full rules'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accentPrimary,
                              foregroundColor: theme.backgroundDeep,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Start playing'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isFirst ? null : () => _goTo(_index - 1),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.textPrimary,
                              side: BorderSide(color: theme.accentPrimary.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _goTo(_index + 1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accentPrimary,
                              foregroundColor: theme.backgroundDeep,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Next'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialSlideView extends StatelessWidget {
  const _TutorialSlideView({required this.slide, required this.theme});

  final TutorialSlide slide;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),
          Builder(builder: slide.demoBuilder),
          const SizedBox(height: 28),
          for (final line in slide.captionLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: theme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.index, required this.theme});

  final int count;
  final int index;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index
                    ? theme.accentPrimary
                    : theme.accentPrimary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}
