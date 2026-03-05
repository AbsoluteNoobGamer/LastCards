import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../features/gameplay/presentation/screens/table_screen.dart';
import '../providers/single_player_session_provider.dart';

/// Full-screen loading screen shown between player count selection and the game.
///
/// Displays rotating flavour text and a pulsing animation while "loading",
/// then automatically navigates to [TableScreen] after [_kLoadDuration].
class GameLoadingScreen extends ConsumerStatefulWidget {
  const GameLoadingScreen({super.key});

  @override
  ConsumerState<GameLoadingScreen> createState() => _GameLoadingScreenState();
}

class _GameLoadingScreenState extends ConsumerState<GameLoadingScreen>
    with TickerProviderStateMixin {
  static const _kLoadDuration = Duration(milliseconds: 3000);
  static const _kFlavourInterval = Duration(milliseconds: 700);

  static const _flavourTexts = [
    'Shuffling the deck...',
    'Dealing your hand...',
    'Opponents are ready...',
    'Play it all. Leave nothing.',
  ];

  late AnimationController _rotateController;
  late AnimationController _pulseController;

  int _flavourIndex = 0;
  Timer? _flavourTimer;
  Timer? _launchTimer;

  @override
  void initState() {
    super.initState();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Cycle flavour text
    _flavourTimer =
        Timer.periodic(_kFlavourInterval, (_) {
      if (!mounted) return;
      setState(() {
        _flavourIndex = (_flavourIndex + 1) % _flavourTexts.length;
      });
    });

    // Auto-navigate to game
    _launchTimer = Timer(_kLoadDuration, _launchGame);
  }

  void _launchGame() {
    if (!mounted) return;
    final session = ref.read(singlePlayerSessionProvider);
    final playerCount = session.playerCount ?? 2;
    final difficulty = session.difficulty;
    ref.read(singlePlayerSessionProvider.notifier).reset();

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TableScreen(
          totalPlayers: playerCount,
          aiDifficulty: difficulty,
        ),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    _flavourTimer?.cancel();
    _launchTimer?.cancel();
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(singlePlayerSessionProvider);
    final difficulty = session.difficulty;
    final playerCount = session.playerCount ?? 2;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Subtle radial glow
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      theme.accentPrimary.withValues(alpha: 0.05),
                      theme.backgroundDeep,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: SizedBox.expand(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 56),

                    // ── DeckDrop title ──────────────────────────────────
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [theme.accentLight, theme.accentPrimary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        'DeckDrop',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cinzel(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Info badge: difficulty · player count ─────────
                    if (difficulty != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: theme.accentPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                theme.accentPrimary.withValues(alpha: 0.30),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              difficulty.emoji,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${difficulty.displayName}  ·  $playerCount Players',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.accentPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const Spacer(flex: 2),

                    // ── Animated spinner ──────────────────────────────
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_rotateController, _pulseController]),
                      builder: (context, child) {
                        final pulse = Tween<double>(begin: 0.88, end: 1.0)
                            .evaluate(CurvedAnimation(
                                parent: _pulseController,
                                curve: Curves.easeInOut));
                        return Transform.scale(
                          scale: pulse,
                          child: Transform.rotate(
                            angle: _rotateController.value * 6.2832,
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: CustomPaint(
                          painter: _RingPainter(
                            color: theme.accentPrimary,
                            accentLight: theme.accentLight,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Rotating flavour text ─────────────────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: Text(
                        _flavourTexts[_flavourIndex],
                        key: ValueKey(_flavourIndex),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.textSecondary,
                          letterSpacing: 0.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),
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

// ── Ring Painter ──────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.accentLight});

  final Color color;
  final Color accentLight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Background ring (dimmed)
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Active arc (gradient approximated via shader)
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [accentLight.withValues(alpha: 0.0), accentLight, color],
        startAngle: 0.0,
        endAngle: 5.0,
      ).createShader(rect)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 5.0, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accentLight != accentLight;
}
