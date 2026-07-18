import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/theme/app_themes.dart';
import 'package:last_cards/features/chat/presentation/widgets/live_text_chat_panel.dart';

void main() {
  final theme = kAppThemes.first;

  testWidgets('composer is focusable inside a bounded table-sized panel',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 340,
              child: LiveTextChatPanel(
                theme: theme,
                messages: const [],
                onSend: (_) {},
                tall: true,
              ),
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'hello table');
    await tester.pump();

    expect(find.text('hello table'), findsOneWidget);
  });

  testWidgets('composer works with unbounded height (lobby scroll)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveTextChatPanel(
              theme: theme,
              messages: const [],
              onSend: (_) {},
              tall: true,
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'hello lobby');
    await tester.pump();

    expect(find.text('hello lobby'), findsOneWidget);
  });
}
