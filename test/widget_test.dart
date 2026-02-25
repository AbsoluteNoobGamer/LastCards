import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StackAndFlowApp());

    // Basic check: verify some initial text or widget if appropriate.
    // For now, just ensure it pumps without crashing.
    expect(find.byType(StackAndFlowApp), findsOneWidget);
  });
}
