import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../lobby/presentation/screens/lobby_screen.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../leaderboard/presentation/screens/leaderboard_screen.dart';
import '../../../rules/presentation/screens/rules_screen.dart';
import '../../../settings/presentation/widgets/settings_modal.dart';
import '../../../../features/single_player/widgets/difficulty_selection_sheet.dart';
import '../../../../features/online/widgets/mode_selection_sheet.dart';
import '../widgets/card_back_selection_menu.dart';
import '../../../../core/theme/theme_selector_modal.dart';
import '../../../../core/navigation/app_page_routes.dart';
import '../../../../core/widgets/glass_frosted_panel.dart';
import '../../../../core/widgets/themed_shimmer.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/server_live_connections_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../features/profile/presentation/screens/profile_screen.dart';
import '../../../../features/profile/widgets/profile_stats_section.dart';
import '../../../../features/tournament/widgets/tournament_type_sheet.dart';
import '../../../../core/widgets/player_progress_widgets.dart';
import '../../../../app/app_route_observer.dart';
import '../../../../services/start_screen_bgm.dart';
import '../../../../features/social/widgets/friends_list_sheet.dart';
import '../../../../features/social/widgets/pending_friend_requests_banner.dart';
import '../../../../features/social/widgets/pending_game_invites_banner.dart';
import '../../../../core/monetization/monetization_config.dart';
import '../../../../core/monetization/monetization_provider.dart';
import '../../../../core/widgets/monetization_banner_ad.dart';

part 'start_screen_background.dart';
part 'start_screen_buttons.dart';

class LastCardsStartScreen extends ConsumerStatefulWidget {
  const LastCardsStartScreen({super.key});

  @override
  ConsumerState<LastCardsStartScreen> createState() =>
      _LastCardsStartScreenState();
}

