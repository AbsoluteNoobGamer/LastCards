import 'dart:async';
import 'dart:io';
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
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../../core/providers/profile_provider.dart';

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

    // Load the saved profile from SharedPreferences so the avatar and name
    // are up-to-date when the menu appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).loadFromPrefs();
    });
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
          Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/StackandFlowBackground.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99000000),
                      Color(0xCC000000),
                    ],
                  ),
                ),
              ),
            ],
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
                          child: Column(
                            children: [
                              Text(
                                "Stack and Flow",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cinzel(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFFFD700),
                                  letterSpacing: 6.0,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0x80FFD700), // #FFD70080
                                      blurRadius: 20,
                                    ),
                                    const Shadow(
                                      color: Color(0x60000000), // #00000060
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: isMobile ? 32 : 48),
                              isMobile
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
                            ],
                          ),
                        ),
                        SizedBox(height: isMobile ? 24 : 40),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: _SecondaryButton(
                                  "Practice Mode",
                                  Icons.style_rounded,
                                  () => _showAISelector(
                                    context,
                                    isPractice: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SecondaryButton(
                                  "Leaderboard",
                                  Icons.emoji_events_rounded,
                                  () => _pushWithTransition(
                                    context,
                                    const LeaderboardScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SecondaryButton(
                                  "Settings",
                                  Icons.settings_rounded,
                                  () => _showSettings(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SecondaryButton(
                                  "Rules",
                                  Icons.menu_book_rounded,
                                  () => _pushWithTransition(
                                    context,
                                    const RulesScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          "STACK & FLOW",
                          style: GoogleFonts.cinzel(
                            color: const Color(0xFFC9A84C),
                            fontSize: 12,
                            letterSpacing: 4.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Profile badge — top-right corner
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: _ProfileBadge(
                onTap: () => _openProfileScreen(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openProfileScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
    ).then((_) {
      // Refresh profile state when returning from ProfileScreen.
      if (mounted) ref.read(profileProvider.notifier).loadFromPrefs();
    });
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
