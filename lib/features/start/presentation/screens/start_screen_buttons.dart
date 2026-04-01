part of 'start_screen.dart';

// -----------------------------------------------------------------------------
// Auth Profile Badge (top-right corner of main menu)
// -----------------------------------------------------------------------------

/// Displays the signed-in user's avatar and display name from Firebase Auth.
/// Shows Google photo/name or Guest for anonymous. Tap to open account sheet.
class _AuthProfileBadge extends ConsumerWidget {
  const _AuthProfileBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final theme = ref.watch(themeProvider).theme;

    if (profileAsync.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, right: 12),
        child: ThemedShimmer(
          width: 120,
          height: 40,
          borderRadius: 20,
        ),
      );
    }

    final userProfile = profileAsync.valueOrNull;
    final String displayName = userProfile?.displayName ?? 'Guest';
    final String? avatarUrl = userProfile?.avatarUrl;

    final Widget avatarWidget = avatarUrl != null
        ? CircleAvatar(
            radius: 22,
            backgroundImage: NetworkImage(avatarUrl),
            backgroundColor: theme.surfacePanel,
          )
        : CircleAvatar(
            radius: 22,
            backgroundColor: theme.surfacePanel,
            child: Icon(
              Icons.person_rounded,
              size: 24,
              color: theme.accentPrimary,
            ),
          );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8, right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: theme.accentPrimary.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.accentPrimary,
                  width: 2,
                ),
              ),
              child: avatarWidget,
            ),
            const SizedBox(width: 8),
            PlayerLevelChip(
              accentColor: theme.accentPrimary,
              backgroundColor: theme.accentPrimary.withValues(alpha: 0.15),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.account_circle_rounded,
              color: theme.accentPrimary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Auth Profile Sheet (account info + Sign out)
// -----------------------------------------------------------------------------

class _AuthProfileSheet extends ConsumerStatefulWidget {
  const _AuthProfileSheet();

  @override
  ConsumerState<_AuthProfileSheet> createState() => _AuthProfileSheetState();
}

class _AuthProfileSheetState extends ConsumerState<_AuthProfileSheet> {
  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider).valueOrNull;
    final theme = ref.watch(themeProvider).theme;
    final authService = ref.read(authServiceProvider);

    final String displayName = userProfile?.displayName ?? 'Guest';
    final String? avatarUrl = userProfile?.avatarUrl;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 32).add(
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: theme.accentPrimary, width: 2),
                      ),
                      child: avatarUrl != null
                          ? CircleAvatar(
                              radius: 40,
                              backgroundImage: NetworkImage(avatarUrl),
                              backgroundColor: theme.surfacePanel,
                            )
                          : CircleAvatar(
                              radius: 40,
                              backgroundColor: theme.surfacePanel,
                              child: Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: theme.accentPrimary,
                              ),
                            ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PlayerXpProgressBarThemed(theme: theme),
                const SizedBox(height: 16),
                const ProfileStatsSection(
                  showXpProgress: false,
                  statsHeaderTopSpacing: 0,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        AppPageRoutes.fadeSlide((_) => const ProfileScreen()),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentPrimary,
                      side: BorderSide(color: theme.accentPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await authService.signOut();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentPrimary,
                      side: BorderSide(color: theme.accentPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
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
// Primary Buttons
// -----------------------------------------------------------------------------

class _PlayAiButton extends StatefulWidget {
  @override
  State<_PlayAiButton> createState() => _PlayAiButtonState();
}

class _PlayAiButtonState extends State<_PlayAiButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return _PrimaryButtonBase(
      label: "Single Player",
      iconKey: 'bot',
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        final parentState =
            context.findAncestorStateOfType<_LastCardsStartScreenState>();
        if (parentState != null) {
          parentState._showAISelector(context);
        } else {
          Navigator.push(
            context,
            AppPageRoutes.fadeSlide((_) => const TableScreen()),
          );
        }
      },
    );
  }
}

class _PlayOnlineButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PlayOnlineButton> createState() => _PlayOnlineButtonState();
}

class _PlayOnlineButtonState extends ConsumerState<_PlayOnlineButton>
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
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _pulseController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final scaleAnim =
        Tween<double>(begin: 1.0, end: 1.05).animate(_pulseController);
    final countAsync = ref.watch(onlinePlayerCountProvider);
    final onlineLabel = countAsync.when(
      data: (c) => c != null ? '$c online' : '-- online',
      loading: () => '-- online',
      error: (_, __) => '-- online',
    );

    return _PrimaryButtonBase(
      label: "Online",
      iconKey: 'online',
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        final parentState =
            context.findAncestorStateOfType<_LastCardsStartScreenState>();
        if (parentState != null) {
          parentState._showOnlineModeSelector(context);
        } else {
          Navigator.pushReplacement(
            context,
            AppPageRoutes.fadeSlide((_) => const LobbyScreen()),
          );
        }
      },
      subtitle: AnimatedBuilder(
          animation: scaleAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: scaleAnim.value,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFF00FF88),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x8000FF88),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ]),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    onlineLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }),
    );
  }
}

