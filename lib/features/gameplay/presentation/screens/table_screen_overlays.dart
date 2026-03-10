part of 'table_screen.dart';

// ── Win dialog ────────────────────────────────────────────────────────────────

class _WinDialog extends StatelessWidget {
  const _WinDialog({
    required this.winnerName,
    required this.isLocalWin,
    required this.onPlayAgain,
    this.isOnlineMode = false,
  });

  final String winnerName;
  final bool isLocalWin;
  final VoidCallback onPlayAgain;
  final bool isOnlineMode;

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
