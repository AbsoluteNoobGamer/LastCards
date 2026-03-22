import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/features/settings/presentation/widgets/settings_modal.dart';

import '../helpers/mock_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAudioChannels();
  });

  test('defaults to soundVolume=100 and reduceMotion=false', () async {
    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.soundVolume, 100.0);
    expect(notifier.state.reduceMotion, isFalse);
  });

  test('setReduceMotion persists to SharedPreferences', () async {
    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    notifier.setReduceMotion(true);
    expect(notifier.state.reduceMotion, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reduceMotion'), isTrue);
  });

  test('updateSound persists volume to SharedPreferences', () async {
    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    notifier.updateSound(75.0);
    expect(notifier.state.soundVolume, 75.0);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('soundVolume'), 75.0);
  });

  test('restores saved values on init', () async {
    SharedPreferences.setMockInitialValues({
      'soundVolume': 42.0,
      'reduceMotion': true,
    });
    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.soundVolume, 42.0);
    expect(notifier.state.reduceMotion, isTrue);
  });
}
