import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/settings/presentation/widgets/settings_modal.dart';

import '../../../helpers/mock_audio_platform.dart';

Future<void> _waitForAsyncInit() async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

Future<void> _waitForSettingsInit(ProviderContainer container) async {
  container.read(settingsProvider);
  await _waitForAsyncInit();
}

Future<void> _waitForAudioInit(ProviderContainer container) async {
  container.read(audioServiceProvider);
  await _waitForAsyncInit();
}

Finder _switchByTitle(String title) {
  final tile = find.widgetWithText(SwitchListTile, title);
  return find.descendant(
    of: tile,
    matching: find.byType(Switch),
  );
}

bool _switchValue(WidgetTester tester, Finder switchFinder) {
  return tester.widget<Switch>(switchFinder).value;
}

Future<void> _pumpSettingsModal(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: const SettingsModal(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await tester.drag(scrollables.last, const Offset(0, -700));
    await tester.pump();
  }
}

class _SpyAudioService extends AudioService {
  int setSoundEffectsEnabledCallCount = 0;
  bool? lastSetSoundEffectsEnabled;

  @override
  Future<void> setSoundEffectsEnabled(bool enabled) async {
    setSoundEffectsEnabledCallCount++;
    lastSetSoundEffectsEnabled = enabled;
    await super.setSoundEffectsEnabled(enabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAudioChannels();
  });

  group('SettingsNotifier (unit)', () {
    test('loads default values when SharedPreferences has no stored data',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForSettingsInit(container);

      final state = container.read(settingsProvider);
      expect(state.soundVolume, 100.0);
      expect(state.timerTickVolume, 65.0);
      expect(state.musicVolume, 55.0);
      expect(state.reduceMotion, isFalse);
      expect(state.budgetDeviceMode, isFalse);
    });

    test('setReduceMotion(true) persists true to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForSettingsInit(container);

      container.read(settingsProvider.notifier).setReduceMotion(true);

      expect(container.read(settingsProvider).reduceMotion, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reduceMotion'), isTrue);
    });

    test('setReduceMotion(false) persists false', () async {
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForSettingsInit(container);

      container.read(settingsProvider.notifier).setReduceMotion(false);

      expect(container.read(settingsProvider).reduceMotion, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reduceMotion'), isFalse);
    });

    test('setBudgetDeviceMode(true) persists and updates provider state',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForSettingsInit(container);

      container.read(settingsProvider.notifier).setBudgetDeviceMode(true);

      expect(container.read(settingsProvider).budgetDeviceMode, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('budget_device_mode'), isTrue);
    });

    test('updateSound persists volume to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForSettingsInit(container);

      container.read(settingsProvider.notifier).updateSound(75.0);

      expect(container.read(settingsProvider).soundVolume, 75.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('soundVolume'), 75.0);
    });

    test('toggleMute persists the new mute state via AudioService', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForAudioInit(container);

      final audio = container.read(audioServiceProvider);
      expect(audio.soundEffectsEnabled, isTrue);

      await audio.setSoundEffectsEnabled(false);
      await _waitForAsyncInit();

      expect(audio.soundEffectsEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound_effects_enabled'), isFalse);
      expect(prefs.getBool('audio_muted'), isTrue);
    });

    test('reading provider after each set returns updated value not stale',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForSettingsInit(container);

      container.read(settingsProvider.notifier).setReduceMotion(true);
      expect(container.read(settingsProvider).reduceMotion, isTrue);

      container.read(settingsProvider.notifier).setBudgetDeviceMode(true);
      expect(container.read(settingsProvider).budgetDeviceMode, isTrue);

      container.read(settingsProvider.notifier).setReduceMotion(false);
      expect(container.read(settingsProvider).reduceMotion, isFalse);

      container.read(settingsProvider.notifier).setBudgetDeviceMode(false);
      expect(container.read(settingsProvider).budgetDeviceMode, isFalse);
    });
  });

  group('SettingsModal (widget)', () {
    testWidgets('toggle switches reflect first-launch defaults', (tester) async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => _SpyAudioService()),
        ],
      );
      addTearDown(container.dispose);

      await _pumpSettingsModal(tester, container: container);
      await tester.pump(const Duration(milliseconds: 100));

      expect(_switchValue(tester, _switchByTitle('Reduce Motion')), isFalse);
      expect(_switchValue(tester, _switchByTitle('Lower Performance')), isFalse);
      expect(
        _switchValue(tester, _switchByTitle('Enable Sound Effects')),
        isTrue,
      );
      expect(
        _switchValue(tester, _switchByTitle('Animated Card Effects')),
        isTrue,
      );
    });

    testWidgets('tapping Reduce Motion updates switch and provider state',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => _SpyAudioService()),
        ],
      );
      addTearDown(container.dispose);

      await _pumpSettingsModal(tester, container: container);

      await tester.tap(_switchByTitle('Reduce Motion'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_switchValue(tester, _switchByTitle('Reduce Motion')), isTrue);
      expect(container.read(settingsProvider).reduceMotion, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reduceMotion'), isTrue);
    });

    testWidgets('tapping Enable Sound Effects calls setSoundEffectsEnabled',
        (tester) async {
      final spy = _SpyAudioService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      await _pumpSettingsModal(tester, container: container);
      await tester.pump(const Duration(milliseconds: 100));
      spy.setSoundEffectsEnabledCallCount = 0;

      await tester.tap(_switchByTitle('Enable Sound Effects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(spy.setSoundEffectsEnabledCallCount, 1);
      expect(spy.lastSetSoundEffectsEnabled, isFalse);
      expect(_switchValue(tester, _switchByTitle('Enable Sound Effects')), isFalse);
    });
  });
}
