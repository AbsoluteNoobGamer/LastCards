import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/core/services/tutorial_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shouldShowFirstLaunchPrompt returns true once then false', () async {
    SharedPreferences.setMockInitialValues({});
    final service = TutorialService.instance;

    expect(await service.shouldShowFirstLaunchPrompt(), isTrue);
    expect(await service.shouldShowFirstLaunchPrompt(), isFalse);
  });

  test('a fresh install with the flag already set never shows the prompt', () async {
    SharedPreferences.setMockInitialValues({'tutorial_prompt_shown': true});
    final service = TutorialService.instance;

    expect(await service.shouldShowFirstLaunchPrompt(), isFalse);
  });
}
