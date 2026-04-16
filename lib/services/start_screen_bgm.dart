import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

/// Looping background music for [LastCardsStartScreen].
///
/// Uses [just_audio] instead of [audioplayers] for reliable long-asset playback
/// on Windows/desktop and consistent session handling on mobile.
///
/// Paused when another route covers the start screen ([RouteAware.didPushNext]);
/// resumed when returning ([RouteAware.didPopNext]). Paused when the app goes to
/// the background ([AppLifecycleState.paused]); resumed on [AppLifecycleState.resumed]
/// when the start screen route is still visible. Stopped when the screen disposes.
///
/// [onRouteCovered] / [onRouteVisible] are only wired from [RouteAware] on the start
/// screen; navigation while the app is fully backgrounded is not expected, but
/// [onRouteVisible] still checks [WidgetsBinding.lifecycleState] before playing so BGM
/// does not resume in [AppLifecycleState.paused] / [hidden] / [detached].
///
/// **Web:** autoplay is blocked until a user gesture — [start] is a no-op on web;
/// the first [notifyUserGesture] (pointer down on the start screen) begins playback.
class StartScreenBgm with WidgetsBindingObserver {
  StartScreenBgm._();
  static final StartScreenBgm instance = StartScreenBgm._();

  AudioPlayer? _player;
  bool _started = false;
  bool _starting = false;
  bool _pausedByRoute = false;
  bool _pausedByAppLifecycle = false;
  bool _lifecycleObserverAdded = false;

  /// Incremented in [stop] so in-flight [_startImpl] can detect cancellation after `await`.
  int _epoch = 0;

  /// 0.0–1.0; driven by Settings → Music Volume.
  double _musicVolume = 0.55;

  /// Full asset key as declared in pubspec (`assets/...`).
  static const _assetPath = 'assets/audio/bgm/startscreen_bgm.mp3';

  void _addLifecycleObserver() {
    if (_lifecycleObserverAdded || kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleObserverAdded = true;
  }

  void _removeLifecycleObserver() {
    if (!_lifecycleObserverAdded) return;
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleObserverAdded = false;
  }

  Future<void> _safePausePlayer() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.pause();
    } catch (_) {}
  }

  /// Clears [_pausedByAppLifecycle] only after a successful play.
  Future<void> _resumeAfterAppLifecyclePause() async {
    if (!_pausedByAppLifecycle || _pausedByRoute || !_started) return;
    final p = _player;
    if (p == null) return;
    try {
      await p.play();
      if (!_started || _pausedByRoute) return;
      _pausedByAppLifecycle = false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StartScreenBgm: resume after lifecycle pause failed: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _player == null || kIsWeb) return;
    switch (state) {
      case AppLifecycleState.paused:
        if (_pausedByRoute) return;
        _pausedByAppLifecycle = true;
        unawaited(_safePausePlayer());
        return;
      case AppLifecycleState.resumed:
        if (!_pausedByAppLifecycle || _pausedByRoute) return;
        unawaited(_resumeAfterAppLifecyclePause());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        return;
    }
  }

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
      _addLifecycleObserver();
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
    // Do not clear [_pausedByAppLifecycle] here: if the app was backgrounded first,
    // that flag must remain until [didChangeAppLifecycleState] / [onRouteVisible]
    // resumes playback at a safe time.
    try {
      await _player!.pause();
    } catch (_) {}
  }

  Future<void> onRouteVisible() async {
    if (!_pausedByRoute || _player == null) return;
    _pausedByRoute = false;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null &&
        (life == AppLifecycleState.paused ||
            life == AppLifecycleState.hidden ||
            life == AppLifecycleState.detached)) {
      _pausedByAppLifecycle = true;
      return;
    }
    try {
      await _player!.play();
      _pausedByAppLifecycle = false;
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
    _pausedByAppLifecycle = false;
    _removeLifecycleObserver();
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
