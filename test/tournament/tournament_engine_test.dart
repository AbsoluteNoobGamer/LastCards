import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/single_player/providers/single_player_session_provider.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_widget.dart';
import 'package:last_cards/features/tournament/screens/tournament_coordinator.dart';
import 'package:last_cards/tournament/tournament_engine.dart';

void main() {
  List<TournamentPlayer> buildPlayers() {
    return const [
      TournamentPlayer(id: 'p1', displayName: 'P1'),
      TournamentPlayer(id: 'p2', displayName: 'P2'),
      TournamentPlayer(id: 'p3', displayName: 'P3'),
      TournamentPlayer(id: 'p4', displayName: 'P4'),
    ];
  }

  void finishRound(TournamentEngine engine, List<String> finishOrder) {
    for (final playerId in finishOrder) {
      engine.registerHandEmpty(playerId);
    }
  }

  group('TournamentEngine', () {
    test('1st to empty hand is recorded as 1st finisher', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();

      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);

      expect(engine.finishingPositionFor(roundNumber: 1, playerId: 'p1'), 1);
    });

    test('last to empty hand is eliminated', () async {
      final engine = TournamentEngine.online(players: buildPlayers());
      PlayerEliminatedEvent? eliminatedEvent;
      engine.playerEliminated.listen((event) => eliminatedEvent = event);

      engine.startTournament();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);
      await Future<void>.delayed(Duration.zero);

      expect(eliminatedEvent, isNotNull);
      expect(eliminatedEvent!.playerId, 'p4');
      expect(eliminatedEvent!.finishingPosition, 4);
    });

    test('correct players advance after 4-player round', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();

      finishRound(engine, ['p3', 'p1', 'p2', 'p4']);

      expect(engine.activePlayerIds, ['p3', 'p1', 'p2']);
    });

    test('remaining players continue after one player finishes', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();

      engine.recordPlayerFinished('p1', finishPosition: 1);

      expect(engine.isRoundInProgress, isTrue);
      expect(engine.roundResults, isEmpty);
      expect(engine.finishingPositionFor(roundNumber: 1, playerId: 'p1'), 1);
    });

    test('when 3 of 4 qualify, last remaining player is immediately eliminated',
        () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();

      engine.recordPlayerFinished('p1', finishPosition: 1);
      engine.recordPlayerFinished('p2', finishPosition: 2);
      engine.recordPlayerFinished('p3', finishPosition: 3);
      expect(engine.roundResults.length, 1);
      expect(engine.isRoundInProgress, isFalse);
      expect(engine.roundResults.first.eliminatedPlayerId, 'p4');
      expect(engine.finishingPositionFor(roundNumber: 1, playerId: 'p4'), 4);
    });

    test('last player turns stop immediately when auto-eliminated', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();

      engine.recordPlayerFinished('p1', finishPosition: 1);
      engine.recordPlayerFinished('p2', finishPosition: 2);
      engine.recordPlayerFinished('p3', finishPosition: 3);

      expect(engine.isRoundInProgress, isFalse);
      expect(engine.activePlayerIds, ['p1', 'p2', 'p3']);
      expect(engine.currentRoundFinishingOrder, ['p1', 'p2', 'p3', 'p4']);
    });

    test('round summary callback is ready immediately after auto-elimination',
        () async {
      final engine = TournamentEngine.online(players: buildPlayers());
      RoundCompleteEvent? completed;
      engine.roundComplete.listen((event) => completed = event);

      engine.startTournament();
      engine.recordPlayerFinished('p1', finishPosition: 1);
      engine.recordPlayerFinished('p2', finishPosition: 2);
      engine.recordPlayerFinished('p3', finishPosition: 3);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isNotNull);
      expect(completed!.result.roundNumber, 1);
      expect(completed!.result.eliminatedPlayerId, 'p4');
    });

    test('rounds progress 4 -> 3 -> 2', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();
      expect(engine.activePlayerIds.length, 4);

      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);
      expect(engine.activePlayerIds.length, 3);

      engine.startNextRound();
      finishRound(engine, ['p2', 'p1', 'p3']);
      expect(engine.activePlayerIds.length, 2);
    });

    test('new round starts with reduced player count', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);

      engine.startNextRound();
      expect(engine.currentRound, 2);
      expect(engine.activePlayerIds.length, 3);
    });

    test('tournament winner identified after final', () {
      final engine = TournamentEngine.online(players: buildPlayers());
      engine.startTournament();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);

      engine.startNextRound();
      finishRound(engine, ['p1', 'p3', 'p2']);

      engine.startNextRound();
      finishRound(engine, ['p3', 'p1']);

      expect(engine.isComplete, isTrue);
      expect(engine.winnerId, 'p3');
    });

    test('playerEliminated fires each round', () async {
      final engine = TournamentEngine.online(players: buildPlayers());
      final eliminated = <PlayerEliminatedEvent>[];
      engine.playerEliminated.listen(eliminated.add);

      engine.startTournament();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);
      engine.startNextRound();
      finishRound(engine, ['p1', 'p3', 'p2']);
      engine.startNextRound();
      finishRound(engine, ['p1', 'p3']);
      await Future<void>.delayed(Duration.zero);

      expect(eliminated.length, 3);
      expect(eliminated.map((e) => e.playerId), ['p4', 'p2', 'p3']);
    });

    test('tournamentComplete fires after final', () async {
      final engine = TournamentEngine.online(players: buildPlayers());
      TournamentCompleteEvent? complete;
      engine.tournamentComplete.listen((event) => complete = event);

      engine.startTournament();
      finishRound(engine, ['p2', 'p1', 'p3', 'p4']);
      engine.startNextRound();
      finishRound(engine, ['p2', 'p3', 'p1']);
      engine.startNextRound();
      finishRound(engine, ['p2', 'p3']);
      await Future<void>.delayed(Duration.zero);

      expect(complete, isNotNull);
      expect(complete!.winnerPlayerId, 'p2');
      expect(complete!.roundResults.length, 3);
    });

    test('offline mode fills empty slots with AI', () {
      final engine = TournamentEngine.offline(
        players: const [
          TournamentPlayer(id: 'local', displayName: 'You'),
        ],
      );

      expect(engine.allPlayers.length, 4);
      expect(engine.allPlayers.where((player) => player.isAi).length, 3);
    });
  });

  group('Tournament mode flow wiring', () {
    CardModel c(String id, Rank rank, Suit suit) =>
        CardModel(id: id, rank: rank, suit: suit);

    testWidgets(
        'TableScreen tournament mode defers qualification on last-card Black Jack',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final finished = <String>[];
      final initialState = GameState(
        sessionId: 'tournament-defer-test',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: OfflineGameState.localId,
            displayName: 'You',
            tablePosition: TablePosition.bottom,
            hand: [c('last-bj', Rank.jack, Suit.spades)],
            cardCount: 1,
            isConnected: true,
            isActiveTurn: true,
            isSkipped: false,
          ),
          PlayerModel(
            id: 'player-2',
            displayName: 'Player 2',
            tablePosition: TablePosition.top,
            hand: [
              c('p2-1', Rank.jack, Suit.hearts),
              c('p2-2', Rank.five, Suit.clubs),
            ],
            cardCount: 2,
            isConnected: true,
            isActiveTurn: false,
            isSkipped: false,
          ),
        ],
        currentPlayerId: OfflineGameState.localId,
        direction: PlayDirection.clockwise,
        discardTopCard: c('discard-3s', Rank.three, Suit.spades),
        drawPileCount: 6,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TableScreen(
              totalPlayers: 2,
              isTournamentMode: true,
              onPlayerFinished: (name, pos) => finished.add('$name:$pos'),
              tournamentPlayerNameByTableId: const {
                OfflineGameState.localId: 'You',
                'player-2': 'Player 2',
              },
              debugInitialOfflineState: initialState,
              debugInitialDrawPile: [
                c('draw-1', Rank.two, Suit.hearts),
                c('draw-2', Rank.four, Suit.diamonds),
                c('draw-3', Rank.six, Suit.spades),
              ],
              debugSkipDealAnimation: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final lastBlackJack = find.byWidgetPredicate(
        (w) => w is CardWidget && w.card.id == 'last-bj',
      );
      expect(lastBlackJack, findsOneWidget);
      await tester.tap(lastBlackJack);
      await tester.pump();

      expect(finished, isEmpty);
      expect(find.text('✓ Qualified'), findsNothing);
    });

    testWidgets(
        'TableScreen tournament mode defers qualification on last-card Queen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final finished = <String>[];
      final initialState = GameState(
        sessionId: 'tournament-queen-defer-test',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: OfflineGameState.localId,
            displayName: 'You',
            tablePosition: TablePosition.bottom,
            hand: [c('last-qh', Rank.queen, Suit.hearts)],
            cardCount: 1,
            isConnected: true,
            isActiveTurn: true,
            isSkipped: false,
          ),
          PlayerModel(
            id: 'player-2',
            displayName: 'Player 2',
            tablePosition: TablePosition.top,
            hand: [
              c('p2-1', Rank.king, Suit.hearts),
              c('p2-2', Rank.five, Suit.clubs),
            ],
            cardCount: 2,
            isConnected: true,
            isActiveTurn: false,
            isSkipped: false,
          ),
        ],
        currentPlayerId: OfflineGameState.localId,
        direction: PlayDirection.clockwise,
        discardTopCard: c('discard-3h', Rank.three, Suit.hearts),
        drawPileCount: 6,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TableScreen(
              totalPlayers: 2,
              isTournamentMode: true,
              onPlayerFinished: (name, pos) => finished.add('$name:$pos'),
              tournamentPlayerNameByTableId: const {
                OfflineGameState.localId: 'You',
                'player-2': 'Player 2',
              },
              debugInitialOfflineState: initialState,
              debugInitialDrawPile: [
                c('draw-1', Rank.two, Suit.spades),
                c('draw-2', Rank.four, Suit.diamonds),
                c('draw-3', Rank.six, Suit.clubs),
              ],
              debugSkipDealAnimation: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final lastQueen = find.byWidgetPredicate(
        (w) => w is CardWidget && w.card.id == 'last-qh',
      );
      expect(lastQueen, findsOneWidget);
      await tester.tap(lastQueen);
      await tester.pump();

      expect(finished, isEmpty);
      expect(find.text('✓ Qualified'), findsNothing);
    });

    testWidgets(
        'onPlayerFinished is called each time a player empties hand in tournament mode',
        (tester) async {
      final finishCalls = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              playerCount: 4,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                AiDifficulty? aiDifficulty,
              }) {
                final names = [
                  tournamentPlayerNameByTableId['player-local'] ?? 'You',
                  tournamentPlayerNameByTableId['player-2'] ?? 'Player 2',
                  tournamentPlayerNameByTableId['player-3'] ?? 'Player 3',
                  tournamentPlayerNameByTableId['player-4'] ?? 'Player 4',
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderNames: names,
                  onPlayerFinished: (name, pos) {
                    finishCalls.add('$name:$pos');
                    onPlayerFinished(name, pos);
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(finishCalls.length, 4);
      expect(finishCalls[0], 'You:1');
      expect(finishCalls[1], endsWith(':2'));
      expect(finishCalls[2], endsWith(':3'));
      expect(finishCalls[3], endsWith(':4'));

      // Dismiss EliminationScreen to clean up the navigator stack.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('standard win screen does NOT appear when isTournamentMode is true',
        (tester) async {
      bool? capturedTournamentMode;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                AiDifficulty? aiDifficulty,
              }) {
                capturedTournamentMode = isTournamentMode;
                final names = [
                  tournamentPlayerNameByTableId['player-local'] ?? 'You',
                  tournamentPlayerNameByTableId['player-2'] ?? 'Player 2',
                  tournamentPlayerNameByTableId['player-3'] ?? 'Player 3',
                  tournamentPlayerNameByTableId['player-4'] ?? 'Player 4',
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderNames: names,
                  onPlayerFinished: onPlayerFinished,
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(capturedTournamentMode, isTrue);
      expect(find.text('PLAY AGAIN'), findsNothing);

      // Dismiss EliminationScreen to clean up the navigator stack.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('round summary screen appears after all 4 players have finished',
        (tester) async {
      TournamentRoundResult? summaryResult;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              onRoundSummaryShown: (result) => summaryResult = result,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                AiDifficulty? aiDifficulty,
              }) {
                // Use actual display names from the engine so _onPlayerFinished
                // can resolve them to player IDs (AI names are now randomised).
                final names = [
                  tournamentPlayerNameByTableId['player-local'] ?? 'You',
                  tournamentPlayerNameByTableId['player-2'] ?? 'Player 2',
                  tournamentPlayerNameByTableId['player-3'] ?? 'Player 3',
                  tournamentPlayerNameByTableId['player-4'] ?? 'Player 4',
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderNames: names,
                  onPlayerFinished: onPlayerFinished,
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Dismiss EliminationScreen so flow reaches onRoundSummaryShown.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(summaryResult, isNotNull);
      expect(summaryResult!.roundNumber, 1);
    });

    testWidgets(
        'round summary is shown immediately after auto-elimination (last player does not continue)',
        (tester) async {
      TournamentRoundResult? summaryResult;
      final finishCalls = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              onRoundSummaryShown: (result) => summaryResult = result,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                AiDifficulty? aiDifficulty,
              }) {
                // 3 players finish; the 4th (tournament-ai-4) is auto-eliminated.
                final names = [
                  tournamentPlayerNameByTableId['player-local'] ?? 'You',
                  tournamentPlayerNameByTableId['player-2'] ?? 'Player 2',
                  tournamentPlayerNameByTableId['player-3'] ?? 'Player 3',
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderNames: names,
                  autoPopAfterCallbacks: false,
                  onPlayerFinished: (name, pos) {
                    finishCalls.add('$name:$pos');
                    onPlayerFinished(name, pos);
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // 3 callbacks fired; verify positions without depending on random AI names.
      expect(finishCalls.length, 3);
      expect(finishCalls[0], endsWith(':1'));
      expect(finishCalls[1], endsWith(':2'));
      expect(finishCalls[2], endsWith(':3'));

      // Dismiss EliminationScreen so flow reaches onRoundSummaryShown.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(summaryResult, isNotNull);
      expect(summaryResult!.eliminatedPlayerId, 'tournament-ai-4');
    });

    testWidgets('eliminated player is correctly the last to finish', (tester) async {
      TournamentRoundResult? summaryResult;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              onRoundSummaryShown: (result) => summaryResult = result,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                AiDifficulty? aiDifficulty,
              }) {
                // player-2 finishes 1st, local ('You') 2nd; player-4 finishes last.
                final names = [
                  tournamentPlayerNameByTableId['player-2'] ?? 'Player 2',
                  tournamentPlayerNameByTableId['player-local'] ?? 'You',
                  tournamentPlayerNameByTableId['player-3'] ?? 'Player 3',
                  tournamentPlayerNameByTableId['player-4'] ?? 'Player 4',
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderNames: names,
                  onPlayerFinished: onPlayerFinished,
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Dismiss EliminationScreen so flow reaches onRoundSummaryShown.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(summaryResult, isNotNull);
      expect(summaryResult!.eliminatedPlayerId, 'tournament-ai-4');
    });

    test('normal game mode win screen still appears correctly when isTournamentMode is false',
        () {
      expect(shouldShowStandardWinOverlay(isTournamentMode: false), isTrue);
      expect(shouldShowStandardWinOverlay(isTournamentMode: true), isFalse);
    });
  });
}

class _AutoFinishRoundGameScreen extends StatefulWidget {
  const _AutoFinishRoundGameScreen({
    required this.finishOrderNames,
    required this.onPlayerFinished,
    this.autoPopAfterCallbacks = true,
  });

  final List<String> finishOrderNames;
  final void Function(String playerName, int finishPosition) onPlayerFinished;
  final bool autoPopAfterCallbacks;

  @override
  State<_AutoFinishRoundGameScreen> createState() =>
      _AutoFinishRoundGameScreenState();
}

class _AutoFinishRoundGameScreenState extends State<_AutoFinishRoundGameScreen> {
  bool _didTrigger = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didTrigger) return;
    _didTrigger = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var i = 0; i < widget.finishOrderNames.length; i++) {
        widget.onPlayerFinished(widget.finishOrderNames[i], i + 1);
      }
      if (!widget.autoPopAfterCallbacks) return;
      if (!mounted) return;
      // Guard against double-pop: _onPlayerFinished may have already popped
      // this route when the round completed (all players recorded).
      if (!Navigator.of(context).canPop()) return;
      Navigator.of(context).pop(
        const TournamentRoundGameResult(
          finishedPlayerIds: ['player-local', 'tournament-ai-2', 'tournament-ai-3', 'tournament-ai-4'],
          eliminatedPlayerId: 'tournament-ai-4',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Fake Tournament Round')),
    );
  }
}
