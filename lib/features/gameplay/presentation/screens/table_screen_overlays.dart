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
                            Text(emoji, style: const TextStyle(fontSize: 48)),
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