class _LastCardsStartScreenState extends ConsumerState<LastCardsStartScreen>
    with TickerProviderStateMixin, RouteAware {
  late AnimationController _bgController;
  late AnimationController _primaryEntranceController;
  late AnimationController _titleShimmerController;
  late AnimationController _dividerController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _primaryEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _titleShimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _dividerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(StartScreenBgm.instance.start());
      final disable = MediaQuery.disableAnimationsOf(context);
      if (!disable) {
        _bgController.repeat();
        _titleShimmerController.repeat();
        _dividerController.repeat(reverse: true);
        _primaryEntranceController.forward();
      } else {
        _bgController.value = 0;
        _titleShimmerController.value = 0;
        _dividerController.value = 1.0;
        _primaryEntranceController.value = 1.0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // MaterialPageRoute is PageRoute<dynamic>, not PageRoute<void> — subscribe correctly.
    if (route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    unawaited(StartScreenBgm.instance.onRouteCovered());
  }

  @override
  void didPopNext() {
    unawaited(StartScreenBgm.instance.onRouteVisible());
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    unawaited(StartScreenBgm.instance.stop());
    _bgController.dispose();
    _primaryEntranceController.dispose();
    _titleShimmerController.dispose();
    _dividerController.dispose();
    super.dispose();
  }

  /// Staggered slide + fade for primary menu buttons (indices 0–2).
  Widget _wrapPrimaryEntrance(int index, Widget child) {
    final disable = MediaQuery.disableAnimationsOf(context);
    if (disable) return child;

    const intervals = <Interval>[
      Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      Interval(0.15, 0.75, curve: Curves.easeOutCubic),
      Interval(0.3, 0.9, curve: Curves.easeOutCubic),
    ];
    final interval = intervals[index];

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _primaryEntranceController,
          curve: interval,
        ),
      ),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _primaryEntranceController,
            curve: interval,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => StartScreenBgm.instance.notifyUserGesture(),
        child: Stack(
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
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _bgController,
                  builder: (context, _) => CustomPaint(
                    painter: ParticleStarfieldPainter(
                      progress: _bgController.value,
                    ),
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
                final isMobile = min(constraints.maxWidth, constraints.maxHeight) < 600;
                final disableAnim = MediaQuery.disableAnimationsOf(context);
                final splashTheme = ref.watch(themeProvider).theme;
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
                              disableAnim
                                  ? ShaderMask(
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
                                        "Last Cards",
                                        textAlign: TextAlign.center,
                                        style: gameTitleTextStyle(
                                          splashTheme,
                                          fontSize: 42,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 5.0,
                                          color: Colors.white,
                                          shadows: [
                                            Shadow(
                                              color: splashTheme.accentPrimary
                                                  .withValues(alpha: 0.38),
                                              blurRadius: 24,
                                            ),
                                            const Shadow(
                                              color: Color(0x80000000),
                                              blurRadius: 6,
                                              offset: Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : AnimatedBuilder(
                                      animation: _titleShimmerController,
                                      builder: (context, _) {
                                        final t = _titleShimmerController.value;
                                        return ShaderMask(
                                          shaderCallback: (Rect bounds) {
                                            return LinearGradient(
                                              begin: Alignment(-1.0 + 2.0 * t, 0),
                                              end: Alignment(1.0 + 2.0 * t, 0),
                                              colors: const [
                                                Color(0xFFFFE566),
                                                Color(0xFFC9A84C),
                                                Color(0xFFFFE566),
                                              ],
                                              stops: const [0.0, 0.5, 1.0],
                                            ).createShader(bounds);
                                          },
                                          child: Text(
                                            "Last Cards",
                                            textAlign: TextAlign.center,
                                            style: gameTitleTextStyle(
                                              splashTheme,
                                              fontSize: 42,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 5.0,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  color: splashTheme
                                                      .accentPrimary
                                                      .withValues(alpha: 0.38),
                                                  blurRadius: 24,
                                                ),
                                                const Shadow(
                                                  color: Color(0x80000000),
                                                  blurRadius: 6,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              const SizedBox(height: 6),
                              Text(
                                "Play it all. Leave nothing.",
                                textAlign: TextAlign.center,
                                style: gameTitleTextStyle(
                                  splashTheme,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 3.0,
                                  color: splashTheme.accentPrimary
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              SizedBox(height: isMobile ? 40 : 56),
                              isMobile
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _wrapPrimaryEntrance(0, _PlayAiButton()),
                                        const SizedBox(height: 20),
                                        _wrapPrimaryEntrance(
                                            1, _PlayOnlineButton()),
                                        const SizedBox(height: 20),
                                        _wrapPrimaryEntrance(
                                            2, _TournamentButton()),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _wrapPrimaryEntrance(
                                                0, _PlayAiButton()),
                                            const SizedBox(width: 24),
                                            _wrapPrimaryEntrance(
                                                1, _PlayOnlineButton()),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        _wrapPrimaryEntrance(
                                            2, _TournamentButton()),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                        SizedBox(height: isMobile ? 48 : 64),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: disableAnim
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Expanded(
                                        child:
                                            Divider(color: Color(0x40C9A84C))),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Text(
                                        "LAST CARDS",
                                        style: GoogleFonts.cinzel(
                                          color: Color(0xFFC9A84C),
                                          fontSize: 13,
                                          letterSpacing: 6.0,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const Expanded(
                                        child:
                                            Divider(color: Color(0x40C9A84C))),
                                  ],
                                )
                              : AnimatedBuilder(
                                  animation: _dividerController,
                                  builder: (context, _) {
                                    final pulse =
                                        0.55 + 0.45 * _dividerController.value;
                                    return Opacity(
                                      opacity: pulse,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: Divider(
                                              color: const Color(0x40C9A84C)
                                                  .withValues(alpha: pulse),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets
                                                .symmetric(horizontal: 16),
                                            child: Text(
                                              "LAST CARDS",
                                              style: GoogleFonts.cinzel(
                                                color: const Color(0xFFC9A84C)
                                                    .withValues(alpha: pulse),
                                                fontSize: 13,
                                                letterSpacing: 6.0,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(
                                              color: const Color(0x40C9A84C)
                                                  .withValues(alpha: pulse),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
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

          // 3. Friends (top-left) + room invites + friend requests (leave space for profile badge)
          Positioned(
            top: 0,
            left: 0,
            right: 100,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _FriendsTopLeftButton(
                      onTap: () => _showFriendsSheet(context),
                    ),
                  ),
                  const PendingGameInvitesBanner(),
                  const PendingFriendRequestsBanner(),
                ],
              ),
            ),
          ),

          // 4. Auth profile badge — top-right corner
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: _AuthProfileBadge(
                onTap: () => _showAuthProfileSheet(context),
              ),
            ),
          ),

          // 5. Banner ad (hidden after remove-ads purchase or on non-mobile)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: Consumer(
                  builder: (context, ref, _) {
                    final m = ref.watch(monetizationProvider);
                    if (!kSupportsStoreMonetization() ||
                        !m.ready ||
                        m.adsRemoved) {
                      return const SizedBox.shrink();
                    }
                    final id = kBannerAdUnitIdForPlatform();
                    if (id.isEmpty) return const SizedBox.shrink();
                    return MonetizationBannerAd(adUnitId: id);
                  },
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  void _showAuthProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ProviderScope(
        child: _AuthProfileSheet(),
      ),
    );
  }

  void _pushWithTransition(BuildContext context, Widget screen) {
    Navigator.push(context, AppPageRoutes.fadeSlide((_) => screen));
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProviderScope(child: SettingsModal()),
    );
  }

  void _showFriendsSheet(BuildContext context) {
    final theme = ref.read(themeProvider).theme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.backgroundDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const FriendsListSheet(),
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

  void _showAISelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DifficultySelectionSheet(),
    );
  }

  void _showOnlineModeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModeSelectionSheet(),
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
