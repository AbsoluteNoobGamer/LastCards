import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/audio_service.dart' as app_audio;

final audioServiceProvider = ChangeNotifierProvider<AudioService>((ref) {
  return AudioService();
});

class AudioService extends ChangeNotifier {
  static const _prefsKeyMuted = 'audio_muted';
  static const _prefsKeySfxEnabled = 'sound_effects_enabled';
  static const _prefsKeySoundVolume = 'soundVolume';

  AudioService() {
    _init();
  }

  bool _soundEffectsEnabled = true;
  bool get soundEffectsEnabled => _soundEffectsEnabled;

  @Deprecated('Use soundEffectsEnabled instead.')
  bool get isMuted => !_soundEffectsEnabled;

  Future<void> _init() async {
    await app_audio.AudioService.instance.init();
    final prefs = await SharedPreferences.getInstance();

    // Restore persisted volume (0–100 stored, 0.0–1.0 used by the player).
    final savedVolume = prefs.getDouble(_prefsKeySoundVolume) ?? 100.0;
    app_audio.AudioService.instance.setVolume(savedVolume / 100.0);

    // Resolve enabled/disabled state.
    // Priority: new key → legacy key → default true.
    final bool enabled;
    if (prefs.containsKey(_prefsKeySfxEnabled)) {
      enabled = prefs.getBool(_prefsKeySfxEnabled) ?? true;
    } else if (prefs.containsKey(_prefsKeyMuted)) {
      enabled = !(prefs.getBool(_prefsKeyMuted) ?? false);
    } else {
      enabled = true;
    }
    await setSoundEffectsEnabled(enabled);
  }

  @Deprecated('Use setSoundEffectsEnabled(bool) instead.')
  Future<void> toggleMute() async {
    await setSoundEffectsEnabled(!_soundEffectsEnabled);
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    _soundEffectsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeySfxEnabled, enabled);
    await prefs.setBool(_prefsKeyMuted, !enabled);
    await app_audio.AudioService.instance.setSoundEffectsEnabled(enabled);
    notifyListeners();
  }
}
