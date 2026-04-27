import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/providers/user_profile_provider.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/core/theme/app_typography.dart';
import 'package:last_cards/core/monetization/post_game_interstitial.dart';

import '../../leaderboard/data/leaderboard_stats_writer.dart';

import '../models/bust_round_state.dart';

/// Shown when a Bust game is completely finished — one player remains —
/// or when the local player is eliminated mid-tournament.
///
/// - When [localEliminated] is true: shows a personal round-by-round journey.
/// - Otherwise: shows the full placement-based leaderboard.
class BustWinnerScreen extends ConsumerStatefulWidget {
  const BustWinnerScreen({
    super.key,
    required this.winnerId,
    required this.winnerName,
    required this.totalRounds,
    required this.playerNames,
    required this.eliminationHistory,
    required this.localRoundStats,
    this.localEliminated = false,
  });

  final String winnerId;
  final String winnerName;
  final int totalRounds;

  /// Display names for current-round survivors (for winner label).
  final Map<String, String> playerNames;

  /// Placement records for every non-winner player, ordered by
  /// round eliminated (accumulated across all rounds).
  final List<BustEliminationRecord> eliminationHistory;

  /// Per-round performance stats for the local human player.
  final List<BustLocalRoundStat> localRoundStats;

  /// True when the local player was knocked out before the final round.
  final bool localEliminated;

  bool get _localWon =>
      !localEliminated &&
      winnerId.isNotEmpty &&
      winnerId == OfflineGameState.localId;

  // ── Leaderboard (used when local player won or AI won) ─────────────────────

  List<_PlacementEntry> _buildLeaderboard() {
    final sorted = List<BustEliminationRecord>.from(eliminationHistory)
      ..sort((a, b) {
        if (b.roundEliminated != a.roundEliminated) {
          return b.roundEliminated.compareTo(a.roundEliminated);
        }
        return a.cardsAtElimination.compareTo(b.cardsAtElimination);
      });

    final entries = <_PlacementEntry>[];

    if (winnerId.isNotEmpty) {
      entries.add(_PlacementEntry(
        position: 1,
        playerName: winnerName.isEmpty ? 'Winner' : winnerName,
        subtitle: 'Winner — survived all $totalRounds rounds',
        isWinner: true,
        isLocal: _localWon,
      ));
    }

    for (var i = 0; i < sorted.length; i++) {
      final rec = sorted[i];
      entries.add(_PlacementEntry(
        position: entries.length + 1,
        playerName: rec.playerName,
        subtitle: 'Eliminated — Round ${rec.roundEliminated}',
        isWinner: false,
        isLocal: rec.isLocal,
      ));
    }

    return entries;
  }

  @override
  ConsumerState<BustWinnerScreen> createState() => _BustWinnerScreenState();
}

class _BustWinnerScreenState extends ConsumerState<BustWinnerScreen> {
  bool _recorded = false;

  Future<void> _recordOnce() async {
    if (_recorded) return;
    _recorded = true;

    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid == null) return;

    final localWon = widget._localWon;

    final profileName = ref.read(displayNameForGameProvider);
    final displayName =
        widget.playerNames['player-local'] ?? profileName;

    await LeaderboardStatsWriter.instance.recordModeResult(
      collectionName: 'leaderboard_bust_offline',
      uid: firebaseUid,
      displayName: displayName,
      deltaWins: localWon ? 1 : 0,
      deltaLosses: localWon ? 0 : 1,
      deltaGamesPlayed: 1,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recordOnce());
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return _build(context, ref);
  }

  Widget _build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    // Mirror widget fields locally so the rest of the UI code can stay
    // unchanged while we move from ConsumerWidget → ConsumerStatefulWidget.
    final localWon = widget._localWon;
    final localEliminated = widget.localEliminated;
    final winnerName = widget.winnerName;
    final totalRounds = widget.totalRounds;
    final localRoundStats = widget.localRoundStats;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppDimensions.lg * 2),

            // Hero icon
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: localWon
                    ? AppColors.goldPrimary.withValues(alpha: 0.15)
                    : AppColors.redAccent.withValues(alpha: 0.12),
                border: Border.all(
                  color:
                      localWon ? AppColors.goldPrimary : AppColors.redAccent,
                  width: 2.5,
                ),
              ),
              child: Icon(
                localWon
                    ? Icons.emoji_events_rounded
                    : localEliminated
                        ? Icons.cancel_rounded
                        : Icons.sentiment_dissatisfied_rounded,
                size: 52,
                color: localWon ? AppColors.goldPrimary : AppColors.redAccent,
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Title
            Text(
              localWon
                  ? 'You Won!'
                  : localEliminated
                      ? 'You\'re Eliminated!'
                      : '${winnerName.isEmpty ? 'Someone' : winnerName} Wins!',
              style: GoogleFonts.cinzel(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: localWon ? AppColors.goldPrimary : theme.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: AppDimensions.xs),
            Text(
              localWon
                  ? 'Congratulations — you survived all $totalRounds rounds!'
                  : localEliminated
                      ? 'Better luck next time. Here\'s how you did:'
                      : 'Game finished after $totalRounds rounds.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.lg),

            // Body — personal journey OR leaderboard
            Expanded(
              child: localEliminated
                  ? _PersonalJourney(
                      stats: localRoundStats,
                      totalRounds: totalRounds,
                      theme: theme,
                    )
                  : _Leaderboard(
                      entries: widget._buildLeaderboard(),
                      theme: theme,
                    ),
            ),

            const SizedBox(height: AppDimensions.md),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref
                            .read(postGameInterstitialProvider.notifier)
                            .markCompletedPlaySession();
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppDimensions.md),
                        side: BorderSide(
                            color:
                                theme.accentDark.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Main Menu',
                        style: AppTypography.buttonSecondary
                            .copyWith(color: theme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ref
                            .read(postGameInterstitialProvider.notifier)
                            .markCompletedPlaySession();
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: localWon
                            ? AppColors.goldPrimary
                            : theme.accentPrimary,
                        foregroundColor: theme.backgroundDeep,
                        padding: const EdgeInsets.symmetric(
                            vertical: AppDimensions.md),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        localEliminated ? 'Try Again' : 'Play Again',
                        style: AppTypography.buttonPrimary
                            .copyWith(color: theme.backgroundDeep),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),
          ],
        ),
      ),
    );
  }
}

