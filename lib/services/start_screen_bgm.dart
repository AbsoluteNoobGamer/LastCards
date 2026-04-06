import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Looping background music for [LastCardsStartScreen].
///
/// Uses [just_audio] instead of [audioplayers] for reliable long-asset playback
/// on Windows/desktop and consistent session handling on mobile.
///
/// Paused when another route covers the start screen ([RouteAware.didPushNext]);
/// resumed when returning ([RouteAware.didPopNext]). Stopped when the screen disposes.
///
/// **Web:** autoplay is blocked until a user gesture — [start] is a no-op on web;
/// the first [notifyUserGesture] (pointer down on the start screen) begins playback.
class StartScreenBgm {
  StartScreenBgm._();
  static final StartScreenBgm instance = StartScreenBgm._();

  AudioPlayer? _player;
  bool _started = false;
  bool _starting = false;
  bool _pausedByRoute = false;

  /// Incremented in [stop] so in-flight [_startImpl] can detect cancellation after `await`.
  int _epoch = 0;

  /// 0.0–1.0; driven by Settings → Music Volume.
  double _musicVolume = 0.55;

  /// Full asset key as declared in pubspec (`assets/...`).
  static const _assetPath = 'assets/audio/bgm/startscreen_bgm.mp3';

  /// Updates BGM loudness (0.0–1.0).
  void setMusicVolume(double normalized) {
    _musicVolume = normalized.clamp(0.0, 1.0);
    final p = _player;
    if (p != null) {
      unawaited(p.setVolume(_musicVolume));
    }
  }

  /// Starts looping BGM. On web, does nothing — use [notifyUserGesture] after the user touches the screen.
  Future<void> start() async {
    if (_started || kIsWeb) return;
    await _startImpl();
  }

  /// Call on pointer down so web (and any platform) can start BGM after a gesture if needed.
  void notifyUserGesture() {
    if (_started) return;
    unawaited(_startImpl());
  }

  /// After [stop], returns true; [localPlayer] is cleared/disposed as needed.
  Future<bool> _abortIfStale(int myEpoch, AudioPlayer? localPlayer) async {
    if (_epoch == myEpoch) return false;
    if (_player == localPlayer) {
      _player = null;
    }
    try {
      await localPlayer?.dispose();
    } catch (_) {}
    return true;
  }

  Future<void> _startImpl() async {
    if (_started || _starting) return;
    _starting = true;
    final myEpoch = _epoch;
    AudioPlayer? localPlayer;
    try {
      localPlayer = AudioPlayer();
      await localPlayer.setAsset(_assetPath);
      if (await _abortIfStale(myEpoch, localPlayer)) return;

      await localPlayer.setLoopMode(LoopMode.one);
      if (await _abortIfStale(myEpoch, localPlayer)) return;

      await localPlayer.setVolume(_musicVolume);
      if (await _abortIfStale(myEpoch, localPlayer)) return;

      _player = localPlayer;
      await localPlayer.play();
      if (await _abortIfStale(myEpoch, localPlayer)) return;

      _started = true;
      if (kDebugMode) {
        debugPrint('StartScreenBgm: playing $_assetPath at volume $_musicVolume');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('StartScreenBgm._startImpl failed: $e\n$st');
      }
      _started = false;
      if (_player == localPlayer) {
        _player = null;
      }
      try {
        await localPlayer?.dispose();
      } catch (_) {}
    } finally {
      _starting = false;
    }
  }

  Future<void> onRouteCovered() async {
    if (!_started || _player == null) return;
    _pausedByRoute = true;
    try {
      await _player!.pause();
    } catch (_) {}
  }

  Future<void> onRouteVisible() async {
    if (!_pausedByRoute || _player == null) return;
    _pausedByRoute = false;
    try {
      await _player!.play();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StartScreenBgm.onRouteVisible play failed: $e');
      }
    }
  }

  Future<void> stop() async {
    _epoch++;
    _started = false;
    _pausedByRoute = false;
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
