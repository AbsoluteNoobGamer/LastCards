part of 'table_screen.dart';

// ── Win dialog ────────────────────────────────────────────────────────────────

class _WinDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
      backgroundColor: AppColors.feltMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
        side: const BorderSide(color: AppColors.goldPrimary, width: 2),
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
                color: isLocalWin ? AppColors.goldPrimary : AppColors.redSoft,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: AppDimensions.sm),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (ratingDelta != null) ...[
              const SizedBox(height: AppDimensions.md),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: ratingDelta! > 0
                      ? const Color(0xFF1B5E20).withValues(alpha: 0.5)
                      : const Color(0xFF7F0000).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ratingDelta! > 0
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
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      ratingDelta! > 0 ? '+$ratingDelta' : '$ratingDelta',
                      style: TextStyle(
                        color: ratingDelta! > 0
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
            ],
            const SizedBox(height: AppDimensions.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPlayAgain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldPrimary,
                  foregroundColor: AppColors.feltDeep,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppDimensions.md),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusButton),
                  ),
                ),
                child: Text(
                  isOnlineMode ? 'BACK TO MENU' : 'PLAY AGAIN',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 15,
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
