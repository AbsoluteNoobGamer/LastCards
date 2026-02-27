part of 'start_screen.dart';

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final buttonWidth = isMobile
        ? (screenWidth * 0.78).clamp(220.0, 360.0)
        : (screenWidth * 0.3).clamp(220.0, 300.0);
    final buttonHeight = isMobile ? 64.0 : 70.0;
    final iconSize = isMobile ? 24.0 : 28.0;
    final labelSize = isMobile ? 18.0 : 20.0;

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
        width: buttonWidth,
        height: buttonHeight,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(buttonHeight / 2),
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
            borderRadius: BorderRadius.circular(buttonHeight / 2),
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
                  style: TextStyle(fontSize: iconSize),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: labelSize,
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
