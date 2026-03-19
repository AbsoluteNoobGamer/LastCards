import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/offline_game_state.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../services/audio_service.dart';
import '../../../../services/game_sound.dart';
import '../../../../tournament/tournament_engine.dart';
import '../../../../tournament/tournament_table_id_mapping.dart';
import '../../gameplay/presentation/screens/table_screen.dart';
import '../../single_player/providers/single_player_session_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../leaderboard/data/leaderboard_stats_writer.dart';
import '../providers/tournament_session_provider.dart';
import 'elimination_screen.dart';
import 'round_summary_screen.dart';
import 'tournament_lobby_screen.dart';
import 'waiting_screen.dart';
import 'winner_screen.dart';

/// Builds the round game widget (default: [TableScreen]).
/// Used for dependency injection and tests.
/// [activePlayerIds] is the engine's current round player IDs (for tests that
/// need to report finish order using the same IDs the engine expects).
typedef TournamentRoundGameBuilder = Widget Function({
  required int totalPlayers,
  required bool isTournamentMode,
  required void Function(String playerId, int finishPosition) onPlayerFinished,
  required Map<String, String> tournamentPlayerNameByTableId,
  required List<String> activePlayerIds,
  AiDifficulty? aiDifficulty,
});

/// Unified coordinator that runs the tournament loop.
///
/// Single entry point for both offline (vs AI) and online flows.
/// Flow: [WaitingScreen] → TableScreen → [EliminationScreen] → [RoundSummaryScreen] → repeat → [WinnerScreen].
class TournamentCoordinator extends ConsumerStatefulWidget {
  const TournamentCoordinator({
    this.roundGameBuilder = _defaultRoundGameBuilder,
    this.onRoundSummaryShown,
    this.isOnline = false,
    this.onlineLocalDisplayName = 'You',
    this.showStartButton = false,
    this.playerCount,
    this.aiDifficulty,
    super.key,
  });

  /// Custom round game builder (for tests).
  final TournamentRoundGameBuilder roundGameBuilder;

  /// Called when round summary is shown (for tests).
  final void Function(TournamentRoundResult result)? onRoundSummaryShown;

  /// Whether this is an online tournament.
  final bool isOnline;

  /// Local player display name for online.
  final String onlineLocalDisplayName;

  /// If true, show "Start Tournament" button and wait for tap.
  /// Used by online flow (legacy) and tests. If false, auto-starts.
  final bool showStartButton;

  /// Player count for offline. If null, uses [TournamentSessionState.playerCount].
  final int? playerCount;

  /// AI difficulty for vs AI. If null, uses [TournamentSessionState.difficulty].
  final AiDifficulty? aiDifficulty;

  static Widget _defaultRoundGameBuilder({
    required int totalPlayers,
    required bool isTournamentMode,
    required void Function(String playerId, int finishPosition)
        onPlayerFinished,
    required Map<String, String> tournamentPlayerNameByTableId,
    required List<String> activePlayerIds,
    AiDifficulty? aiDifficulty,
  }) {
    return TableScreen(
      totalPlayers: totalPlayers,
      isTournamentMode: isTournamentMode,
      onPlayerFinished: onPlayerFinished,
      tournamentPlayerNameByTableId: tournamentPlayerNameByTableId,
      aiDifficulty: aiDifficulty,
    );
  }

  @override
  ConsumerState<TournamentCoordinator> createState() =>
      _TournamentCoordinatorState();
}

class _TournamentCoordinatorState extends ConsumerState<TournamentCoordinator> {
  late final TournamentEngine _engine;
  bool _hasStarted = false;
  bool _isDisposed = false;
  bool _tournamentLeaderboardRecorded = false;

  /// Copy of [_engine.activePlayerIds] taken when the table route is opened.
  /// After [_engine] completes a round it shrinks this list immediately, but
  /// [TableScreen] still has the full seat layout until it pops — mapping
  /// `player-2`… with the shrunk list breaks (e.g. `player-3` → out of range)
  /// and [recordPlayerFinished] is ignored, freezing the round.
  List<String>? _enginePlayerIdsForCurrentTable;

