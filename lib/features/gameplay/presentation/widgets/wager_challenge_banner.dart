import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Non-blocking banner card for the current table's side-bet wager state.
///
/// Renders one of three states, entirely driven by props:
/// - **incoming** — the local player is the challenged target of an
///   unlocked proposal: Accept / Decline buttons.
/// - **outgoing** — the local player sent the (still unlocked) proposal:
///   a Withdraw button, the manual escape hatch for a challenge nobody's
///   answered yet.
/// - **active** — the wager is locked in (stakes charged): a compact,
///   button-less status chip.
///
/// Shared between the pre-game lobby and the in-match table screen — both
/// surfaces can have an active side-bet proposal or lock-in in flight.
class WagerChallengeBanner extends StatelessWidget {
  const WagerChallengeBanner({
    super.key,
    required this.theme,
    required this.opponentName,
    required this.stakeCoins,
    required this.locked,
    required this.isInitiator,
    this.onAccept,
    this.onDecline,
    this.onWithdraw,
  });

  final AppThemeData theme;
  final String opponentName;
  final int stakeCoins;

  /// Stakes have been charged — no more Accept/Decline/Withdraw, just a
  /// status chip.
  final bool locked;

  /// True when the local player sent the challenge (outgoing); false when
  /// the local player is the challenged target (incoming). Ignored once
  /// [locked] is true.
  final bool isInitiator;

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: theme.surfacePanel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: locked ? _buildActive() : _buildPending(),
        ),
      ),
    );
  }

  Widget _buildActive() {
    return Row(
      children: [
        Icon(Icons.monetization_on_rounded,
            color: theme.accentPrimary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Side bet vs $opponentName · $stakeCoins coins',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.accentPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPending() {
    final label = isInitiator ? 'Side bet sent' : 'Side bet challenge';
    final detail = isInitiator
        ? 'Waiting for $opponentName to accept · $stakeCoins coins'
        : '$opponentName wagered $stakeCoins coins';
    return Row(
      children: [
        Icon(Icons.monetization_on_rounded,
            color: theme.accentPrimary, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: theme.textSecondary,
                ),
              ),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.accentPrimary,
                ),
              ),
            ],
          ),
        ),
        if (isInitiator)
          TextButton(
            onPressed: onWithdraw,
            child: Text(
              'Withdraw',
              style: TextStyle(color: theme.textSecondary),
            ),
          )
        else ...[
          TextButton(
            onPressed: onDecline,
            child: Text(
              'Decline',
              style: TextStyle(color: theme.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onAccept,
            child: const Text('Accept'),
          ),
        ],
      ],
    );
  }
}
