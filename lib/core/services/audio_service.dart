import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/connection_provider.dart';

final audioServiceProvider = ChangeNotifierProvider<AudioService>((ref) {
  return AudioService();
});

class AudioService extends ChangeNotifier {
  static const _prefsKeyMuted = 'audio_muted';

  AudioPlayer? _bgmPlayer;
  AudioPlayer? _sfxPlayer;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  AudioService() {
    try {
      _bgmPlayer = AudioPlayer();
      _sfxPlayer = AudioPlayer();
      _sfxPlayer?.setPlayerMode(PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('AudioPlayer failed to init. (Normal in unit tests): $e');
    }
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isMuted = prefs.getBool(_prefsKeyMuted) ?? false;
    _applyMuteState();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyMuted, _isMuted);
    _applyMuteState();
    notifyListeners();
  }

  void _applyMuteState() {
    final volume = _isMuted ? 0.0 : 1.0;
    // BGM should be slightly quieter than SFX
    _bgmPlayer?.setVolume(_isMuted ? 0.0 : 0.4);
    _sfxPlayer?.setVolume(volume);
  }

  Future<void> startBgm() async {
    await _bgmPlayer?.setReleaseMode(ReleaseMode.loop);
    await _bgmPlayer?.play(AssetSource('audio/bgm.wav'));
    _applyMuteState(); // Ensure correct volume is applied when starting
  }

  Future<void> stopBgm() async {
    await _bgmPlayer?.stop();
  }

  Future<void> playClick() async {
    if (_isMuted) return;
    await _sfxPlayer?.play(AssetSource('audio/swoosh.wav'));
  }

  Future<void> playDrag() async {
    if (_isMuted) return;
    await _sfxPlayer?.play(AssetSource('audio/drag.wav'));
  }

  @override
  void dispose() {
    _bgmPlayer?.dispose();
    _sfxPlayer?.dispose();
    super.dispose();
  }
}
