import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../lobby/presentation/screens/lobby_screen.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../practice/presentation/screens/offline_practice_screen.dart';
import '../../../leaderboard/presentation/screens/leaderboard_screen.dart';
import '../../../rules/presentation/screens/rules_screen.dart';
import '../../../settings/presentation/widgets/settings_modal.dart';
import '../widgets/ai_selector_modal.dart';

part 'start_screen_background.dart';
part 'start_screen_buttons.dart';

class StackFlowStartScreen extends ConsumerStatefulWidget {
  const StackFlowStartScreen({super.key});

  @override
  ConsumerState<StackFlowStartScreen> createState() =>
      _StackFlowStartScreenState();
}

class _StackFlowStartScreenState extends ConsumerState<StackFlowStartScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Image
          Image.asset(
            'assets/images/stack_and_flow_logo.jpg',
            fit: BoxFit.cover,
          ),

          // 2. Main Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      children: [
                        SizedBox(height: isMobile ? 24 : 40),
                        SizedBox(
                            height: constraints.maxHeight *
                                (isMobile ? 0.24 : 0.3)),
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
                        SizedBox(height: isMobile ? 24 : 40),
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
                                        () => _showAISelector(
                                          context,
                                          isPractice: true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _SecondaryButton(
                                        "Leaderboard",
                                        () => _pushWithTransition(
                                          context,
                                          const LeaderboardScreen(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _SecondaryButton(
                                        "Settings",
                                        () => _showSettings(context),
                                      ),
                                      const SizedBox(width: 12),
                                      _SecondaryButton(
                                        "Rules",
                                        () => _pushWithTransition(
                                          context,
                                          const RulesScreen(),
                                        ),
                                      ),
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
                                        () => _showAISelector(
                                          context,
                                          isPractice: true,
                                        ),
                                      ),
                                      _SecondaryButton(
                                        "Leaderboard",
                                        () => _pushWithTransition(
                                          context,
                                          const LeaderboardScreen(),
                                        ),
                                      ),
                                      _SecondaryButton(
                                        "Settings",
                                        () => _showSettings(context),
                                      ),
                                      _SecondaryButton(
                                        "Rules",
                                        () => _pushWithTransition(
                                          context,
                                          const RulesScreen(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 32),
                        const DefaultTextStyle(
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                          child: Text(
                            "Server validated • Secure matchmaking • Instant reconnect",
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
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
