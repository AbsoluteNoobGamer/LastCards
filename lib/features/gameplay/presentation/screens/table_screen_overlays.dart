part of 'table_screen.dart';

// ── Win dialog ────────────────────────────────────────────────────────────────

/// Rank tier thresholds (MMR): Bronze < 1100, Silver < 1300, Gold < 1500,
/// Diamond < 1800, Master 1800+
({String label, String emoji}) _rankTierForMmr(int mmr) {
  if (mmr >= 1800) return (label: 'Master', emoji: '👑');
  if (mmr >= 1500) return (label: 'Diamond', emoji: '💎');
  if (mmr >= 1300) return (label: 'Gold', emoji: '🥇');
  if (mmr >= 1100) return (label: 'Silver', emoji: '🥈');
  return (label: 'Bronze', emoji: '🥉');
}

class _WinDialog extends ConsumerWidget {
  const _WinDialog({
    required this.winnerName,
    required this.isLocalWin,
    required this.onPlayAgain,
    this.isOnlineMode = false,
    this.ratingDelta,
  });

  final String winnerName;
  final bool isLocalWin;
  final VoidCallback onPlayAgain;
  final bool isOnlineMode;

  /// Rating change for the local player in a ranked game, or null.
  final int? ratingDelta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final emoji = isLocalWin ? '🎉' : (isOnlineMode ? '👤' : '🤖');
    final headline = isLocalWin ? 'YOU WIN!' : '$winnerName WINS!';
    final sub = isLocalWin
        ? (isOnlineMode
            ? 'You played your last card first!'
            : 'Excellent hand — you beat the Dealer!')
        : (isOnlineMode
            ? '$winnerName played their last card first. Better luck next time!'
            : 'The Dealer played their last card first.');

    return Dialog(
      backgroundColor: theme.surfacePanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
        side: BorderSide(color: theme.accentPrimary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: AppDimensions.md),
            Text(
              headline,
              style: TextStyle(
                color: isLocalWin ? theme.accentPrimary : theme.suitRed,
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
            if (ratingDelta != null) ...[
              const SizedBox(height: AppDimensions.md),
              _RankedResultsSection(
                ratingDelta: ratingDelta!,
                theme: theme,
              ),
            ],
            const SizedBox(height: AppDimensions.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPlayAgain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentPrimary,
                  foregroundColor: theme.backgroundDeep,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppDimensions.md),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusButton),
                  ),
                ),
                child: Text(
                  isOnlineMode ? 'BACK TO MENU' : 'PLAY AGAIN',
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
      ),
    );
  }
}

/// Ranked results section with MMR delta, and fetched stats (MMR, W/L, tier).
class _RankedResultsSection extends StatelessWidget {
  const _RankedResultsSection({
    required this.ratingDelta,
    required this.theme,
  });

  final int ratingDelta;
  final AppThemeData theme;

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
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return (
        rating: (d['rating'] as num?)?.toInt() ?? 1000,
        wins: (d['wins'] as num?)?.toInt() ?? 0,
        losses: (d['losses'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int rating, int wins, int losses})?>(
      future: _fetchRankedStats(),
      builder: (context, snap) {
        final stats = snap.data;
        final tier = stats != null ? _rankTierForMmr(stats.rating) : null;

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
