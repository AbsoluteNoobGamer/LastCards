import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';

import '../helpers/mock_audio_platform.dart';

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

  setUp(() {
    mockAudioChannels();
  });

  testWidgets('offline: End Turn is disabled when actionsThisTurn is 0',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    ];

    final initialState = GameState(
      sessionId: 'offline-end-turn',
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: 7,
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
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: drawPile.length,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
    );

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

    final endTurn = find.widgetWithText(ElevatedButton, 'End Turn');
    expect(endTurn, findsOneWidget);
    final button = tester.widget<ElevatedButton>(endTurn);
    expect(button.onPressed, isNull);
  });

  testWidgets('offline: turn timer expiry shows timeout snackbar', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

    final initialState = GameState(
      sessionId: 'offline-timer',
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: 7,
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
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: drawPile.length,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
    );

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

    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    expect(find.textContaining('Timeout!'), findsWidgets);

    await _pumpDrainOfflineAiSchedulers(tester);
  });

  testWidgets('offline: playing last winning card shows YOU WIN dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final localHand = [c('WIN', Rank.seven, Suit.spades)];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
    ];

    final initialState = GameState(
      sessionId: 'offline-win',
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: 1,
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
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: drawPile.length,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
    );

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

    await tester.tap(find.byKey(const ValueKey('entry-WIN')));
    // Avoid pumpAndSettle: offline GameTurnTimer ticks every second and never "settles".
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('YOU WIN!'), findsOneWidget);
  });

  testWidgets('offline: tapping draw pile draws a card when no action yet',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Two of clubs cannot be played on six of spades (wrong rank and suit).
    final localHand = [c('L0', Rank.two, Suit.clubs)];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
      c('D2', Rank.four, Suit.clubs),
    ];

    final initialState = GameState(
      sessionId: 'offline-draw',
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: 1,
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
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: drawPile.length,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
    );

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

    expect(
      find.descendant(
        of: find.byType(DrawPileWidget),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await _pumpDrainOfflineAiSchedulers(tester);
  });

  testWidgets('offline: End Turn is enabled after playing a card', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final localHand = [
      c('L0', Rank.seven, Suit.spades),
      c('L1', Rank.five, Suit.diamonds),
    ];
    final drawPile = [
      c('D0', Rank.two, Suit.hearts),
      c('D1', Rank.three, Suit.diamonds),
    ];

    final initialState = GameState(
      sessionId: 'offline-end-turn-on',
      phase: GamePhase.playing,
      players: [
        PlayerModel(
          id: OfflineGameState.localId,
          displayName: 'You',
          tablePosition: TablePosition.bottom,
          hand: localHand,
          cardCount: 2,
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
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: drawPile.length,
      actionsThisTurn: 0,
      cardsPlayedThisTurn: 0,
    );

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

    await tester.tap(find.byKey(const ValueKey('entry-L0')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final endTurn = find.widgetWithText(ElevatedButton, 'End Turn');
    final button = tester.widget<ElevatedButton>(endTurn);
    expect(button.onPressed, isNotNull);
  });
}
