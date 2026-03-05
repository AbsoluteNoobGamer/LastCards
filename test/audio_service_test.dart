import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deck_drop/core/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // Mock the audioplayers MethodChannels heavily used during init/play
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
  });

  test('AudioService initializes with mute false', () async {
    final service = AudioService();
    // Wait for async init
    await Future.delayed(const Duration(milliseconds: 50));
    expect(service.isMuted, false);
  });

  test('AudioService toggles mute state and notifies listeners', () async {
    final service = AudioService();
    await Future.delayed(const Duration(milliseconds: 50));

    // Check initial state
    expect(service.isMuted, false);

    bool notified = false;
    service.addListener(() {
      notified = true;
    });

    // Toggle mute
    await service.toggleMute();

    // Check new state
    expect(service.isMuted, true);
    expect(notified, true);

    // Verify it saved to prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('audio_muted'), true);
  });
}
