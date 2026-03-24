import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';

void main() {
  testWidgets('Last Cards scale bump key appears when hand crosses to ≤5',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: _LastCardsHighlightHarness(
              key: const ValueKey('harness'),
              initialHandSize: 6,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('lc-scale-0')), findsOneWidget);

    final state = tester.state<_LastCardsHighlightHarnessState>(
      find.byKey(const ValueKey('harness')),
    );
    state.setHandSize(5);
    await tester.pump();

    expect(find.byKey(const ValueKey('lc-scale-1')), findsOneWidget);
  });
}

class _LastCardsHighlightHarness extends StatefulWidget {
  const _LastCardsHighlightHarness({
    super.key,
    required this.initialHandSize,
  });

  final int initialHandSize;

  @override
  State<_LastCardsHighlightHarness> createState() =>
      _LastCardsHighlightHarnessState();
}

class _LastCardsHighlightHarnessState extends State<_LastCardsHighlightHarness> {
  late int _handSize;

  @override
  void initState() {
    super.initState();
    _handSize = widget.initialHandSize;
  }

  void setHandSize(int n) => setState(() => _handSize = n);

  @override
  Widget build(BuildContext context) {
    return FloatingActionBarWidget(
      activePlayerName: 'Opponent',
      direction: PlayDirection.clockwise,
      canEndTurn: false,
      isLocalTurn: false,
      lastCardsEnabled: true,
      localHandSize: _handSize,
      onLastCards: () {},
    );
  }
}
