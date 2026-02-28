part of 'table_screen.dart';

// ── Offline mode banner ───────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onBack, required this.aiThinking, this.onProfile});
  final VoidCallback onBack;
  final bool aiThinking;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.md,
        vertical: AppDimensions.xs + 2,
      ),
      color: AppColors.goldDark.withValues(alpha: 0.88),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.arrow_back_ios,
                size: 16, color: AppColors.feltDeep),
          ),
          const SizedBox(width: AppDimensions.sm),
          Expanded(
            child: Text(
              aiThinking
                  ? '⏳  Player 2 is thinking…'
                  : 'OFFLINE — follow suit or rank to play',
              style: TextStyle(
                color: AppColors.feltDeep,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontStyle: aiThinking ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          Text(
            aiThinking ? '' : 'vs Player 2 (AI)  🤖',
            style: const TextStyle(
              color: AppColors.feltDeep,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: AppDimensions.xs),
          GestureDetector(
            onTap: onProfile,
            child: const Icon(Icons.person_rounded,
                size: 20, color: AppColors.feltDeep),
          ),
        ],
      ),
    );
  }
}


// ── Win dialog ────────────────────────────────────────────────────────────────

class _WinDialog extends StatelessWidget {
  const _WinDialog({
    required this.winnerName,
    required this.isLocalWin,
    required this.onPlayAgain,
  });

  final String winnerName;
  final bool isLocalWin;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final emoji = isLocalWin ? '🎉' : '🤖';
    final headline = isLocalWin ? 'YOU WIN!' : '$winnerName WINS!';
    final sub = isLocalWin
        ? 'Excellent hand — you beat the Dealer!'
        : 'The Dealer played their last card first.';

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
                child: const Text(
                  'PLAY AGAIN',
                  style: TextStyle(
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
