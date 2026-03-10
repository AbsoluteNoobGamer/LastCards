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
import '../../online/screens/matchmaking_screen.dart';
import '../providers/tournament_session_provider.dart';
import 'elimination_screen.dart';
import 'round_summary_screen.dart';
import 'waiting_screen.dart';
import 'winner_screen.dart';

class TournamentLobbyScreen extends ConsumerStatefulWidget {
  const TournamentLobbyScreen({super.key});

  @override
  ConsumerState<TournamentLobbyScreen> createState() =>
      _TournamentLobbyScreenState();
}

class _TournamentLobbyScreenState extends ConsumerState<TournamentLobbyScreen> {
  late final TournamentEngine _engine;
  late final bool _isOnline;
  Map<String, String> _playerIdByName = {};
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(tournamentSessionProvider);
    _isOnline = session.type == TournamentType.online;

    // Online tournaments are driven by the server via MatchmakingScreen →
    // LobbyReadyScreen → TournamentScreen(isOnline: true). We only need a
    // local engine for the offline (vs AI) path.
    if (!_isOnline) {
      _engine = TournamentEngine.offline(
        players: [
          const TournamentPlayer(
            id: OfflineGameState.localId,
            displayName: 'You',
            isAi: false,
          )
        ],
        requiredPlayers: session.playerCount ?? 4,
      );
    } else {
      // Placeholder — never used for online path.
      _engine = TournamentEngine.offline(
        players: [
          const TournamentPlayer(
            id: OfflineGameState.localId,
            displayName: 'You',
            isAi: false,
          )
        ],
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _engine.dispose();
    super.dispose();
  }

  void _onBeginTournament() {
    if (_isOnline) {
      _launchOnlineTournament();
      return;
    }
    _engine.startTournament();
    _runTournamentLoop();
  }

  void _launchOnlineTournament() {
    // Ensure the format is set so LobbyReadyScreen routes to TournamentScreen.
    final session = ref.read(tournamentSessionProvider);
    if (session.format == null) {
      ref
          .read(tournamentSessionProvider.notifier)
          .setFormat(TournamentFormat.knockout);
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MatchmakingScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  Future<void> _runTournamentLoop() async {
    final session = ref.read(tournamentSessionProvider);

    while (mounted && !_isDisposed && !_engine.isComplete) {
      final expectedRound = _engine.currentRound;
      final playersInRound = _engine.activePlayerIds.length;

      // Show waiting screen before each round
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

      _playerIdByName = {
        for (final id in _engine.activePlayerIds) _displayName(id): id
      };

      final nameByTableId = <String, String>{};
      for (var i = 0; i < _engine.activePlayerIds.length; i++) {
        final tableId = switch (i) {
          0 => OfflineGameState.localId,
          1 => 'player-2',
          2 => 'player-3',
          _ => 'player-4',
        };
        nameByTableId[tableId] = _displayName(_engine.activePlayerIds[i]);
      }

      final roundResult = await Navigator.push<TournamentRoundGameResult>(
        context,
        MaterialPageRoute(
          builder: (_) => TableScreen(
            totalPlayers: playersInRound,
            isTournamentMode: true,
            // Pass difficulty scaling to AI if it's a vsAI tournament
            aiDifficulty: session.type == TournamentType.vsAi
                ? session.difficulty
                : null,
            onPlayerFinished: (playerName, finishPosition) {
              final id = _playerIdByName[playerName] ?? '';
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
            },
            tournamentPlayerNameByTableId: nameByTableId,
          ),
        ),
      );

      if (!mounted || _isDisposed || roundResult == null) return;

      final round = _engine.roundResults
          .where((r) => r.roundNumber == expectedRound)
          .firstOrNull;
      if (round == null) return;

      // Only show the "Next Round" summary when there is actually a next round.
      if (!_engine.isComplete) {
        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => TournamentRoundSummaryScreen(
              roundNumber: round.roundNumber,
              advancedPlayerNames:
                  round.advancedPlayerIds.map(_displayName).toList(),
              eliminatedPlayerName: _displayName(round.eliminatedPlayerId),
              nextRoundPlayerNames:
                  round.advancedPlayerIds.map(_displayName).toList(),
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
          MaterialPageRoute(builder: (_) => const TournamentLobbyScreen()),
          (route) => route.isFirst,
        );
      },
      onReturnToMenu: (ctx) {
        Navigator.of(ctx).popUntil((route) => route.isFirst);
      },
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  String _displayName(String playerId) {
    return _engine.allPlayers
            .where((p) => p.id == playerId)
            .firstOrNull
            ?.displayName ??
        playerId;
  }

  Future<bool> _onWillPop() async {
    final theme = ref.read(themeProvider).theme;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: theme.surfacePanel,
            title: Text(
              'Leave Tournament?',
              style: GoogleFonts.outfit(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'Are you sure? Tournament setup will be lost.',
              style: GoogleFonts.inter(color: theme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(color: theme.accentPrimary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Leave',
                    style: GoogleFonts.inter(color: Colors.redAccent)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(tournamentSessionProvider);

    final typeLabel = session.type?.displayName ?? 'Tournament';
    final diffLabel = session.difficulty?.displayName;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (!context.mounted) return;
        if (shouldPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.textPrimary),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (!context.mounted) return;
              if (shouldPop) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo/Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      'LAST CARDS',
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: theme.accentPrimary,
                        letterSpacing: 4.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (session.type == TournamentType.vsAi &&
                            diffLabel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  theme.accentPrimary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: theme.accentPrimary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              diffLabel,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.accentPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '$typeLabel • ${session.playerCount} Players',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Player Grid (offline only — online players are matched server-side)
              if (!_isOnline)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: _engine.allPlayers.length,
                      itemBuilder: (context, index) {
                        final player = _engine.allPlayers[index];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.surfacePanel,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.accentDark.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.backgroundDeep,
                                child: Icon(
                                  player.isAi
                                      ? Icons.smart_toy_rounded
                                      : Icons.person_rounded,
                                  color: theme.accentPrimary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                player.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.public_rounded,
                          size: 64,
                          color: theme.accentPrimary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Online Tournament',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ll be matched with ${(session.playerCount ?? 4) - 1} other players online.\nThe tournament bracket is managed by the server.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // CTA
              Padding(
                padding: const EdgeInsets.all(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [theme.accentLight, theme.accentPrimary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accentPrimary.withValues(alpha: 0.30),
                        blurRadius: 16,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _onBeginTournament,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isOnline ? 'Find Match' : 'Begin Tournament',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: theme.backgroundDeep,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isOnline
                                  ? Icons.search_rounded
                                  : Icons.play_arrow_rounded,
                              size: 24,
                              color: theme.backgroundDeep,
                            ),
                          ],
                        ),
                      ),
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
}
