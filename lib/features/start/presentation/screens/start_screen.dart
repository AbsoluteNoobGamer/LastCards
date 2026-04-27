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
import '../../../../core/widgets/prestige_avatar_frame.dart';
import '../../../../app/app_route_observer.dart';
import '../../../../services/start_screen_bgm.dart';
import '../../../../features/social/widgets/friends_list_sheet.dart';
import '../../../../features/social/widgets/pending_friend_requests_banner.dart';
import '../../../../features/social/widgets/pending_game_invites_banner.dart';
import '../../../../core/monetization/monetization_config.dart';
import '../../../../core/monetization/monetization_provider.dart';
import '../../../../core/monetization/post_game_interstitial.dart';
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
  late AnimationController _godRayController;
  late AnimationController _shockwaveController;

  final GlobalKey _stackKey = GlobalKey();
  Offset _parallaxNorm = Offset.zero;
  Offset? _shockwaveCenter;

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
    _godRayController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 55),
    );
    _shockwaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shockwaveController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _shockwaveCenter = null);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(StartScreenBgm.instance.start());
      final disable = MediaQuery.disableAnimationsOf(context);
      if (!disable) {
        _bgController.repeat();
        _titleShimmerController.repeat();
        _dividerController.repeat(reverse: true);
        _primaryEntranceController.forward();
        if (_cinematicEffectsCore(
          context,
          ref.read(settingsProvider).budgetDeviceMode,
        )) {
          _godRayController.repeat();
        }
      } else {
        _bgController.value = 0;
        _titleShimmerController.value = 0;
        _dividerController.value = 1.0;
        _primaryEntranceController.value = 1.0;
        _godRayController.value = 0;
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
    // Post-game interstitial: only after a completed session (see
    // [PostGameInterstitialNotifier.markCompletedPlaySession]) and subject to
    // cooldown + remove-ads purchase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(postGameInterstitialProvider.notifier)
            .maybeShowWhenStartVisible(ref, context),
      );
    });
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    unawaited(StartScreenBgm.instance.stop());
    _bgController.dispose();
    _primaryEntranceController.dispose();
    _titleShimmerController.dispose();
    _dividerController.dispose();
    _godRayController.dispose();
    _shockwaveController.dispose();
    super.dispose();
  }

  /// Shared logic for “heavy” start-screen VFX (god rays, bloom, parallax, shockwave).
  /// [budgetDeviceMode] is true when “Lower Performance” is enabled in settings.
  static bool _cinematicEffectsCore(
    BuildContext context,
    bool budgetDeviceMode,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (budgetDeviceMode) return false;
    final Size s = MediaQuery.sizeOf(context);
    return s.shortestSide >= 600 || s.width >= 840;
  }

  bool _cinematicEffects(BuildContext context) {
    final bool budget = ref.watch(settingsProvider).budgetDeviceMode;
    return _cinematicEffectsCore(context, budget);
  }

  void _syncGodRayWithCinematic() {
    if (!mounted) return;
    final bool budget = ref.read(settingsProvider).budgetDeviceMode;
    if (_cinematicEffectsCore(context, budget)) {
      if (!_godRayController.isAnimating) {
        _godRayController.repeat();
      }
    } else {
      _godRayController.stop();
      _godRayController.reset();
    }
  }

  void _updateParallax(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset local = box.globalToLocal(globalPosition);
    final double w = box.size.width;
    final double h = box.size.height;
    if (w <= 0 || h <= 0) return;
    final double nx = ((local.dx / w) - 0.5) * 2;
    final double ny = ((local.dy / h) - 0.5) * 2;
    final Offset next = Offset(
      nx.clamp(-1.0, 1.0),
      ny.clamp(-1.0, 1.0),
    );
    if ((next - _parallaxNorm).distanceSquared < 1e-8) return;
    setState(() => _parallaxNorm = next);
  }

  void _triggerShockwave(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset local = box.globalToLocal(globalPosition);
    setState(() => _shockwaveCenter = local);
    _shockwaveController.forward(from: 0);
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

  Widget _buildTitleBlock({
    required AppThemeData splashTheme,
    required bool disableAnim,
    required bool cinematic,
  }) {
    final TextStyle titleStyle = gameTitleTextStyle(
      splashTheme,
      fontSize: 42,
      fontWeight: FontWeight.bold,
      letterSpacing: 5.0,
      color: Colors.white,
      shadows: [
        Shadow(
          color: splashTheme.accentPrimary.withValues(alpha: 0.38),
          blurRadius: 24,
        ),
        const Shadow(
          color: Color(0x80000000),
          blurRadius: 6,
          offset: Offset(0, 3),
        ),
      ],
    );

    Widget buildTitleShader() {
      if (disableAnim) {
        return ShaderMask(
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
            'Last Cards',
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
        );
      }
      return AnimatedBuilder(
        animation: _titleShimmerController,
        builder: (context, _) {
          final double t = _titleShimmerController.value;
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
              'Last Cards',
              textAlign: TextAlign.center,
              style: titleStyle,
            ),
          );
        },
      );
    }

    final Widget core = buildTitleShader();

    if (!cinematic || disableAnim) {
      return core;
    }

    Widget blurredTitle() {
      return ShaderMask(
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
          'Last Cards',
          textAlign: TextAlign.center,
          style: titleStyle,
        ),
      );
    }

    return Transform.translate(
      offset: Offset(
        -_parallaxNorm.dx * 8,
        -_parallaxNorm.dy * 6,
      ),
      child: ClipRect(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Opacity(
                opacity: 0.35,
                child: blurredTitle(),
              ),
            ),
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Opacity(
                opacity: 0.18,
                child: blurredTitle(),
              ),
            ),
            core,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monetization = ref.watch(monetizationProvider);
    final reserveScrollPaddingForAds = kSupportsStoreMonetization() &&
        monetization.ready &&
        !monetization.adsRemoved;
    ref.listen<SettingsState>(settingsProvider, (prev, next) {
      if (prev?.budgetDeviceMode == next.budgetDeviceMode) return;
      _syncGodRayWithCinematic();
      if (next.budgetDeviceMode) {
        setState(() {
          _parallaxNorm = Offset.zero;
          _shockwaveCenter = null;
        });
        _shockwaveController.reset();
      }
    });
    final bool cinematic = _cinematicEffects(context);
    final Color accentForVfx =
        ref.watch(themeProvider).theme.accentPrimary;

    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent e) {
          StartScreenBgm.instance.notifyUserGesture();
          if (_cinematicEffects(context)) {
            _triggerShockwave(e.position);
          }
        },
        onPointerMove: (PointerMoveEvent e) {
          if (_cinematicEffects(context)) {
            _updateParallax(e.position);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        Expanded(
          child: Stack(
          fit: StackFit.expand,
          children: [
          Stack(
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(
                    _parallaxNorm.dx * 10,
                    _parallaxNorm.dy * 8,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(
                          'assets/images/StackandFlowBackground.png',
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(
                    _parallaxNorm.dx * 16,
                    _parallaxNorm.dy * 12,
                  ),
                  child: AnimatedBuilder(
                    animation: _bgController,
                    builder: (context, _) => CustomPaint(
                      painter: ParticleStarfieldPainter(
                        progress: _bgController.value,
                      ),
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
              if (cinematic)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.05,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.42),
                          ],
                          stops: const [0.52, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              if (cinematic)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _godRayController,
                      builder: (context, _) => CustomPaint(
                        painter: GodRaysPainter(
                          rotation: _godRayController.value * 2 * pi,
                          accent: accentForVfx,
                        ),
                      ),
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
                              _buildTitleBlock(
                                splashTheme: splashTheme,
                                disableAnim: disableAnim,
                                cinematic: cinematic,
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
                        // Extra bottom inset when a banner may show so the icon row
                        // stays above the ad slot and remains scrollable/tappable.
                        SizedBox(
                          height: reserveScrollPaddingForAds ? 120 : 32,
                        ),
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
          // 5. Cinematic tap shockwave (tablet / desktop layout)
          if (cinematic && _shockwaveCenter != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shockwaveController,
                  builder: (context, _) => CustomPaint(
                    painter: ShockwavePainter(
                      center: _shockwaveCenter!,
                      progress: Curves.easeOutCubic
                          .transform(_shockwaveController.value),
                      accent: accentForVfx,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
        // Banner sits in layout flow (not stacked over content) so the icon row
        // and Settings remain tappable and reachable for "Remove ads".
        Consumer(
          builder: (context, ref, _) {
            final m = ref.watch(monetizationProvider);
            if (!kSupportsStoreMonetization() || !m.ready || m.adsRemoved) {
              return const SizedBox.shrink();
            }
            final id = kBannerAdUnitIdForPlatform();
            if (id.isEmpty) return const SizedBox.shrink();
            return SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: MonetizationBannerAd(adUnitId: id),
              ),
            );
          },
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
