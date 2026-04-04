import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/features/gameplay/presentation/widgets/card_flip_widget.dart';

void main() {
  testWidgets('CardFlipWidget shows front or back per showFace', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CardFlipWidget(
            showFace: true,
            front: Text('FACE', key: Key('face')),
            back: Text('BACK', key: Key('back')),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('face')), findsOneWidget);
    expect(find.byKey(const Key('back')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CardFlipWidget(
            showFace: false,
            front: Text('FACE', key: Key('face')),
            back: Text('BACK', key: Key('back')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('back')), findsOneWidget);
  });
}
