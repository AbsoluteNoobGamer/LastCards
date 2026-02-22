import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'lobby_screen.dart';
import 'table_screen.dart';
import 'offline_practice_screen.dart';
import 'leaderboard_screen.dart';
import 'rules_screen.dart';
import '../widgets/settings_modal.dart';
import '../widgets/ai_selector_modal.dart';

class StackFlowStartScreen extends ConsumerStatefulWidget {
  const StackFlowStartScreen({super.key});

  @override
  ConsumerState<StackFlowStartScreen> createState() =>
      _StackFlowStartScreenState();
}

class _StackFlowStartScreenState extends ConsumerState<StackFlowStartScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    _logoController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..forward();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Casino Felt Background + Floating Cards
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return CustomPaint(
                painter:
                    ParticleStarfieldPainter(progress: _bgController.value),
              );
            },
          ),

          // 2. Main Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                return Column(
                  children: [
                    const SizedBox(height: 40),

                    // Logo Section
                    AnimatedLogo(controller: _logoController),

                    const Spacer(),

                    // Primary Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: isMobile
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PlayAiButton(),
                                const SizedBox(height: 16),
                                _PlayOnlineButton(),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PlayAiButton(),
                                const SizedBox(width: 24),
                                _PlayOnlineButton(),
                              ],
                            ),
                    ),

                    const SizedBox(height: 40),

                    // Secondary Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: isMobile
                          ? SizedBox(
                              height: 50,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _SecondaryButton(
                                      "Practice Mode",
                                      () => _showAISelector(context,
                                          isPractice: true)),
                                  const SizedBox(width: 12),
                                  _SecondaryButton(
                                      "Leaderboard",
                                      () => _pushWithTransition(
                                          context, const LeaderboardScreen())),
                                  const SizedBox(width: 12),
                                  _SecondaryButton(
                                      "Settings", () => _showSettings(context)),
                                  const SizedBox(width: 12),
                                  _SecondaryButton(
                                      "Rules",
                                      () => _pushWithTransition(
                                          context, const RulesScreen())),
                                ],
                              ),
                            )
                          : Center(
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                alignment: WrapAlignment.center,
                                children: [
                                  _SecondaryButton(
                                      "Practice Mode",
                                      () => _showAISelector(context,
                                          isPractice: true)),
                                  _SecondaryButton(
                                      "Leaderboard",
                                      () => _pushWithTransition(
                                          context, const LeaderboardScreen())),
                                  _SecondaryButton(
                                      "Settings", () => _showSettings(context)),
                                  _SecondaryButton(
                                      "Rules",
                                      () => _pushWithTransition(
                                          context, const RulesScreen())),
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 32),

                    // Footer
                    const DefaultTextStyle(
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                      child: Text(
                        "Server validated • Secure matchmaking • Instant reconnect",
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _pushWithTransition(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProviderScope(child: SettingsModal()),
    );
  }

  void _showAISelector(BuildContext context, {required bool isPractice}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AISelectorModal(
        onSelected: (totalPlayers) {
          final target = isPractice
              ? OfflinePracticeScreen(totalPlayers: totalPlayers)
              : TableScreen(
                  totalPlayers:
                      totalPlayers); // Temporarily using TableScreen for demo as well

          _pushWithTransition(context, target);
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Animated Background
// -----------------------------------------------------------------------------

class ParticleStarfieldPainter extends CustomPainter {
  final double progress;
  ParticleStarfieldPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double breath = (sin(progress * pi * 2) + 1) / 2;

    final Color darkGreen = const Color(0xFF0F2027);
    final Color darkCyan = const Color(0xFF133b3a);

    final Paint bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        size.longestSide,
        [
          Color.lerp(darkGreen, darkCyan, breath)!,
          Color.lerp(darkCyan, darkGreen, breath)!,
        ],
        [0.0, 1.0],
      );
    canvas.drawRect(rect, bgPaint);

    final Random rand = Random(42);
    final Paint particlePaint = Paint()..color = Colors.white;

    for (int i = 0; i < 150; i++) {
      final double startX = rand.nextDouble() * size.width;
      final double startY = rand.nextDouble() * size.height;
      final double speed = 0.1 + rand.nextDouble() * 0.5;
      final double sizeScale = 0.5 + rand.nextDouble() * 2.0;

      final double rawY = startY - (progress * size.height * speed);
      final double y = (rawY % size.height + size.height) % size.height;
      final double x = startX + sin(progress * pi * 2 * speed + i) * 10;

      final double opacityFunc = (sin(progress * pi * 4 * speed + i) + 1) / 2;
      particlePaint.color = Colors.cyan.withOpacity(0.1 + 0.6 * opacityFunc);

      canvas.drawCircle(Offset(x, y), sizeScale, particlePaint);
    }
  }

  @override
  bool shouldRepaint(ParticleStarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// -----------------------------------------------------------------------------
// Logo Animation
// -----------------------------------------------------------------------------

class AnimatedLogo extends StatefulWidget {
  final AnimationController controller;
  const AnimatedLogo({super.key, required this.controller});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
          parent: widget.controller,
          curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic)),
    );
    final opacityAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: widget.controller,
          curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _pulseController]),
      builder: (context, child) {
        final double pulse = _pulseController.value;

        return SlideTransition(
          position: slideAnim,
          child: Opacity(
            opacity: opacityAnim.value,
            child: ShaderMask(
              shaderCallback: (bounds) {
                return ui.Gradient.linear(
                  const Offset(0, 0),
                  Offset(0, bounds.height),
                  [
                    Colors.white,
                    Colors.white.withOpacity(0.6),
                    Colors.white,
                  ],
                  [
                    (pulse * 2 - 0.2).clamp(0.0, 1.0),
                    (pulse * 2).clamp(0.0, 1.0),
                    (pulse * 2 + 0.2).clamp(0.0, 1.0)
                  ],
                );
              },
              child: Text(
                "STACK FLOW",
                style: GoogleFonts.outfit(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 60 * 0.05,
                  shadows: [
                    Shadow(
                      color: const Color(0xFFCCFF00)
                          .withOpacity(0.4 + (pulse * 0.6)),
                      blurRadius: 15 + (pulse * 20),
                      offset: const Offset(0, 0),
                    ),
                    Shadow(
                      color: const Color(0xFFCCFF00)
                          .withOpacity(0.2 + (pulse * 0.4)),
                      blurRadius: 30 + (pulse * 30),
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Primary Buttons
// -----------------------------------------------------------------------------

class _PlayAiButton extends StatefulWidget {
  @override
  State<_PlayAiButton> createState() => _PlayAiButtonState();
}

class _PlayAiButtonState extends State<_PlayAiButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  String _emoji = "🤖";
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _startBlinking();
  }

  void _startBlinking() {
    _blinkTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted) return;
      setState(() => _emoji = "😳"); // Wink/blink
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() => _emoji = "🤖");
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PrimaryButtonBase(
      label: "Play with AI",
      icon: _emoji,
      gradient: const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      glowColor: const Color(0xFFFFD700),
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      // onTapUp intentionally removed for InkWell compatibility
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        // Find the _StackFlowStartScreenState to trigger the modal
        // A bit of a hack since _PlayAiButton is not passed a callback directly,
        // we can look up the state in the widget tree.
        final parentState =
            context.findAncestorStateOfType<_StackFlowStartScreenState>();
        if (parentState != null) {
          parentState._showAISelector(context, isPractice: false);
        } else {
          // Fallback if not found
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TableScreen()));
        }
      },
    );
  }
}

class _PlayOnlineButton extends StatefulWidget {
  @override
  State<_PlayOnlineButton> createState() => _PlayOnlineButtonState();
}

class _PlayOnlineButtonState extends State<_PlayOnlineButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleAnim =
        Tween<double>(begin: 1.0, end: 1.05).animate(_pulseController);

    return _PrimaryButtonBase(
      label: "Play Online",
      icon: "👥",
      gradient: const LinearGradient(
        colors: [Color(0xFF00E5FF), Color(0xFF007AFA)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      glowColor: const Color(0xFF00E5FF),
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      // onTapUp intentionally removed for InkWell compatibility
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
      },
      subtitle: AnimatedBuilder(
          animation: scaleAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: scaleAnim.value,
              child: const Text(
                "12/24 online",
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            );
          }),
    );
  }
}