  @override
  void initState() {
    super.initState();
    _engine = _buildEngine();
    if (!widget.showStartButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasStarted && !_isDisposed) {
          _onStartTournament();
        }
      });
    }
  }

  TournamentEngine _buildEngine() {
    if (widget.isOnline) {
      return TournamentEngine.online(
        players: [
          TournamentPlayer(
            id: OfflineGameState.localId,
            displayName: widget.onlineLocalDisplayName,
            isAi: false,
          ),
          const TournamentPlayer(
            id: 'online-player-2',
            displayName: 'Player 2',
            isAi: false,
          ),
          const TournamentPlayer(
            id: 'online-player-3',
            displayName: 'Player 3',
            isAi: false,
          ),
          const TournamentPlayer(
            id: 'online-player-4',
            displayName: 'Player 4',
            isAi: false,
          ),
        ],
      );
    }
    final playerCount =
        widget.playerCount ?? ref.read(tournamentSessionProvider).playerCount ?? 4;
    return TournamentEngine.offline(
      players: const [
        TournamentPlayer(
          id: OfflineGameState.localId,
          displayName: 'You',
          isAi: false,
        ),
      ],
      requiredPlayers: playerCount,
    );
  }

  AiDifficulty? get _aiDifficulty =>
      widget.aiDifficulty ?? ref.read(tournamentSessionProvider).difficulty;

  @override
  void dispose() {
    _isDisposed = true;
    _engine.dispose();
    super.dispose();
  }

  void _onStartTournament() {
    if (_hasStarted) return;
    _hasStarted = true;
    _engine.startTournament();
    _runTournamentLoop();
  }

  /// Waits for two frames so route disposal (summary → engine advance) cannot
  /// race the next [Navigator.push] (round-3 waiting was failing intermittently).
  Future<void> _waitForUiSettled() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });
    });
    return completer.future;
  }

  Future<void> _runTournamentLoop() async {
    while (mounted && !_isDisposed && !_engine.isComplete) {
      final expectedRound = _engine.currentRound;
      final playersInRound = _engine.activePlayerIds.length;
      final activeIdsAtRoundStart = List<String>.from(_engine.activePlayerIds);
      final nameByTableId = _buildTournamentNamesByTableId(_engine.activePlayerIds);

      // Waiting screen before each round
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => TournamentWaitingScreen(
            roundNumber: _engine.currentRound,
            players: _engine.activePlayerIds.map(_displayName).toList(),
          ),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      if (!mounted || _isDisposed) return;

      // Round game — freeze fix: snapshot ids for the whole table session (see
      // [_enginePlayerIdsForCurrentTable]).
      _enginePlayerIdsForCurrentTable = List<String>.from(activeIdsAtRoundStart);
      final roundResult = await Navigator.push<TournamentRoundGameResult>(
        context,
        MaterialPageRoute(
          builder: (_) => widget.roundGameBuilder(
            totalPlayers: playersInRound,
            isTournamentMode: true,
            onPlayerFinished: _onPlayerFinished,
            tournamentPlayerNameByTableId: nameByTableId,
            activePlayerIds: _enginePlayerIdsForCurrentTable!,
            aiDifficulty: widget.isOnline ? null : _aiDifficulty,
          ),
        ),
      );
      _enginePlayerIdsForCurrentTable = null;
      if (!mounted || _isDisposed) return;
      if (roundResult != null) {
        // Defensive reconciliation: table can report finish IDs while the engine
        // missed one callback due to route/frame timing. Replaying ensures the
        // expected round result exists before we navigate onward.
        for (var i = 0; i < roundResult.finishedPlayerIds.length; i++) {
          final reportedId = roundResult.finishedPlayerIds[i];
          final engineId = resolveTournamentTableIdToEnginePlayerId(
            reportedId: reportedId,
            activePlayerIds: activeIdsAtRoundStart,
          );
          if (_engine.finishingPositionFor(
                roundNumber: expectedRound,
                playerId: engineId,
              ) !=
              null) {
            continue;
          }
          _engine.recordPlayerFinished(engineId, finishPosition: i + 1);
        }
      }

      final round = _engine.roundResults
          .where((r) => r.roundNumber == expectedRound)
          .firstOrNull;
      if (round == null) {
        // Recovery path for larger brackets: if a table route exits without a
        // result payload, don't dead-end on coordinator loading. Either the
        // tournament is complete, or we restart loop navigation for this/next
        // round instead of returning permanently.
        if (_engine.isComplete) break;
        await _waitForUiSettled();
        if (!mounted || _isDisposed) return;
        continue;
      }

      // Table route may pop on the next frame; let it dispose before pushing
      // Elimination (another Consumer route) to avoid InheritedWidget races.
      await _waitForUiSettled();
      if (!mounted || _isDisposed) return;

      // Elimination screen
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TournamentEliminationScreen(
            eliminatedPlayer: _displayName(round.eliminatedPlayerId),
            remainingPlayers: _namesForIds(round.advancedPlayerIds),
            roundNumber: round.roundNumber,
          ),
        ),
      );
      if (!mounted || _isDisposed) return;

      if (!_engine.isComplete) {
        // If you were eliminated this round, don't let the loop advance you into
        // the next round (spectating/playing after elimination was the bug).
        if (round.eliminatedPlayerId == OfflineGameState.localId) {
          if (!_tournamentLeaderboardRecorded) {
            _tournamentLeaderboardRecorded = true;
            final uid = FirebaseAuth.instance.currentUser?.uid ??
                OfflineGameState.localId;
            // Firestore `leaderboard_tournament_online` is server-only; this
            // updates local cache only for instant UI until online tournaments
            // are driven by the game server.
            final collectionName = widget.isOnline
                ? 'leaderboard_tournament_online'
                : 'leaderboard_tournament_ai';
            final displayName = _displayName(OfflineGameState.localId);

            await LeaderboardStatsWriter.instance.recordModeResult(
              collectionName: collectionName,
              uid: uid,
              displayName: displayName,
              deltaWins: 0,
              deltaLosses: 1,
              deltaGamesPlayed: 1,
            );
          }
          if (mounted && !_isDisposed) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        }

        widget.onRoundSummaryShown?.call(round);

        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => TournamentRoundSummaryScreen(
              roundNumber: round.roundNumber,
              advancedPlayerNames: _namesForIds(round.advancedPlayerIds),
              eliminatedPlayerName: _displayName(round.eliminatedPlayerId),
              nextRoundPlayerNames: _namesForIds(round.advancedPlayerIds),
            ),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
        if (!mounted || _isDisposed) return;

        await _waitForUiSettled();
        if (!mounted || _isDisposed) return;

        _engine.startNextRound();
      }
    }

    if (!mounted || _isDisposed || !_engine.isComplete) return;

    // Record leaderboard result for the local player if not already done.
    // The elimination-branch at line ~291 handles mid-tournament exits, but
    // a player who reaches the final and LOSES bypasses that branch because
    // _engine.isComplete is already true when we get here.
    if (!_tournamentLeaderboardRecorded) {
      _tournamentLeaderboardRecorded = true;
      final uid =
          FirebaseAuth.instance.currentUser?.uid ?? OfflineGameState.localId;
      final collectionName = widget.isOnline
          ? 'leaderboard_tournament_online'
          : 'leaderboard_tournament_ai';
      final displayName = _displayName(OfflineGameState.localId);
      final didWin = _engine.winnerId == OfflineGameState.localId;

      await LeaderboardStatsWriter.instance.recordModeResult(
        collectionName: collectionName,
        uid: uid,
        displayName: displayName,
        deltaWins: didWin ? 1 : 0,
        deltaLosses: didWin ? 0 : 1,
        deltaGamesPlayed: 1,
      );
    }

    if (_engine.winnerId == OfflineGameState.localId) {
      unawaited(PlayerLevelService.instance.awardTournamentWinXP());
    }
    AudioService.instance.playSound(GameSound.tournamentWin);

    if (!mounted || _isDisposed) return;
    await Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TournamentWinnerScreen(
          winnerName: _displayName(_engine.winnerId!),
          onPlayAgain: (ctx) {
            Navigator.of(ctx).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => widget.isOnline
                    ? TournamentCoordinator(
                        isOnline: true,
                        onlineLocalDisplayName: widget.onlineLocalDisplayName,
                        showStartButton: true,
                        playerCount: widget.playerCount,
                        aiDifficulty: widget.aiDifficulty,
                      )
                    : TournamentLobbyScreen(),
              ),
              (route) => route.isFirst,
            );
          },
          onReturnToMenu: (ctx) =>
              Navigator.of(ctx).popUntil((route) => route.isFirst),
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Records a player finish with the engine. Only the round game (TableScreen)
  /// should pop with [TournamentRoundGameResult]; this keeps a single pop and
  /// avoids double-pop or stuck coordinator spinner.
  ///
  /// [TableScreen] reports [OfflineGameState] seat IDs (`player-2`…); the
  /// offline engine uses `tournament-ai-*`. We map before [recordPlayerFinished].
  void _onPlayerFinished(String playerId, int finishPosition) {
    if (playerId.isEmpty) return;
    final idsForMapping =
        _enginePlayerIdsForCurrentTable ?? _engine.activePlayerIds;
    final engineId = resolveTournamentTableIdToEnginePlayerId(
      reportedId: playerId,
      activePlayerIds: idsForMapping,
    );
    if (_engine.finishingPositionFor(
          roundNumber: _engine.currentRound,
          playerId: engineId,
        ) !=
        null) {
      return;
    }
    _engine.recordPlayerFinished(engineId, finishPosition: finishPosition);
  }

  Map<String, String> _buildTournamentNamesByTableId(List<String> activeIds) {
    // Keep TableScreen's local slot stable:
    // - It always uses `OfflineGameState.localId` as the human-controlled seat.
    // - The tournament engine's `activePlayerIds` ordering can change between rounds.
    // Map `player-local` to the engine's local player id (if still active),
    // and then fill remaining table seats with the other active players.
    final localActive = activeIds.contains(OfflineGameState.localId);
    final localName = localActive ? _displayName(OfflineGameState.localId) : 'You';

    final opponentIds =
        activeIds.where((id) => id != OfflineGameState.localId).toList(growable: false);

    final map = <String, String>{};
    map[OfflineGameState.localId] = localName;

    for (var i = 0; i < opponentIds.length; i++) {
      // OfflineGameState opponent ids are `player-2`, `player-3`, ...
      final tableId = 'player-${i + 2}';
      map[tableId] = _displayName(opponentIds[i]);
    }
    return map;
  }

  List<String> _namesForIds(List<String> ids) =>
      ids.map(_displayName).toList(growable: false);

  String _displayName(String playerId) {
    final match =
        _engine.allPlayers.where((p) => p.id == playerId).firstOrNull;
    return match?.displayName ?? playerId;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showStartButton && !_hasStarted) {
      final theme = ref.watch(themeProvider).theme;
      return Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tournament Lobby',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: theme.accentPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isOnline ? 'Online Bracket' : 'Offline Bracket',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: theme.textSecondary,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onStartTournament,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: theme.backgroundDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Start Tournament',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Brief loading state before loop pushes first screen or between rounds.
    // Keep minimal so transition to WaitingScreen/EliminationScreen feels instant.
    final theme = ref.watch(themeProvider).theme;
    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: theme.accentPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading…',
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
