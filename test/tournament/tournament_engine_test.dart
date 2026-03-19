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

    test('tournament winner identified after final with 6 players', () {
      final engine = TournamentEngine.online(
        players: const [
          TournamentPlayer(id: 'p1', displayName: 'P1'),
          TournamentPlayer(id: 'p2', displayName: 'P2'),
          TournamentPlayer(id: 'p3', displayName: 'P3'),
          TournamentPlayer(id: 'p4', displayName: 'P4'),
          TournamentPlayer(id: 'p5', displayName: 'P5'),
          TournamentPlayer(id: 'p6', displayName: 'P6'),
        ],
      );
      engine.startTournament();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);

      engine.startNextRound();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4', 'p5']);

      engine.startNextRound();
      finishRound(engine, ['p1', 'p2', 'p3', 'p4']);

      engine.startNextRound();
      finishRound(engine, ['p1', 'p2', 'p3']);

      engine.startNextRound();
      finishRound(engine, ['p1', 'p2']);

      expect(engine.isComplete, isTrue);
      expect(engine.winnerId, 'p1');
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
          ),
          PlayerModel(
            id: 'player-2',
            displayName: 'O',
            tablePosition: TablePosition.top,
            hand: [
              c('p2-1', Rank.jack, Suit.hearts),
              c('p2-2', Rank.five, Suit.clubs),
            ],
            cardCount: 2,
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
                'player-2': 'O',
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
          ),
          PlayerModel(
            id: 'player-2',
            displayName: 'O',
            tablePosition: TablePosition.top,
            hand: [
              c('p2-1', Rank.king, Suit.hearts),
              c('p2-2', Rank.five, Suit.clubs),
            ],
            cardCount: 2,
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
                'player-2': 'O',
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
                  onPlayerFinished: (id, pos) {
                    finishCalls.add('$id:$pos');
                    onPlayerFinished(id, pos);
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
      expect(finishCalls[0], endsWith(':1'));
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                capturedTournamentMode = isTournamentMode;
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                // 3 players finish; the 4th is auto-eliminated.
                final firstThree =
                    activePlayerIds.take(3).toList(growable: false);
                final eliminatedId = activePlayerIds.length > 3
                    ? activePlayerIds[3]
                    : activePlayerIds.last;
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: firstThree,
                  autoPopAfterCallbacks: true,
                  eliminatedPlayerId: eliminatedId,
                  onPlayerFinished: (id, pos) {
                    finishCalls.add('$id:$pos');
                    onPlayerFinished(id, pos);
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

      // 3 callbacks fired; verify positions.
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

    testWidgets('qualify to next round: EliminationScreen then Round Summary then next round WaitingScreen',
        (tester) async {
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
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

      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Next Round'), findsOneWidget);
      await tester.tap(find.text('Next Round'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text("Let's Go!"), findsOneWidget);
    });

    testWidgets(
        '4-player offline bracket reaches Round 3 waiting after two full rounds',
        (tester) async {
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
                  onPlayerFinished: onPlayerFinished,
                );
              },
            ),
          ),
        ),
      );

      Future<void> dismissPostRoundUi() async {
        expect(find.text('Continue'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.text('Next Round'), findsOneWidget);
        await tester.tap(find.text('Next Round'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Round 1
      expect(find.text('Round 1'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 2 waiting
      expect(find.text('Round 2'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 3 waiting (2-player final) — regression: must appear after round 2.
      expect(find.text('Round 3'), findsOneWidget);
      expect(find.text("Let's Go!"), findsOneWidget);
    });

    testWidgets(
        '6-player offline bracket reaches Round 5 waiting after four full rounds',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TournamentCoordinator(
              showStartButton: true,
              playerCount: 6,
              roundGameBuilder: ({
                required totalPlayers,
                required isTournamentMode,
                required onPlayerFinished,
                required tournamentPlayerNameByTableId,
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: activePlayerIds,
                  onPlayerFinished: onPlayerFinished,
                );
              },
            ),
          ),
        ),
      );

      Future<void> dismissPostRoundUi() async {
        expect(find.text('Continue'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.text('Next Round'), findsOneWidget);
        await tester.tap(find.text('Next Round'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Start Tournament'));
      await tester.pumpAndSettle(const Duration(milliseconds: 120));

      // Round 1
      expect(find.text('Round 1'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 2
      expect(find.text('Round 2'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 3
      expect(find.text('Round 3'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 4
      expect(find.text('Round 4'), findsOneWidget);
      await tester.tap(find.text("Let's Go!"));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await dismissPostRoundUi();

      // Round 5 waiting (2-player final) should be reachable.
      expect(find.text('Round 5'), findsOneWidget);
      expect(find.text("Let's Go!"), findsOneWidget);
    });

    testWidgets(
        'coordinator records round when TableScreen seat IDs (player-2…) are used',
        (tester) async {
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: const [
                    OfflineGameState.localId,
                    'player-2',
                    'player-3',
                    'player-4',
                  ],
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

      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
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
                required activePlayerIds,
                AiDifficulty? aiDifficulty,
              }) {
                // player-2 finishes 1st, local 2nd, player-3 3rd; player-4 last (eliminated).
                final order = [
                  activePlayerIds[1],
                  activePlayerIds[0],
                  activePlayerIds[2],
                  activePlayerIds[3],
                ];
                return _AutoFinishRoundGameScreen(
                  finishOrderIds: order,
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
    required this.finishOrderIds,
    required this.onPlayerFinished,
    this.autoPopAfterCallbacks = true,
    this.eliminatedPlayerId,
  });

  /// Player IDs in finish order (engine IDs so coordinator round is recorded).
  final List<String> finishOrderIds;
  final void Function(String playerId, int finishPosition) onPlayerFinished;
  final bool autoPopAfterCallbacks;
  /// When set (e.g. 3 of 4 finish, 4th auto-eliminated), used as eliminated in pop result.
  final String? eliminatedPlayerId;

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
      for (var i = 0; i < widget.finishOrderIds.length; i++) {
        widget.onPlayerFinished(widget.finishOrderIds[i], i + 1);
      }
      if (!widget.autoPopAfterCallbacks) return;
      if (!mounted) return;
      if (!Navigator.of(context).canPop()) return;
      // Pop with result; coordinator will match round from engine.roundResults.
      final ids = widget.finishOrderIds;
      final eliminated = widget.eliminatedPlayerId ??
          (ids.isNotEmpty ? ids.last : '');
      Navigator.of(context).pop(
        TournamentRoundGameResult(
          finishedPlayerIds: List<String>.from(ids),
          eliminatedPlayerId: eliminated,
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
