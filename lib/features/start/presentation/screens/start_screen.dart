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
import '../widgets/online_mode_selector_modal.dart';
import '../widgets/card_back_selection_menu.dart';
import '../../../../core/theme/theme_selector_modal.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../screens/tournament_screen.dart';

part 'start_screen_background.dart';
part 'start_screen_buttons.dart';

class DeckDropStartScreen extends ConsumerStatefulWidget {
  const DeckDropStartScreen({super.key});

  @override
  ConsumerState<DeckDropStartScreen> createState() =>
      _DeckDropStartScreenState();
}

class _DeckDropStartScreenState extends ConsumerState<DeckDropStartScreen>
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
                    image:
                        AssetImage('assets/images/StackandFlowBackground.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ref.watch(themeProvider).theme.overlayTop,
                      ref.watch(themeProvider).theme.overlayBottom,
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
                              ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return const LinearGradient(
                                    colors: [
                                      Color(0xFFFFE566),
                                      Color(0xFFC9A84C),
                                      Color(0xFFFFE566),
                                    ],
                                  ).createShader(bounds);
                                },
                                child: Text(
                                  "DeckDrop",
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cinzel(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 5.0,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x60FFD700),
                                        blurRadius: 24,
                                      ),
                                      Shadow(
                                        color: Color(0x80000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Play it all. Leave nothing.",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cinzel(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: ref
                                      .watch(themeProvider)
                                      .theme
                                      .accentPrimary
                                      .withValues(alpha: 0.55),
                                  letterSpacing: 3.0,
                                ),
                              ),
                              SizedBox(height: isMobile ? 40 : 56),
                              isMobile
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _PlayAiButton(),
                                        const SizedBox(height: 20),
                                        _PlayOnlineButton(),
                                        const SizedBox(height: 20),
                                        _TournamentButton(),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _PlayAiButton(),
                                            const SizedBox(width: 24),
                                            _PlayOnlineButton(),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        _TournamentButton(),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                        SizedBox(height: isMobile ? 48 : 64),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Expanded(
                                  child: Divider(color: Color(0x40C9A84C))),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  "DECKDROP",
                                  style: GoogleFonts.cinzel(
                                    color: const Color(0xFFC9A84C),
                                    fontSize: 13,
                                    letterSpacing: 6.0,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const Expanded(
                                  child: Divider(color: Color(0x40C9A84C))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // ── Horizontal icon row ──────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _IconRowItem(
                                "Practice",
                                Icons.style_rounded,
                                () => _showAISelector(
                                  context,
                                  isPractice: true,
                                ),
                              ),
                              _IconRowItem(
                                "Leaderboard",
                                Icons.emoji_events_rounded,
                                () => _pushWithTransition(
                                  context,
                                  const LeaderboardScreen(),
                                ),
                              ),
                              _IconRowItem(
                                "Card Styles",
                                Icons.style_rounded,
                                () => _showCardStyles(context),
                              ),
                              _IconRowItem(
                                "Themes",
                                Icons.palette_rounded,
                                () => _showThemeSelector(context),
                              ),
                              _IconRowItem(
                                "Settings",
                                Icons.settings_rounded,
                                () => _showSettings(context),
                              ),
                              _IconRowItem(
                                "Rules",
                                Icons.menu_book_rounded,
                                () => _pushWithTransition(
                                  context,
                                  const RulesScreen(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
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

  void _showCardStyles(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CardStylesModal(),
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

  void _showOnlineModeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OnlineModeSelectorModal(
        onSelected: (mode) {
          _pushWithTransition(
            context,
            LobbyScreen(onlineMode: mode),
          );
        },
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ThemeSelectorModal(),
    );
  }
}