class _PrimaryButtonBase extends StatelessWidget {
  final String label;
  final String icon;
  final Widget? subtitle;
  final Gradient gradient;
  final Color glowColor;
  final bool isHovered;
  final bool isPressed;
  final ValueChanged<bool> onHover;
  final GestureTapDownCallback onTapDown;
  // Removed onTapUp
  final GestureTapCancelCallback onTapCancel;
  final VoidCallback onTap;

  const _PrimaryButtonBase({
    required this.label,
    required this.icon,
    this.subtitle,
    required this.gradient,
    required this.glowColor,
    required this.isHovered,
    required this.isPressed,
    required this.onHover,
    required this.onTapDown,
    required this.onTapCancel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = isPressed ? 0.95 : (isHovered ? 1.10 : 1.0);
    final activeGlowColor = isHovered ? const Color(0xFF00FFFF) : glowColor;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(scale, scale),
        transformAlignment: Alignment.center,
        width: 250,
        height: 70,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: activeGlowColor.withOpacity(isHovered ? 0.8 : 0.3),
              blurRadius: isHovered ? 25 : 15,
              spreadRadius: isHovered ? 4 : 0,
              offset: const Offset(0, 4),
            ),
            // Inner border
            BoxShadow(
              color: Colors.white.withOpacity(0.3),
              blurRadius: 0,
              spreadRadius: 1,
              offset: const Offset(0, 1),
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(35),
            splashColor: const Color(0xFF00FFFF).withOpacity(0.3),
            highlightColor: Colors.transparent,
            onTapDown: onTapDown,
            onTapCancel: onTapCancel,
            onTap: () {
              onTap();
              Future.delayed(const Duration(milliseconds: 150), () {
                if (context.mounted) onTapCancel();
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          const Shadow(
                              color: Colors.black45,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ],
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle!,
                    ]
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Secondary Buttons
// -----------------------------------------------------------------------------

class _SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton(this.label, this.onTap);

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..scale(_isHovered ? 1.10 : 1.0, _isHovered ? 1.10 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isHovered
              ? const Color(0xFF00FFFF).withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: _isHovered ? const Color(0xFF00FFFF) : Colors.white60,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: const Color(0xFF00FFFF).withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
              )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(25),
            splashColor: const Color(0xFF00FFFF).withOpacity(0.3),
            highlightColor: Colors.transparent,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(
                widget.label,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _isHovered ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
