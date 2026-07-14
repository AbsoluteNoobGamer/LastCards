import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/core/services/guest_rename_prompt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shouldShowFirstLaunchPrompt returns true once then false', () async {
    SharedPreferences.setMockInitialValues({});
    final service = GuestRenamePromptService.instance;

    expect(await service.shouldShowFirstLaunchPrompt(), isTrue);
    expect(await service.shouldShowFirstLaunchPrompt(), isFalse);
  });

  test('a fresh install with the flag already set never shows the prompt', () async {
    SharedPreferences.setMockInitialValues({'guest_rename_prompt_shown': true});
    final service = GuestRenamePromptService.instance;

    expect(await service.shouldShowFirstLaunchPrompt(), isFalse);
  });
}
