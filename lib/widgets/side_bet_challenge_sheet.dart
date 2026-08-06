import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_dimensions.dart';
import '../core/theme/app_theme_data.dart';

/// Bottom sheet collecting a stake amount to send either a targeted 1v1
/// side-bet challenge ([targetName] set) or an untargeted mid-game table-pot
/// proposal ([targetName] null — open to whoever wants to join). The 1v1
/// case never blocks the rest of the table — settlement is independent of
/// the overall match result, decided by whichever of the two participants
/// has fewer cards left when the match ends. The table-pot case settles
/// winner-take-all among joiners by overall match result.
///
/// Shared between the pre-game lobby (challenge a seated player before the
/// match starts) and the in-match table screen (challenge an opponent, or
/// propose a table-pot, while the match is already running).
class SideBetChallengeSheet extends StatefulWidget {
  const SideBetChallengeSheet({
    super.key,
    required this.theme,
    required this.onConfirm,
    this.targetName,
    this.title,
    this.subtitle,
  });

  final AppThemeData theme;
  final ValueChanged<int> onConfirm;

  /// The challenged opponent's display name. Null for an untargeted
  /// table-pot proposal.
  final String? targetName;

  /// Overrides the default heading — needed for the table-pot case, which
  /// has no single target name to build a "CHALLENGE X" heading from.
  final String? title;

  /// Overrides the default explanatory copy — lets mid-game callers use
  /// slightly different wording than the pre-game lobby.
  final String? subtitle;

  @override
  State<SideBetChallengeSheet> createState() => _SideBetChallengeSheetState();
}

class _SideBetChallengeSheetState extends State<SideBetChallengeSheet> {
  final _stakeController = TextEditingController(text: '10');

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Padding(
      padding: EdgeInsets.only(
        left: AppDimensions.lg,
        right: AppDimensions.lg,
        top: AppDimensions.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimensions.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ??
                'CHALLENGE ${(widget.targetName ?? '').toUpperCase()}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: theme.accentLight,
            ),
          ),
          const SizedBox(height: AppDimensions.xs),
          Text(
            widget.subtitle ??
                (widget.targetName != null
                    ? 'Whoever has fewer cards left when the match ends '
                        'wins the pot. ${widget.targetName} must accept '
                        'before it counts.'
                    : 'Set a stake for the whole table. Other players can '
                        'join before you start it — winner takes the pot.'),
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.35,
              color: theme.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimensions.md),
          TextField(
            controller: _stakeController,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: GoogleFonts.inter(
              color: theme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(
                Icons.monetization_on_rounded,
                color: theme.accentPrimary,
                size: 20,
              ),
              hintText: 'Stake (coins)',
              hintStyle: GoogleFonts.inter(color: theme.textSecondary),
              filled: true,
              fillColor: theme.surfacePanel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
                borderSide: BorderSide(
                  color: theme.accentDark.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final v = int.tryParse(_stakeController.text.trim());
                if (v != null && v > 0) widget.onConfirm(v);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentPrimary,
                foregroundColor: theme.backgroundDeep,
                minimumSize: const Size(0, AppDimensions.minTouchTarget + 2),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusModal),
                ),
              ),
              child: Text(
                widget.targetName != null ? 'SEND CHALLENGE' : 'PROPOSE WAGER',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