// ── Personal journey (shown when local player is eliminated) ──────────────────

class _PersonalJourney extends StatelessWidget {
  const _PersonalJourney({
    required this.stats,
    required this.totalRounds,
    required this.theme,
  });

  final List<BustLocalRoundStat> stats;
  final int totalRounds;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return Center(
        child: Text(
          'No round data available.',
          style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
        ),
      );
    }

    final totalShed = stats.fold<int>(0, (sum, s) => sum + s.cardsShed);
    final totalRemaining =
        stats.fold<int>(0, (sum, s) => sum + s.cardsRemaining);
    final roundsSurvived = stats.where((s) => s.survived).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary chips
          Row(
            children: [
              _SummaryChip(
                label: 'Rounds passed',
                value: '$roundsSurvived',
                icon: Icons.check_circle_outline_rounded,
                color: theme.accentPrimary,
                theme: theme,
              ),
              const SizedBox(width: AppDimensions.sm),
              _SummaryChip(
                label: 'Total cards shed',
                value: '$totalShed',
                icon: Icons.style_rounded,
                color: AppColors.goldPrimary,
                theme: theme,
              ),
              const SizedBox(width: AppDimensions.sm),
              _SummaryChip(
                label: 'Cards in hand total',
                value: '$totalRemaining',
                icon: Icons.front_hand_rounded,
                color: AppColors.redAccent,
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.md),

          Text(
            'Round by Round',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppDimensions.sm),

          Expanded(
            child: ListView.separated(
              itemCount: stats.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppDimensions.xs),
              itemBuilder: (_, i) => _RoundStatRow(
                stat: stats[i],
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: theme.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundStatRow extends StatelessWidget {
  const _RoundStatRow({required this.stat, required this.theme});

  final BustLocalRoundStat stat;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        stat.survived ? theme.accentPrimary : AppColors.redAccent;
    final Color bg = stat.survived
        ? theme.accentPrimary.withValues(alpha: 0.07)
        : AppColors.redAccent.withValues(alpha: 0.07);
    final Color border = stat.survived
        ? theme.accentPrimary.withValues(alpha: 0.25)
        : AppColors.redAccent.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          // Round badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                'R${stat.roundNumber}',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Status label
          Expanded(
            child: Text(
              stat.survived ? 'Survived' : 'Eliminated',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),

          // Cards shed
          _StatPill(
            icon: Icons.style_rounded,
            value: '${stat.cardsShed} shed',
            color: AppColors.goldPrimary,
            theme: theme,
          ),
          const SizedBox(width: 6),

          // Cards remaining
          _StatPill(
            icon: Icons.front_hand_rounded,
            value: '${stat.cardsRemaining} left',
            color: AppColors.redAccent,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final Color color;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard (shown when local player won or AI won) ───────────────────────

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.entries, required this.theme});

  final List<_PlacementEntry> entries;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Final Standings',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppDimensions.sm),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppDimensions.xs),
              itemBuilder: (_, index) => _PlacementRow(
                entry: entries[index],
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Placement entry model ──────────────────────────────────────────────────────

class _PlacementEntry {
  const _PlacementEntry({
    required this.position,
    required this.playerName,
    required this.subtitle,
    required this.isWinner,
    required this.isLocal,
  });

  final int position;
  final String playerName;
  final String subtitle;
  final bool isWinner;
  final bool isLocal;
}

// ── Placement row widget ───────────────────────────────────────────────────────

class _PlacementRow extends StatelessWidget {
  const _PlacementRow({required this.entry, required this.theme});

  final _PlacementEntry entry;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final Color accent = entry.isWinner
        ? AppColors.goldPrimary
        : entry.isLocal
            ? AppColors.redAccent
            : theme.textPrimary;

    final Color bgColor = entry.isWinner
        ? AppColors.goldPrimary.withValues(alpha: 0.10)
        : entry.isLocal
            ? AppColors.redAccent.withValues(alpha: 0.07)
            : theme.backgroundMid;

    final Color borderColor = entry.isWinner
        ? AppColors.goldPrimary.withValues(alpha: 0.40)
        : entry.isLocal
            ? AppColors.redAccent.withValues(alpha: 0.25)
            : theme.accentDark.withValues(alpha: 0.20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: entry.isWinner
                ? Icon(Icons.emoji_events_rounded,
                    color: AppColors.goldPrimary, size: 20)
                : Text(
                    '#${entry.position}',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.playerName,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight:
                        entry.isWinner ? FontWeight.w700 : FontWeight.w500,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  entry.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: accent.withValues(
                        alpha: entry.isWinner ? 0.70 : 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
