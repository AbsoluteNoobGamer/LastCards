import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';

import '../../../../helpers/mock_audio_platform.dart';

class _MockAudioService extends AudioService {}

/// Offline [TableScreen] schedules AI turns with [Future.delayed]; advance
/// fake time so widget teardown does not hit pending-timer assertions.
Future<void> _pumpDrainOfflineAiSchedulers(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CardModel c(String id, Rank rank, Suit suit) =>
      CardModel(id: id, rank: rank, suit: suit);

  /// Seven cards for the opponent so layout matches a normal two-player deal.
  List<CardModel> opponentSeven() => [
        c('P0', Rank.two, Suit.hearts),
        c('P1', Rank.three, Suit.diamonds),
        c('P2', Rank.four, Suit.clubs),
        c('P3', Rank.king, Suit.spades),
        c('P4', Rank.queen, Suit.hearts),
        c('P5', Rank.jack, Suit.diamonds),
        c('P6', Rank.ace, Suit.clubs),
      ];

  void useLandscapeTablet(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpTableScreen(
    WidgetTester tester, {
    required GameState initialState,
    required List<CardModel> drawPile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
        ],
        child: MaterialApp(
          home: TableScreen(
            totalPlayers: 2,
            debugInitialOfflineState: initialState,
            debugInitialDrawPile: drawPile,
            debugSkipDealAnimation: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  GameState twoPlayerState({
    required String sessionId,
    required List<CardModel> localHand,
    required List<CardModel> drawPile,
    required CardModel discardTop,
    int actionsThisTurn = 0,
    int cardsPlayedThisTurn = 0,
    CardModel? lastPlayedThisTurn,
    Suit? queenSuitLock,
  }) {
    return GameState(
      sessionId: sessionId,
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: localHand.length,
        ),
        PlayerModel(
          id: 'player-2',
          displayName: 'A',
          tablePosition: TablePosition.top,
          hand: opponentSeven(),
          cardCount: 7,
        ),
      ],
      currentPlayerId: OfflineGameState.localId,
      direction: PlayDirection.clockwise,
      discardTopCard: discardTop,
      drawPileCount: drawPile.length,
      actionsThisTurn: actionsThisTurn,
      cardsPlayedThisTurn: cardsPlayedThisTurn,
      lastPlayedThisTurn: lastPlayedThisTurn,
      queenSuitLock: queenSuitLock,
    );
  }

  int localHandCardCount(WidgetTester tester) {
    return find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('entry-'),
        )
        .evaluate()
        .length;
  }

  setUp(() {
    mockAudioChannels();
  });

  testWidgets('offline mode renders draw and discard piles from seeded state',
      (tester) async {
    useLandscapeTablet(tester);

    final localHand = [
      c('L0', Rank.four, Suit.hearts),
      c('L1', Rank.five, Suit.diamonds),
      c('L2', Rank.six, Suit.clubs),
      c('L3', Rank.seven, Suit.spades),
      c('L4', Rank.eight, Suit.hearts),
      c('L5', Rank.nine, Suit.diamonds),
      c('L6', Rank.ten, Suit.clubs),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
      c('D2', Rank.four, Suit.clubs),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-render',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: c('disc', Rank.six, Suit.spades),
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: c('played', Rank.six, Suit.spades),
      ),
      drawPile: drawPile,
    );

    expect(find.byType(DrawPileWidget), findsOneWidget);
    expect(find.byType(DiscardPileWidget), findsOneWidget);
    expect(find.text('End Turn'), findsOneWidget);
  });

  testWidgets('End Turn is disabled when validateEndTurn would fail', (tester) async {
    useLandscapeTablet(tester);

    final localHand = [
      c('L0', Rank.four, Suit.hearts),
      c('L1', Rank.five, Suit.diamonds),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-end-turn-off',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: c('disc', Rank.six, Suit.spades),
        actionsThisTurn: 0,
      ),
      drawPile: drawPile,
    );

    final endTurn = find.widgetWithText(ElevatedButton, 'End Turn');
    expect(endTurn, findsOneWidget);
    expect(tester.widget<ElevatedButton>(endTurn).onPressed, isNull);
  });

  testWidgets('End Turn is enabled when validateEndTurn would pass', (tester) async {
    useLandscapeTablet(tester);

    final played = c('played', Rank.seven, Suit.spades);
    final localHand = [
      c('L0', Rank.five, Suit.diamonds),
      c('L1', Rank.eight, Suit.hearts),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-end-turn-on',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: played,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: played,
      ),
      drawPile: drawPile,
    );

    final endTurn = find.widgetWithText(ElevatedButton, 'End Turn');
    expect(endTurn, findsOneWidget);
    expect(tester.widget<ElevatedButton>(endTurn).onPressed, isNotNull);
  });

  testWidgets('turn timer expiry advances turn when queen lock is inactive',
      (tester) async {
    useLandscapeTablet(tester);

    final played = c('played', Rank.seven, Suit.spades);
    final localHand = [
      c('L0', Rank.five, Suit.diamonds),
      c('L1', Rank.eight, Suit.hearts),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
      c('D2', Rank.four, Suit.clubs),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-timer-advance',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: played,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: played,
      ),
      drawPile: drawPile,
    );

    final actionBarBefore =
        tester.widget<FloatingActionBarWidget>(find.byType(FloatingActionBarWidget));
    expect(actionBarBefore.isLocalTurn, isTrue);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    final actionBarAfter =
        tester.widget<FloatingActionBarWidget>(find.byType(FloatingActionBarWidget));
    expect(actionBarAfter.isLocalTurn, isFalse);

    await _pumpDrainOfflineAiSchedulers(tester);
  });

  testWidgets('turn timer expiry forces draw when queenSuitLock is active',
      (tester) async {
    useLandscapeTablet(tester);

    final queen = c('queen', Rank.queen, Suit.hearts);
    final localHand = [
      c('L0', Rank.five, Suit.diamonds),
      c('L1', Rank.eight, Suit.hearts),
      c('L2', Rank.nine, Suit.clubs),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
      c('D2', Rank.four, Suit.clubs),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-timer-queen-draw',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: queen,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: queen,
        queenSuitLock: Suit.hearts,
      ),
      drawPile: drawPile,
    );

    expect(localHandCardCount(tester), equals(3));

    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(localHandCardCount(tester), equals(4));

    await _pumpDrainOfflineAiSchedulers(tester);
  });

  testWidgets('win dialog appears when local player empties hand', (tester) async {
    useLandscapeTablet(tester);

    final localHand = [c('WIN', Rank.seven, Suit.spades)];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-win',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: c('disc', Rank.six, Suit.spades),
      ),
      drawPile: drawPile,
    );

    await tester.tap(find.byKey(const ValueKey('entry-WIN')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('YOU WIN!'), findsOneWidget);
  });

  testWidgets('draw pile tap increases local hand size by one', (tester) async {
    useLandscapeTablet(tester);

    final localHand = [c('L0', Rank.two, Suit.clubs)];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
      c('D2', Rank.four, Suit.clubs),
    ];

    await pumpTableScreen(
      tester,
      initialState: twoPlayerState(
        sessionId: 'offline-draw',
        localHand: localHand,
        drawPile: drawPile,
        discardTop: c('disc', Rank.six, Suit.spades),
      ),
      drawPile: drawPile,
    );

    expect(localHandCardCount(tester), equals(1));
    expect(
      find.descendant(
        of: find.byType(DrawPileWidget),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(DrawPileWidget));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(localHandCardCount(tester), equals(2));
    expect(
      find.descendant(
        of: find.byType(DrawPileWidget),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await _pumpDrainOfflineAiSchedulers(tester);
  });
}
