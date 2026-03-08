import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';

class TournamentWinnerScreen extends ConsumerStatefulWidget {
  const TournamentWinnerScreen({
    required this.winnerName,
    required this.onPlayAgain,
    required this.onReturnToMenu,
    super.key,
  });

  final String winnerName;
  final void Function(BuildContext context) onPlayAgain;
  final void Function(BuildContext context) onReturnToMenu;

  @override
  ConsumerState<TournamentWinnerScreen> createState() =>
      _TournamentWinnerScreenState();
}

class _TournamentWinnerScreenState extends ConsumerState<TournamentWinnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: Stack(
          alignment: Alignment.center,
          children: [
            // Background glow
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      theme.accentPrimary.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    center: Alignment.center,
                    radius: 0.8,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: _scale,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.accentPrimary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.accentPrimary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.emoji_events_rounded,
                          color: theme.accentPrimary,
                          size: 100,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Tournament Winner',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: theme.accentPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.winnerName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: theme.textPrimary,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 64),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => widget.onPlayAgain(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accentPrimary,
                          foregroundColor: theme.backgroundDeep,
                          elevation: 8,
                          shadowColor: theme.accentPrimary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Play Again',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () => widget.onReturnToMenu(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: theme.accentDark, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          foregroundColor: theme.textPrimary,
                        ),
                        child: Text(
                          'Return to Menu',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
