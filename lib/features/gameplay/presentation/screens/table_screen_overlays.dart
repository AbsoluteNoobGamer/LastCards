part of 'table_screen.dart';

// ── Win dialog ────────────────────────────────────────────────────────────────

class _WinDialog extends ConsumerStatefulWidget {
  const _WinDialog({
    required this.winnerName,
    required this.isLocalWin,
    required this.onPlayAgain,
    this.isOnlineMode = false,
    this.ratingDelta,
    this.xpAwarded,
  });

  final String winnerName;
  final bool isLocalWin;
  final VoidCallback onPlayAgain;
  final bool isOnlineMode;

  /// Rating change for the local player in a ranked game, or null.
  final int? ratingDelta;

  /// Local XP gained this game (offline only), or null to hide.
  final int? xpAwarded;

  @override
  ConsumerState<_WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends ConsumerState<_WinDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  bool _celebrationDone = false;
  late final Animation<double> _scale;
  late final CurvedAnimation _fade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1.0;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final emoji = widget.isLocalWin ? '🎉' : (widget.isOnlineMode ? '👤' : '🤖');
    final headline = widget.isLocalWin ? 'YOU WIN!' : '${widget.winnerName} WINS!';
    final sub = widget.isLocalWin
        ? (widget.isOnlineMode
            ? 'Well Done, You played your last card first!'
            : 'Excellent Win!')
        : (widget.isOnlineMode
            ? '${widget.winnerName} played their last card first. Better luck next time!'
            : '${widget.winnerName} played their last card first.');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        height: MediaQuery.sizeOf(context).height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!reduce && !_celebrationDone && widget.isLocalWin)
              Positioned.fill(
                child: WinCelebrationOverlay(
                  theme: theme,
                  onFinished: () {
                    if (mounted) setState(() => _celebrationDone = true);
                  },
                ),
              ),
            Center(
              child: ScaleTransition(
                scale: _scale,
                child: FadeTransition(
                  opacity: _fade,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Material(
                      color: theme.surfacePanel,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusModal),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusModal),
                          border:
                              Border.all(color: theme.accentPrimary, width: 2),
                        ),
                        padding: const EdgeInsets.all(AppDimensions.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            reduce
                                ? Text(emoji,
                                    style: const TextStyle(fontSize: 48))
                                : TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: const Duration(milliseconds: 700),
                                    curve: Curves.elasticOut,
                                    builder: (context, scale, child) =>
                                        Transform.scale(
                                      scale: scale.clamp(0.0, 1.0),
                                      child: child,
                                    ),
                                    child: Text(emoji,
                                        style: const TextStyle(fontSize: 48)),
                                  ),
                            const SizedBox(height: AppDimensions.md),
                            Text(
                              headline,
                              style: TextStyle(
                                color: widget.isLocalWin
                                    ? theme.accentPrimary
                                    : theme.suitRed,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.sm),
                            Text(
                              sub,
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.xpAwarded != null) ...[
                              const SizedBox(height: AppDimensions.md),
                              FadeTransition(
                                opacity: _fade,
                                child: Text(
                                  '+${widget.xpAwarded} XP',
                                  style: TextStyle(
                                    color: theme.accentPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                            if (widget.ratingDelta != null) ...[
                              const SizedBox(height: AppDimensions.md),
                              _RankedResultsSection(
                                ratingDelta: widget.ratingDelta!,
                                theme: theme,
                              ),
                            ],
                            const SizedBox(height: AppDimensions.xl),
                            if (widget.isOnlineMode)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: widget.onPlayAgain,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.accentPrimary,
                                    foregroundColor: theme.backgroundDeep,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: AppDimensions.md),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusButton),
                                    ),
                                  ),
                                  child: Text(
                                    'BACK TO MENU',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      fontSize: 15,
                                      color: theme.backgroundDeep,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(context)
                                          .popUntil((route) => route.isFirst),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: AppDimensions.md),
                                        side: BorderSide(
                                          color: theme.accentDark
                                              .withValues(alpha: 0.5),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppDimensions.radiusButton),
                                        ),
                                      ),
                                      child: Text(
                                        'Main Menu',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.0,
                                          fontSize: 14,
                                          color: theme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppDimensions.sm),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: widget.onPlayAgain,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.accentPrimary,
                                        foregroundColor: theme.backgroundDeep,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: AppDimensions.md),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppDimensions.radiusButton),
                                        ),
                                      ),
                                      child: Text(
                                        'PLAY AGAIN',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          fontSize: 15,
                                          color: theme.backgroundDeep,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen radial edge vignette: fades in then out when [trigger] increments.
class _ScreenEdgePulse extends StatefulWidget {
  const _ScreenEdgePulse({
    required this.trigger,
    required this.color,
    required this.totalDuration,
    required this.fadeInDuration,
    this.maxOpacity = 0.22,
  });

  final int trigger;
  final Color color;
  final Duration totalDuration;
  final Duration fadeInDuration;
  final double maxOpacity;

  @override
  State<_ScreenEdgePulse> createState() => _ScreenEdgePulseState();
}

class _ScreenEdgePulseState extends State<_ScreenEdgePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.totalDuration);
  }

  @override
  void didUpdateWidget(covariant _ScreenEdgePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _strength(double t) {
    final fi = widget.fadeInDuration.inMilliseconds /
        widget.totalDuration.inMilliseconds;
    if (t <= fi) return (t / fi).clamp(0.0, 1.0);
    final u = (t - fi) / (1.0 - fi);
    return (1.0 - u).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final s = _strength(_c.value);
        if (s <= 0.001) return const SizedBox.shrink();
        return CustomPaint(
          painter: _EdgeVignettePulsePainter(
            color: widget.color,
            opacity: s * widget.maxOpacity,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _EdgeVignettePulsePainter extends CustomPainter {
  _EdgeVignettePulsePainter({
    required this.color,
    required this.opacity,
  });

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0),
          color.withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.68, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _EdgeVignettePulsePainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color;
}

/// Ranked results section with MMR delta, and fetched stats (MMR, W/L, tier).
class _RankedResultsSection extends StatefulWidget {
  const _RankedResultsSection({
    required this.ratingDelta,
    required this.theme,
  });

  final int ratingDelta;
  final AppThemeData theme;

  @override
  State<_RankedResultsSection> createState() => _RankedResultsSectionState();
}

class _RankedResultsSectionState extends State<_RankedResultsSection> {
  late final Future<({int rating, int wins, int losses})?> _statsFuture =
      _fetchRankedStats();

  Future<({int rating, int wins, int losses})?> _fetchRankedStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      // Brief delay so server has time to write trophy update
      await Future.delayed(const Duration(milliseconds: 300));
      final doc = await FirebaseFirestore.instance
          .collection('ranked_stats')
          .doc(uid)
          .get();
      if (!doc.exists) return null;
      final d = doc.data() ?? <String, dynamic>{};
      int toInt(Object? v, int def) => v is num ? v.toInt() : def;
      return (
        rating: toInt(d['rating'], 1000),
        wins: toInt(d['wins'], 0),
        losses: toInt(d['losses'], 0),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int rating, int wins, int losses})?>(
      future: _statsFuture,
      builder: (context, snap) {
        final stats = snap.data;
        final tier = stats != null ? rankTierForMmr(stats.rating) : null;

        final theme = widget.theme;
        final ratingDelta = widget.ratingDelta;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.accentPrimary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MMR delta badge (semantic green/red kept as-is)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: ratingDelta > 0
                      ? const Color(0xFF1B5E20).withValues(alpha: 0.5)
                      : const Color(0xFF7F0000).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ratingDelta > 0
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFEF5350),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🏆  Ranked MMR',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      ratingDelta > 0 ? '+$ratingDelta' : '$ratingDelta',
                      style: TextStyle(
                        color: ratingDelta > 0
                            ? const Color(0xFF81C784)
                            : const Color(0xFFEF9A9A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (stats != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tier!.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '${stats.rating} MMR  ·  ${tier.label}',
                      style: TextStyle(
                        color: theme.accentPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'W ${stats.wins}  ·  L ${stats.losses}',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
