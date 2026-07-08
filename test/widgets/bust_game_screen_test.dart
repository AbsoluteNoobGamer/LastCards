import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/features/bust/screens/bust_game_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/felt_table_background.dart';

import '../helpers/mock_audio_platform.dart';

/// Bust has no debug hooks for a fixed initial deck (unlike TableScreen's
/// debugInitialOfflineState), and its deal is a real sequential per-card
/// flight animation for every seated player — draining it fully needs a
/// bounded loop of pumps rather than pumpAndSettle (which has no timeout and
/// would hang the test if anything kept scheduling frames).
Future<void> _pumpDrainBustDealAndAnyAiTurn(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'profile_name': 'Player'});
    mockAudioChannels();
  });

  testWidgets('BustGameScreen renders and deals without throwing',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BustGameScreen(totalPlayers: 5),
        ),
      ),
    );

    // First frame: initial deal state.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FeltTableBackground), findsOneWidget);

    // Drain the sequential per-player deal animation (and, if the local
    // player doesn't go first, the AI turn(s) that follow) — this is what
    // actually builds the move-log / stack-block-banner overlays wired up
    // for Bust mode, so a structural mistake there (wrong ancestor Stack,
    // missing GlobalKey, bad import) would throw here.
    await _pumpDrainBustDealAndAnyAiTurn(tester);
    expect(tester.takeException(), isNull);

    expect(find.byType(DrawPileWidget), findsOneWidget);
    expect(find.byType(DiscardPileWidget), findsOneWidget);
  });
}
