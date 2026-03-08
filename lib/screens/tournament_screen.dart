import 'package:flutter/material.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/services/card_back_service.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/tournament/screens/elimination_screen.dart';
import 'package:last_cards/features/tournament/screens/round_summary_screen.dart';
import 'package:last_cards/features/tournament/screens/winner_screen.dart';
import 'package:last_cards/screens/tournament/tournament_lobby_screen.dart';
import 'package:last_cards/services/audio_service.dart';
import 'package:last_cards/services/game_sound.dart';
import 'package:last_cards/tournament/tournament_engine.dart';

typedef TournamentRoundGameBuilder = Widget Function({
  required int totalPlayers,
  required bool isTournamentMode,
  required void Function(String playerName, int finishPosition)
      onPlayerFinished,
  required Map<String, String> tournamentPlayerNameByTableId,
});

class TournamentScreen extends StatefulWidget {
  const TournamentScreen({
    this.roundGameBuilder = _defaultRoundGameBuilder,
    this.onRoundSummaryShown,
    this.isOnline = false,
    this.onlineLocalDisplayName = 'You',
    super.key,
  });

  final TournamentRoundGameBuilder roundGameBuilder;
  final void Function(TournamentRoundResult result)? onRoundSummaryShown;
  final bool isOnline;
  final String onlineLocalDisplayName;

  static Widget _defaultRoundGameBuilder({
    required int totalPlayers,
    required bool isTournamentMode,
    required void Function(String playerName, int finishPosition)
        onPlayerFinished,
    required Map<String, String> tournamentPlayerNameByTableId,
  }) {
    return TableScreen(
      totalPlayers: totalPlayers,
      isTournamentMode: isTournamentMode,
      onPlayerFinished: onPlayerFinished,
      tournamentPlayerNameByTableId: tournamentPlayerNameByTableId,
    );
  }

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  late final TournamentEngine _engine;
  static const _localPlayerId = OfflineGameState.localId;
  Map<String, String> _currentRoundPlayerIdByName = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _engine = widget.isOnline
        ? TournamentEngine.online(
            players: [
              TournamentPlayer(
                id: _localPlayerId,
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
          )
        : TournamentEngine.offline(
            players: const [
              TournamentPlayer(
                id: _localPlayerId,
                displayName: 'You',
                isAi: false,
              ),
            ],
          );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _startTournament() async {
    _engine.startTournament();
    await _runTournamentLoop();
  }

  Future<void> _runTournamentLoop() async {
    while (mounted && !_engine.isComplete) {
      final expectedRound = _engine.currentRound;
      final playersInRound = _engine.activePlayerIds.length;
      final nameByTableId = _buildTournamentNamesByTableId(
        _engine.activePlayerIds,
      );
      _currentRoundPlayerIdByName =
          _buildPlayerIdByName(_engine.activePlayerIds);
      final roundResult = await Navigator.push<TournamentRoundGameResult>(
        context,
        MaterialPageRoute(
          builder: (_) => widget.roundGameBuilder(
            totalPlayers: playersInRound,
            isTournamentMode: true,
            onPlayerFinished: _onPlayerFinished,
            tournamentPlayerNameByTableId: nameByTableId,
          ),
        ),
      );
      if (!mounted) return;
      if (roundResult == null) {
        return;
      }

      final round = _engine.roundResults
          .where((r) => r.roundNumber == expectedRound)
          .firstOrNull;
      if (round == null) return;

      // Always show elimination screen so the player sees who was knocked out,
      // even on the final round before the winner screen.
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
      if (!mounted) return;

      // Only show the "Next Round" summary when there is actually a next round.
      if (!_engine.isComplete) {
        widget.onRoundSummaryShown?.call(round);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TournamentRoundSummaryScreen(
              roundNumber: round.roundNumber,
              advancedPlayerNames: _namesForIds(round.advancedPlayerIds),
              eliminatedPlayerName: _displayName(round.eliminatedPlayerId),
              nextRoundPlayerNames: _namesForIds(round.advancedPlayerIds),
              onReady: () => Navigator.of(context).pop(),
            ),
          ),
        );
        if (!mounted) return;

        _engine.startNextRound();
      }
    }

    if (!mounted || !_engine.isComplete) {
      return;
    }

    if (_engine.winnerId == _localPlayerId) {
      CardBackService.instance.registerWin();
    }
    AudioService.instance.playSound(GameSound.tournamentWin);

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentWinnerScreen(
          winnerName: _displayName(_engine.winnerId!),
          onPlayAgain: (ctx) => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TournamentScreen(
                isOnline: widget.isOnline,
                onlineLocalDisplayName: widget.onlineLocalDisplayName,
              ),
            ),
          ),
          onReturnToMenu: (ctx) => Navigator.of(ctx).pop(),
        ),
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

    if (_engine.isRoundInProgress) {
      return;
    }

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
        1 => 'player-2',
        2 => 'player-3',
        _ => 'player-4',
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
    final match = _engine.allPlayers.where((p) => p.id == playerId).firstOrNull;
    return match?.displayName ?? playerId;
  }

  @override
  Widget build(BuildContext context) {
    return TournamentLobbyScreen(
      players: _engine.allPlayers,
      isOnline: widget.isOnline,
      isHost: true,
      onStartTournament: _startTournament,
    );
  }
}
