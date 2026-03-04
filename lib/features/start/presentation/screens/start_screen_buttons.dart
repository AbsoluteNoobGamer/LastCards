part of 'start_screen.dart';

// -----------------------------------------------------------------------------
// Profile Badge (top-right corner of main menu)
// -----------------------------------------------------------------------------

/// Displays the local player's avatar and display name in a compact chip.
/// Watches [profileProvider] so it automatically rebuilds when the profile
/// is saved and the user returns from [ProfileScreen].
class _ProfileBadge extends ConsumerWidget {
  const _ProfileBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final avatarPath = profile.avatarPath;

    final Widget avatarWidget = avatarPath != null
        ? CircleAvatar(
            radius: 22,
            backgroundImage: FileImage(File(avatarPath)),
            backgroundColor: const Color(0xFF1C1C1C),
          )
        : const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF1C1C1C),
            child:
                Icon(Icons.person_rounded, size: 24, color: Color(0xFFC9A84C)),
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
            color: const Color(0xFFC9A84C).withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar circle
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFC9A84C),
                  width: 2,
                ),
              ),
              child: avatarWidget,
            ),
            const SizedBox(width: 8),
            // Player name
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                profile.name,
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
            // Edit pencil icon
            const Icon(
              Icons.edit_rounded,
              color: Color(0xFFC9A84C),
              size: 14,
            ),
          ],
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
      iconWidget:
          const Icon(Icons.smart_toy, color: Color(0xFFFFD700), size: 28),
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
      label: "Online",
      iconWidget: const Icon(Icons.people, color: Color(0xFFFFD700), size: 28),
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
            context.findAncestorStateOfType<_StackFlowStartScreenState>();
        if (parentState != null) {
          parentState._showOnlineModeSelector(context);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LobbyScreen()),
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
                  const Text(
                    "12/24 online",
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC9A84C),
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
      iconWidget:
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 26),
      isHovered: _isHovered,
      isPressed: _isPressed,
      onHover: (val) => setState(() => _isHovered = val),
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TournamentScreen()));
      },
    );
  }
}

class _PrimaryButtonBase extends StatelessWidget {
  final String label;
  final Widget iconWidget;
  final Widget? subtitle;
  final bool isHovered;
  final bool isPressed;
  final ValueChanged<bool> onHover;
  final GestureTapDownCallback onTapDown;
  final GestureTapCancelCallback onTapCancel;
  final VoidCallback onTap;

  const _PrimaryButtonBase({
    required this.label,
    required this.iconWidget,
    this.subtitle,
    required this.isHovered,
    required this.isPressed,
    required this.onHover,
    required this.onTapDown,
    required this.onTapCancel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final buttonWidth = isMobile
        ? (screenWidth * 0.78).clamp(220.0, 360.0)
        : (screenWidth * 0.3).clamp(220.0, 300.0);
    const buttonHeight = 68.0;

    final scale = isPressed ? 0.95 : (isHovered ? 1.05 : 1.0);

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(scale, scale),
        transformAlignment: Alignment.center,
        width: buttonWidth,
        height: buttonHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFF8B6500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30FFD700),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Color(0x15FFD700),
              blurRadius: 40,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                colors: [Color(0xFF2B1700), Color(0xFF1A0E00)],
                radius: 1.5,
              ),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.0),
                    splashColor: const Color(0xFFFFD700).withOpacity(0.3),
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
                        iconWidget,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 2.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                subtitle!,
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
// Secondary Buttons
// -----------------------------------------------------------------------------

class _SecondaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SecondaryButton(this.label, this.icon, this.onTap);

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
          ..scale(_isHovered ? 1.05 : 1.0, _isHovered ? 1.05 : 1.0),
        transformAlignment: Alignment.center,
        height: 80.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFF8B6500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30FFD700),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Color(0x15FFD700),
              blurRadius: 40,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                colors: [Color(0xFF2B1700), Color(0xFF1A0E00)],
                radius: 1.5,
              ),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12.0),
                    splashColor: const Color(0xFFC9A84C).withOpacity(0.3),
                    highlightColor: Colors.transparent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(widget.icon,
                                color: const Color(0xFFFFD700), size: 22),
                            const SizedBox(height: 6),
                            Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
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
