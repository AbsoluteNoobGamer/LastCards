import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/offline_game_state.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/card_back_service.dart';
import '../../../../services/audio_service.dart';
import '../../../../services/game_sound.dart';
import '../../../../tournament/tournament_engine.dart';
import '../../gameplay/presentation/screens/table_screen.dart';
import '../../single_player/providers/single_player_session_provider.dart';
import '../providers/tournament_session_provider.dart';
import 'elimination_screen.dart';
import 'round_summary_screen.dart';
import 'tournament_lobby_screen.dart';
import 'waiting_screen.dart';
import 'winner_screen.dart';

/// Builds the round game widget (default: [TableScreen]).
/// Used for dependency injection and tests.
typedef TournamentRoundGameBuilder = Widget Function({
  required int totalPlayers,
  required bool isTournamentMode,
  required void Function(String playerName, int finishPosition) onPlayerFinished,
  required Map<String, String> tournamentPlayerNameByTableId,
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
    required void Function(String playerName, int finishPosition)
        onPlayerFinished,
    required Map<String, String> tournamentPlayerNameByTableId,
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
  Map<String, String> _currentRoundPlayerIdByName = const {};
  bool _hasStarted = false;
  bool _isDisposed = false;

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

  Future<void> _runTournamentLoop() async {
    while (mounted && !_isDisposed && !_engine.isComplete) {
      final expectedRound = _engine.currentRound;
      final playersInRound = _engine.activePlayerIds.length;
      final nameByTableId = _buildTournamentNamesByTableId(_engine.activePlayerIds);
      _currentRoundPlayerIdByName = _buildPlayerIdByName(_engine.activePlayerIds);

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

      // Round game
      final roundResult = await Navigator.push<TournamentRoundGameResult>(
        context,
        MaterialPageRoute(
          builder: (_) => widget.roundGameBuilder(
            totalPlayers: playersInRound,
            isTournamentMode: true,
            onPlayerFinished: _onPlayerFinished,
            tournamentPlayerNameByTableId: nameByTableId,
            aiDifficulty: widget.isOnline ? null : _aiDifficulty,
          ),
        ),
      );
      if (!mounted || _isDisposed) return;
      if (roundResult == null) return;

      final round = _engine.roundResults
          .where((r) => r.roundNumber == expectedRound)
          .firstOrNull;
      if (round == null) return;

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
        widget.onRoundSummaryShown?.call(round);

        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => TournamentRoundSummaryScreen(
              roundNumber: round.roundNumber,
              advancedPlayerNames: _namesForIds(round.advancedPlayerIds),
              eliminatedPlayerName: _displayName(round.eliminatedPlayerId),
              nextRoundPlayerNames: _namesForIds(round.advancedPlayerIds),
              onReady: () => Navigator.of(context).pop(),
            ),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
        if (!mounted || _isDisposed) return;

        _engine.startNextRound();
      }
    }

    if (!mounted || _isDisposed || !_engine.isComplete) return;

    if (_engine.winnerId == OfflineGameState.localId) {
      CardBackService.instance.registerWin();
    }
    AudioService.instance.playSound(GameSound.tournamentWin);

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

  void _onPlayerFinished(String playerName, int finishPosition) {
    final id = _currentRoundPlayerIdByName[playerName] ?? '';
    if (id.isEmpty) return;
    if (_engine.finishingPositionFor(
          roundNumber: _engine.currentRound,
          playerId: id,
        ) !=
        null) {
      return;
    }
    _engine.recordPlayerFinished(id, finishPosition: finishPosition);

    if (_engine.isRoundInProgress) return;

    final round = _engine.roundResults
        .where((r) => r.roundNumber == _engine.currentRound)
        .firstOrNull;
    if (round == null) return;
    if (!Navigator.of(context).canPop()) return;

    Navigator.of(context).pop(
      TournamentRoundGameResult(
        finishedPlayerIds: round.playerIdsInFinishOrder,
        eliminatedPlayerId: round.eliminatedPlayerId,
      ),
    );
  }

  Map<String, String> _buildTournamentNamesByTableId(List<String> activeIds) {
    final map = <String, String>{};
    for (var i = 0; i < activeIds.length; i++) {
      final tableId = switch (i) {
        0 => OfflineGameState.localId,
        _ => 'player-${i + 1}',
      };
      map[tableId] = _displayName(activeIds[i]);
    }
    return map;
  }

  Map<String, String> _buildPlayerIdByName(List<String> activeIds) {
    final map = <String, String>{};
    for (final playerId in activeIds) {
      map[_displayName(playerId)] = playerId;
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

    // Brief loading state before loop pushes first screen
    return Scaffold(
      backgroundColor: ref.watch(themeProvider).theme.backgroundDeep,
      body: Center(
        child: CircularProgressIndicator(
          color: ref.watch(themeProvider).theme.accentPrimary,
        ),
      ),
    );
  }
}
