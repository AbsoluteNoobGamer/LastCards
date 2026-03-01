import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/audio_service.dart' as app_audio;
import '../../services/game_sound.dart';

final audioServiceProvider = ChangeNotifierProvider<AudioService>((ref) {
  return AudioService();
});

class AudioService extends ChangeNotifier {
  static const _prefsKeyMuted = 'audio_muted';
  static const _prefsKeySfxEnabled = 'sound_effects_enabled';

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
    final hasLegacyMute = prefs.containsKey(_prefsKeyMuted);
    final enabled = hasLegacyMute
        ? !(prefs.getBool(_prefsKeyMuted) ?? false)
        : app_audio.AudioService.instance.soundEffectsEnabled;
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

  Future<void> startBgm() async {}

  Future<void> stopBgm() async {}

  Future<void> playDealCard() async {
    await app_audio.AudioService.instance.playSound(GameSound.cardDraw);
  }

  Future<void> playClick() async {
    await app_audio.AudioService.instance.playSound(GameSound.cardPlace);
  }

  Future<void> playDrag() async {
    await app_audio.AudioService.instance.playSound(GameSound.cardDraw);
  }

  @override
  void dispose() => super.dispose();
}
