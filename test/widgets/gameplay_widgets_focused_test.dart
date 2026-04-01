import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/hud_overlay_widget.dart';

import '../helpers/mock_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mockAudioChannels();
  });

  testWidgets('CardWidget invokes onTap when tapped', (tester) async {
    var taps = 0;
    final card = CardModel(id: 'c1', rank: Rank.king, suit: Suit.hearts);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: CardWidget(
              card: card,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(CardWidget));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('DrawPileWidget calls onTap when enabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawPileWidget(
            cardCount: 5,
            enabled: true,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(DrawPileWidget));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('DrawPileWidget does not call onTap when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawPileWidget(
            cardCount: 5,
            enabled: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(DrawPileWidget));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('HudOverlayWidget shows penalty badge text when penaltyCount > 0',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: HudOverlayWidget(
              penaltyCount: 4,
              penaltyTargetPosition: TablePosition.top,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('+4'), findsOneWidget);
  });
}
