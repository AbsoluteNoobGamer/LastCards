import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/connection_provider.dart';

final audioServiceProvider = ChangeNotifierProvider<AudioService>((ref) {
  return AudioService();
});

class AudioService extends ChangeNotifier {
  static const _prefsKeyMuted = 'audio_muted';
  static const Set<String> _generatedAssets = {
    'assets/audio/bgm.wav',
    'assets/audio/swoosh.wav',
    'assets/audio/drag.wav',
    'assets/audio/click.wav',
  };

  AudioPlayer? _bgmPlayer;
  AudioPlayer? _sfxPlayer;
  AudioPlayer? _dealPlayer;
  String? _bgmAssetPath;
  String? _dealCardAssetPath;
  String? _clickAssetPath;
  String? _dragAssetPath;
  final Random _rng = Random();

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  AudioService() {
    try {
      _bgmPlayer = AudioPlayer();
      _sfxPlayer = AudioPlayer();
      _dealPlayer = AudioPlayer();
      _sfxPlayer?.setPlayerMode(PlayerMode.lowLatency);
      _dealPlayer?.setPlayerMode(PlayerMode.lowLatency);
      _dealPlayer?.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('AudioPlayer failed to init. (Normal in unit tests): $e');
    }
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isMuted = prefs.getBool(_prefsKeyMuted) ?? false;
    await _resolveManualAudioAssets();
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
    _dealPlayer?.setVolume(volume);
  }

  Future<void> startBgm() async {
    if (_bgmAssetPath == null) return;
    await _bgmPlayer?.setReleaseMode(ReleaseMode.loop);
    await _bgmPlayer?.play(AssetSource(_bgmAssetPath!));
    _applyMuteState(); // Ensure correct volume is applied when starting
  }

  Future<void> stopBgm() async {
    await _bgmPlayer?.stop();
  }

  Future<void> playClick() async {
    if (_isMuted) return;
    if (_clickAssetPath == null) {
      await _resolveManualAudioAssets();
      if (_clickAssetPath == null) return;
    }
    await _sfxPlayer?.play(AssetSource(_clickAssetPath!));
  }

  Future<void> playDealCard() async {
    if (_isMuted) return;
    if (_dealCardAssetPath == null) {
      await _resolveManualAudioAssets();
      if (_dealCardAssetPath == null) return;
    }
    final pitch = 0.96 + (_rng.nextDouble() * 0.08); // 0.96..1.04
    final gain = 0.92 + (_rng.nextDouble() * 0.08); // 0.92..1.00
    try {
      await _dealPlayer?.setPlaybackRate(pitch);
    } catch (_) {
      // Some platforms/backends may not support variable playback rate.
    }
    await _dealPlayer?.setVolume(gain);
    await _dealPlayer?.stop();
    await _dealPlayer?.play(AssetSource(_dealCardAssetPath!));
  }

  Future<void> playDrag() async {
    if (_isMuted) return;
    if (_dragAssetPath == null) {
      await _resolveManualAudioAssets();
      if (_dragAssetPath == null) return;
    }
    await _sfxPlayer?.play(AssetSource(_dragAssetPath!));
  }

  Future<void> _resolveManualAudioAssets() async {
    try {
      List<String> audioAssets = [];
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        audioAssets = manifest
            .listAssets()
            .where((assetPath) => assetPath.startsWith('assets/audio/'))
            .where((assetPath) => !_generatedAssets.contains(assetPath))
            .toList();
      } catch (_) {
        final manifestJson = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifest = jsonDecode(manifestJson);
        audioAssets = manifest.keys
            .where((assetPath) => assetPath.startsWith('assets/audio/'))
            .where((assetPath) => !_generatedAssets.contains(assetPath))
            .toList();
      }

      _bgmAssetPath = _pickAsset(audioAssets, const [
        'bgm',
        'music',
        'theme',
        'loop',
      ]);
      _dealCardAssetPath = _pickAsset(audioAssets, const [
        'dealcard',
      ]);
      _clickAssetPath = _pickAsset(audioAssets, const [
        'click',
        'tap',
        'press',
        'play',
        'card',
      ]);
      _dragAssetPath = _pickAsset(audioAssets, const [
        'drag',
        'move',
        'slide',
        'drop',
        'swipe',
      ]);
    } catch (_) {
      // In tests or early startup, the manifest may be unavailable.
      _bgmAssetPath = null;
      _dealCardAssetPath = null;
      _clickAssetPath = null;
      _dragAssetPath = null;
    }
  }

  String? _pickAsset(List<String> audioAssets, List<String> keywords) {
    for (final keyword in keywords) {
      final matched = audioAssets.firstWhere(
        (assetPath) => assetPath.toLowerCase().contains(keyword),
        orElse: () => '',
      );
      if (matched.isNotEmpty) {
        return matched.replaceFirst('assets/', '');
      }
    }
    return audioAssets.isNotEmpty
        ? audioAssets.first.replaceFirst('assets/', '')
        : null;
  }

  @override
  void dispose() {
    _bgmPlayer?.dispose();
    _sfxPlayer?.dispose();
    _dealPlayer?.dispose();
    super.dispose();
  }
}
