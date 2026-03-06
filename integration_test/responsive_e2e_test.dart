import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:deck_drop/features/gameplay/data/datasources/offline_game_state_datasource.dart';
import 'package:deck_drop/features/gameplay/domain/entities/card.dart';
import 'package:deck_drop/features/gameplay/domain/entities/game_state.dart';
import 'package:deck_drop/features/gameplay/domain/usecases/offline_game_engine.dart';
import 'package:deck_drop/features/gameplay/presentation/screens/table_screen.dart';
import 'package:deck_drop/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:deck_drop/features/gameplay/presentation/widgets/player_hand_widget.dart';
import 'package:deck_drop/features/start/presentation/screens/start_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTable(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TableScreen(totalPlayers: 2),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Normal responsive scenario (mobile and tablet table)',
      (tester) async {
    await pumpTable(tester, const Size(412, 915));
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerHandWidget), findsOneWidget);
    expect(find.byType(DrawPileWidget), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpTable(tester, const Size(1024, 1366));
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerHandWidget), findsOneWidget);
    expect(find.byType(DrawPileWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edge case responsive scenario (very small and very large)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DeckDropStartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play with AI'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1400, 1800);
    await tester.pumpAndSettle();
    expect(find.text('Play with AI'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Online selector modal exposes both online modes',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DeckDropStartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(find.text('Up to 3 online players'), findsOneWidget);
    expect(find.text('Tournament mode'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Up to 3 online players'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Invalid UI state is guarded during dealing', (tester) async {
    await pumpTable(tester, const Size(412, 915));

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('DEALING...'), findsOneWidget);

    final drawPile = find.byType(DrawPileWidget);
    expect(drawPile, findsOneWidget);
    await tester.tap(drawPile);
    await tester.pump();

    expect(find.text('DEALING...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Multi-turn interaction remains stable on mobile layout',
      (tester) async {
    await pumpTable(tester, const Size(412, 915));
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpAndSettle();

    final drawPile = find.byType(DrawPileWidget);
    expect(drawPile, findsOneWidget);

    await tester.tap(drawPile);
    await tester.pumpAndSettle();

    // Local hand should still exist and game should keep progressing.
    expect(find.byType(PlayerHandWidget), findsOneWidget);
    expect(find.byType(DrawPileWidget), findsOneWidget);
    expect(find.textContaining("'s Turn"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Regression protection for existing rules stays deterministic',
      (tester) async {
    final (state, _) = OfflineGameState.buildWithDeck(totalPlayers: 2);

    final invalid = const CardModel(
      id: 'invalid',
      suit: Suit.spades,
      rank: Rank.nine,
    );
    final forcedState = state.copyWith(
      discardTopCard: const CardModel(
        id: 'top',
        suit: Suit.hearts,
        rank: Rank.four,
      ),
      phase: GamePhase.playing,
    );

    final err = validatePlay(
      cards: [invalid],
      discardTop: forcedState.discardTopCard!,
      state: forcedState,
    );

    expect(err, isNotNull);
    expect(err, contains('Must match'));
  });
}