class _TournamentButton extends StatefulWidget {
  @override
  State<_TournamentButton> createState() => _TournamentButtonState();
}

class _TournamentButtonState extends State<_TournamentButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return _PrimaryButtonBase(
      label: "Tournament",
      iconKey: 'trophy',
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const TournamentTypeSheet(),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// _PrimaryButtonBase — theme-aware + idle shimmer
// -----------------------------------------------------------------------------

class _PrimaryButtonBase extends ConsumerStatefulWidget {
  final String label;
  final String iconKey; // 'bot' | 'online' | 'trophy'
  final Widget? subtitle;
  final bool isHovered;
  final bool isPressed;
  final ValueChanged<bool> onHover;
  final GestureTapDownCallback onTapDown;
  final GestureTapCancelCallback onTapCancel;
  final VoidCallback onTap;

  const _PrimaryButtonBase({
    required this.label,
    required this.iconKey,
    this.subtitle,
    required this.isHovered,
    required this.isPressed,
    required this.onHover,
    required this.onTapDown,
    required this.onTapCancel,
    required this.onTap,
  });

  @override
  ConsumerState<_PrimaryButtonBase> createState() => _PrimaryButtonBaseState();
}

class _PrimaryButtonBaseState extends ConsumerState<_PrimaryButtonBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shimmer.repeat();
      }
    });
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final accent = theme.accentPrimary;
    final accentLight = theme.accentLight;
    final accentDark = theme.accentDark;
    final bg = theme.backgroundDeep;
    final bgMid = theme.backgroundMid;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final buttonWidth = isMobile
        ? (screenWidth * 0.78).clamp(220.0, 360.0)
        : (screenWidth * 0.3).clamp(220.0, 300.0);
    const buttonHeight = 68.0;

    final scale = widget.isPressed ? 0.95 : (widget.isHovered ? 1.05 : 1.0);

    final IconData iconData = widget.iconKey == 'bot'
        ? Icons.smart_toy
        : widget.iconKey == 'online'
            ? Icons.people
            : Icons.emoji_events;

    final disableAnim = MediaQuery.disableAnimationsOf(context);

    return MouseRegion(
      onEnter: (_) => widget.onHover(true),
      onExit: (_) => widget.onHover(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(scale, scale, 1.0),
        transformAlignment: Alignment.center,
        width: buttonWidth,
        height: buttonHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [accentLight, accentDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.30),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 40,
              spreadRadius: 4,
            ),
            const BoxShadow(
              color: Color(0x80000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        bg.withValues(alpha: 0.95),
                        bgMid.withValues(alpha: 0.98),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                if (!disableAnim)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRect(
                        child: AnimatedBuilder(
                          animation: _shimmer,
                          builder: (context, _) {
                            final t = _shimmer.value;
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth;
                                final bandW = w * 0.42;
                                final travel = w + bandW * 2;
                                final left = -bandW + t * travel;
                                return Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned(
                                      left: left,
                                      top: 0,
                                      bottom: 0,
                                      width: bandW,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Colors.transparent,
                                              accentLight.withValues(
                                                  alpha: 0.12),
                                              accentLight.withValues(
                                                  alpha: 0.22),
                                              accentLight.withValues(
                                                  alpha: 0.12),
                                              Colors.transparent,
                                            ],
                                            stops: const [
                                              0.0,
                                              0.35,
                                              0.5,
                                              0.65,
                                              1.0,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.0),
                    splashColor: accent.withValues(alpha: 0.25),
                    highlightColor: Colors.transparent,
                    onTapDown: widget.onTapDown,
                    onTapCancel: widget.onTapCancel,
                    onTap: () {
                      widget.onTap();
                      Future.delayed(const Duration(milliseconds: 150), () {
                        if (context.mounted) widget.onTapCancel();
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(iconData, color: accent, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.label,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: theme.textPrimary,
                                  letterSpacing: 2.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2),
                                widget.subtitle!,
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
// Icon Row Items (bottom of screen — minimal, no borders)
// -----------------------------------------------------------------------------

/// A borderless, backgroundless icon + label item for the bottom icon row.
/// Shows a themed-accent icon with a small label underneath.
class _IconRowItem extends ConsumerStatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _IconRowItem(this.label, this.icon, this.onTap);

  @override
  ConsumerState<_IconRowItem> createState() => _IconRowItemState();
}

class _IconRowItemState extends ConsumerState<_IconRowItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final accent = theme.accentPrimary;
    final accentLight = theme.accentLight;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(
            _isPressed ? 0.90 : (_isHovered ? 1.12 : 1.0),
            _isPressed ? 0.90 : (_isHovered ? 1.12 : 1.0),
            1.0,
          ),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: _isHovered ? 0.12 : 0.0),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.2),
                        blurRadius: 12,
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [accentLight, accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Icon(
                    widget.icon,
                    color: Colors.white, // overridden by ShaderMask
                    size: 26,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
