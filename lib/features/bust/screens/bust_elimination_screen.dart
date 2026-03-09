import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:last_cards/core/models/ai_player_config.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/theme/app_colors.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';

import '../models/bust_round_state.dart';
import 'bust_game_screen.dart' show BustGameScreen, BustResumeState;
import 'bust_winner_screen.dart';

/// Shown between rounds.
///
/// Displays who was eliminated this round, the current standings with
/// cumulative penalty totals, and the progression path.
/// - If [result.isGameOver]: navigates to [BustWinnerScreen].
/// - Otherwise: starts a new [BustGameScreen] for the survivors.
class BustEliminationScreen extends ConsumerWidget {
  const BustEliminationScreen({
    super.key,
    required this.result,
    required this.playerNames,
    required this.aiConfigs,
    required this.eliminationHistory,
    required this.localRoundStats,
  });

  final BustRoundResult result;
  final Map<String, String> playerNames;
  final List<AiPlayerConfig> aiConfigs;

  /// Placement records for every player eliminated in previous rounds.
  /// This screen appends the current round's eliminations and passes the
  /// updated list forward (or to [BustWinnerScreen] at game end).
  final List<BustEliminationRecord> eliminationHistory;

  /// Per-round performance stats for the local human player (already includes
  /// the stat for the round that just finished, built in [BustGameScreen]).
  final List<BustLocalRoundStat> localRoundStats;

  /// True when the local human player was eliminated this round.
  bool get _localEliminated =>
      result.eliminatedThisRound.contains(OfflineGameState.localId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final localEliminated = _localEliminated;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppDimensions.lg),

            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimensions.md),
              child: Column(
                children: [
                  Text(
                    'Round ${result.roundNumber} Complete',
                    style: GoogleFonts.cinzel(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: theme.accentPrimary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xs),
                  Text(
                    result.eliminatedThisRound.length == 1
                        ? '1 player eliminated'
                        : '${result.eliminatedThisRound.length} players eliminated',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Eliminated players banner
            if (result.eliminatedThisRound.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.md),
                child: Container(
                  padding: const EdgeInsets.all(AppDimensions.md),
                  decoration: BoxDecoration(
                    color: AppColors.redAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cancel_rounded,
                              color: AppColors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'ELIMINATED',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.redAccent,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      ...result.eliminatedThisRound.map(
                        (id) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppDimensions.xs),
                          child: Row(
                            children: [
                              const SizedBox(width: 26),
                              Expanded(
                                child: Text(
                                  playerNames[id] ?? id,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.redAccent,
                                  ),
                                ),
                              ),
                              Text(
                                '+${result.cumulativePenalties[id] ?? 0} pts',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: AppColors.redAccent
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppDimensions.md),

            // Standings
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Standings',
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
                        itemCount: result.standingsThisRound.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppDimensions.xs),
                        itemBuilder: (_, index) {
                          final entry = result.standingsThisRound[index];
                          final isEliminated = result.eliminatedThisRound
                              .contains(entry.playerId);
                          final isWinner = result.isGameOver &&
                              result.winnerId == entry.playerId;

                          return _StandingRow(
                            position: index + 1,
                            playerName: entry.playerName,
                            cardsThisRound: entry.cardsThisRound,
                            totalPenalty: entry.totalPenalty,
                            isEliminated: isEliminated,
                            isWinner: isWinner,
                            theme: theme,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppDimensions.md),

            // Progression indicator
            if (!result.isGameOver)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.md),
                child: _ProgressionBar(
                  survivorCount: result.survivorIds.length,
                  theme: theme,
                ),
              ),
            const SizedBox(height: AppDimensions.md),

            // CTA
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.md),
              child: _CtaButton(
                isGameOver: result.isGameOver,
                localEliminated: localEliminated,
                onTap: () => _onContinue(context, localEliminated),
                theme: theme,
              ),
            ),
            const SizedBox(height: AppDimensions.lg),
          ],
        ),
      ),
    );
  }

  /// Builds [BustEliminationRecord]s for every player knocked out this round,
  /// and — when the game is over — the runner-up as well.
  List<BustEliminationRecord> _buildUpdatedHistory({bool includeRunnerUp = false}) {
    final cardsByPlayer = {
      for (final s in result.standingsThisRound)
        s.playerId: s.cardsThisRound,
    };

    // Players eliminated this round
    final newRecords = result.eliminatedThisRound.map((id) {
      return BustEliminationRecord(
        playerName: playerNames[id] ?? id,
        roundEliminated: result.roundNumber,
        cardsAtElimination: cardsByPlayer[id] ?? 0,
        isLocal: id == OfflineGameState.localId,
      );
    }).toList();

    // When game is over, also record the runner-up (non-winner survivor)
    if (includeRunnerUp) {
      for (final id in result.survivorIds) {
        if (id != result.winnerId) {
          newRecords.add(BustEliminationRecord(
            playerName: playerNames[id] ?? id,
            roundEliminated: result.roundNumber,
            cardsAtElimination: cardsByPlayer[id] ?? 0,
            isLocal: id == OfflineGameState.localId,
          ));
        }
      }
    }

    return [...eliminationHistory, ...newRecords];
  }

  void _onContinue(BuildContext context, bool localEliminated) {
    if (result.isGameOver || localEliminated) {
      final updatedHistory = _buildUpdatedHistory(
        includeRunnerUp: result.isGameOver,
      );
      final winnerId = result.winnerId ?? '';

      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => BustWinnerScreen(
          winnerId: winnerId,
          winnerName: playerNames[winnerId] ?? '',
          totalRounds: result.roundNumber,
          playerNames: playerNames,
          eliminationHistory: updatedHistory,
          localEliminated: localEliminated && !result.isGameOver,
          localRoundStats: localRoundStats,
        ),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ));
    } else {
      // Local player survived — continue to the next round.
      final updatedHistory = _buildUpdatedHistory();

      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => BustGameScreen(
          totalPlayers: result.survivorIds.length,
          resumeState: BustResumeState(
            roundNumber: result.roundNumber + 1,
            survivorIds: result.survivorIds,
            playerNames: playerNames,
            allEliminatedIds: [
              ...result.cumulativePenalties.keys
                  .where((id) => !result.survivorIds.contains(id)),
            ],
            aiConfigs: aiConfigs,
            eliminationHistory: updatedHistory,
            localRoundStats: localRoundStats,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ));
    }
  }
}

