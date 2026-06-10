import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/models/table_position_layout.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/hud_overlay_widget.dart';

class _MockAudioService extends AudioService {}

void main() {
  CardModel c(String id, Rank rank, Suit suit) =>
      CardModel(id: id, rank: rank, suit: suit);

  List<CardModel> hand(int prefix) => List.generate(
        7,
        (i) => c('H$prefix$i', Rank.values[i % Rank.values.length], Suit.hearts),
      );

  GameState seededState(int totalPlayers) {
    final players = List.generate(
      totalPlayers,
      (i) => PlayerModel(
        id: i == 0 ? OfflineGameState.localId : 'player-$i',
        displayName: i == 0 ? 'You' : 'P$i',
        tablePosition: tablePositionForSeatIndex(i),
        hand: hand(i),
        cardCount: 7,
      ),
    );
    return GameState(
      sessionId: 'board-layout-$totalPlayers',
      phase: GamePhase.playing,
      players: players,
      currentPlayerId: OfflineGameState.localId,
      direction: PlayDirection.clockwise,
      discardTopCard: c('disc', Rank.six, Suit.spades),
      drawPileCount: 12,
      suitLock: Suit.hearts,
      activePenaltyCount: 4,
    );
  }

  Future<void> pumpTable(
    WidgetTester tester, {
    required Size size,
    required int totalPlayers,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
        ],
        child: MaterialApp(
          home: TableScreen(
            totalPlayers: totalPlayers,
            debugInitialOfflineState: seededState(totalPlayers),
            debugInitialDrawPile: [c('D0', Rank.two, Suit.hearts)],
            debugSkipDealAnimation: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  const widths = <({double width, double height, String label})>[
    (width: 320, height: 568, label: '320px phone'),
    (width: 360, height: 640, label: '360px phone'),
    (width: 768, height: 1024, label: '768px tablet'),
  ];

  for (final playerCount in [2, 7]) {
    for (final viewport in widths) {
      testWidgets(
        'portrait board has no flex overflow at ${viewport.label} ($playerCount players)',
        (tester) async {
          await pumpTable(
            tester,
            size: Size(viewport.width, viewport.height),
            totalPlayers: playerCount,
          );

          expect(find.byType(DrawPileWidget), findsOneWidget);
          expect(find.byType(DiscardPileWidget), findsOneWidget);
          expect(find.byType(HudOverlayWidget), findsOneWidget);
        },
      );
    }
  }
}
