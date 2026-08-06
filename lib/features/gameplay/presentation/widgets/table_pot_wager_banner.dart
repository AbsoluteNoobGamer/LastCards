import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme_data.dart';

/// Non-blocking banner card for a mid-game, opt-in, multi-player table-pot
/// wager — the whole-table counterpart to [WagerChallengeBanner]'s 1v1
/// side-bet. Renders one of three states, entirely driven by props:
/// - **locked** — stakes charged: a compact status chip, no buttons.
/// - **pending, [isInitiator]** — the local player proposed it: the joined
///   list so far, a Withdraw button (always enabled), and a Start Wager
///   button (enabled only once at least one other player has joined).
/// - **pending, not initiator** — a Join button if the local player hasn't
///   joined yet, or a Leave button if they have.
class TablePotWagerBanner extends StatelessWidget {
  const TablePotWagerBanner({
    super.key,
    required this.theme,
    required this.stakeCoins,
    required this.initiatorName,
    required this.isInitiator,
    required this.locked,
    required this.joinedNames,
    required this.hasLocalPlayerJoined,
    this.onJoin,
    this.onLeave,
    this.onStart,
    this.onWithdraw,
  });

  final AppThemeData theme;
  final int stakeCoins;
  final String initiatorName;

  /// True when the local player proposed this wager.
  final bool isInitiator;

  /// Stakes have been charged — no more Join/Leave/Start/Withdraw, just a
  /// status chip.
  final bool locked;

  /// Display names of who's in so far — pre-lock, resolved from the
  /// wire's `acceptStatus`; post-lock, resolved from `lockedPlayerIds` (the
  /// actual charged set, which can differ from `acceptStatus` if someone
  /// joined mid-lock-in and was excluded from the charge).
  final List<String> joinedNames;

  /// Whether the local player (a non-initiator) has already joined.
  final bool hasLocalPlayerJoined;

  final VoidCallback? onJoin;
  final VoidCallback? onLeave;
  final VoidCallback? onStart;
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
            'Table wager · ${joinedNames.length} players · $stakeCoins '
            'coins each',
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
    final label = isInitiator ? 'Table wager sent' : 'Table wager open';
    final joinedSummary =
        joinedNames.isEmpty ? 'Nobody has joined yet' : joinedNames.join(', ');
    final detail = isInitiator
        ? '$stakeCoins coins each · $joinedSummary'
        : "$initiatorName's wager · $stakeCoins coins each · $joinedSummary";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
          ],
        ),
        const SizedBox(height: 8),
        if (isInitiator)
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onWithdraw,
                  child: Text(
                    'Withdraw',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton(
                  onPressed: joinedNames.isEmpty ? null : onStart,
                  child: const Text('Start Wager'),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: hasLocalPlayerJoined
                ? OutlinedButton(
                    onPressed: onLeave,
                    child: const Text('Leave'),
                  )
                : FilledButton(
                    onPressed: onJoin,
                    child: const Text('Join'),
                  ),
          ),
      ],
    );
  }
}