// ── Standing row ──────────────────────────────────────────────────────────────

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.position,
    required this.playerName,
    required this.cardsThisRound,
    required this.totalPenalty,
    required this.isEliminated,
    required this.isWinner,
    required this.theme,
  });

  final int position;
  final String playerName;
  final int cardsThisRound;
  final int totalPenalty;
  final bool isEliminated;
  final bool isWinner;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final Color rowColor = isWinner
        ? AppColors.goldPrimary
        : isEliminated
            ? AppColors.redAccent
            : theme.textPrimary;

    final Color bgColor = isWinner
        ? AppColors.goldPrimary.withValues(alpha: 0.10)
        : isEliminated
            ? AppColors.redAccent.withValues(alpha: 0.07)
            : theme.backgroundMid;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner
              ? AppColors.goldPrimary.withValues(alpha: 0.4)
              : isEliminated
                  ? AppColors.redAccent.withValues(alpha: 0.25)
                  : theme.accentDark.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$position',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: rowColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (isWinner)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.emoji_events_rounded,
                  color: AppColors.goldPrimary, size: 16),
            )
          else if (isEliminated)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.cancel_rounded,
                  color: AppColors.redAccent, size: 16),
            )
          else
            const SizedBox(width: 22),
          Expanded(
            child: Text(
              playerName,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: rowColor,
              ),
            ),
          ),
          Text(
            '+$cardsThisRound',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: cardsThisRound > 0
                  ? AppColors.redAccent.withValues(alpha: 0.85)
                  : theme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$totalPenalty pts',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: rowColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Progression bar ───────────────────────────────────────────────────────────

class _ProgressionBar extends StatelessWidget {
  const _ProgressionBar({
    required this.survivorCount,
    required this.theme,
  });

  final int survivorCount;
  final dynamic theme;

  static const _steps = [10, 8, 6, 4, 2];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.backgroundMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.accentDark.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: _steps.map((count) {
          final isActive = count == survivorCount;
          final isPast = count > survivorCount;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? theme.accentPrimary
                      : isPast
                          ? theme.accentPrimary.withValues(alpha: 0.25)
                          : theme.backgroundDeep,
                  border: Border.all(
                    color: isActive
                        ? theme.accentPrimary
                        : theme.accentDark.withValues(alpha: 0.3),
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? theme.backgroundDeep
                          : theme.textSecondary
                              .withValues(alpha: isPast ? 0.5 : 0.35),
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── CTA button ────────────────────────────────────────────────────────────────

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.isGameOver,
    required this.localEliminated,
    required this.onTap,
    required this.theme,
  });

  final bool isGameOver;
  final bool localEliminated;
  final VoidCallback onTap;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = (isGameOver || localEliminated)
        ? AppColors.goldPrimary
        : theme.accentPrimary;

    final IconData icon = isGameOver
        ? Icons.emoji_events_rounded
        : localEliminated
            ? Icons.exit_to_app_rounded
            : Icons.play_arrow_rounded;

    final String label = isGameOver
        ? 'See Winner'
        : localEliminated
            ? 'You\'re Out — See Results'
            : 'Next Round';

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: theme.backgroundDeep,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
