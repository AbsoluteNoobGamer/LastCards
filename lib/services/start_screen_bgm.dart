import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

bool _startScreenBgmLifecycleObserverRegistered = false;
final _startScreenBgmLifecycleObserver = _StartScreenBgmLifecycleObserver();

/// Registers once at startup ([main]) so [AppLifecycleState] is observed from process start.
void registerStartScreenBgmAppLifecycleObserver() {
  if (_startScreenBgmLifecycleObserverRegistered) return;
  WidgetsBinding.instance.addObserver(_startScreenBgmLifecycleObserver);
  _startScreenBgmLifecycleObserverRegistered = true;
}

class _StartScreenBgmLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    StartScreenBgm.instance.handleAppLifecycle(state);
  }
}

/// Looping background music for [LastCardsStartScreen].
///
/// **App switch:** Playback is fully torn down (player disposed) whenever the app is no
/// longer in the foreground, then restarted via [start] on [AppLifecycleState.resumed]
/// when the start screen is visible (not covered by another route). This avoids relying
/// on [AudioPlayer.pause] alone, which was unreliable on some Android devices.
///
/// Paused when another route covers the start screen ([RouteAware.didPushNext]); when
/// the route is shown again, [onRouteVisible] resumes or restarts playback.
///
/// **Web:** [start] is a no-op until [notifyUserGesture]; we do not auto-restart BGM on
/// tab focus (autoplay policy).
///
/// Stopped when the screen disposes ([stop]).
class StartScreenBgm {
  StartScreenBgm._();
  static final StartScreenBgm instance = StartScreenBgm._();

  AudioPlayer? _player;
  bool _started = false;
  bool _starting = false;
  bool _pausedByRoute = false;
  Timer? _inactivePauseTimer;
  /// Set when [_tearDownPlaybackForLeavingApp] actually disposed playback; used so
  /// [AppLifecycleState.resumed] does not call [start] on cold launch / splash.
  bool _stoppedDueToAppBackground = false;

  /// Incremented in [stop] and when tearing down for app background so in-flight [_startImpl] aborts.
  int _epoch = 0;

  /// 0.0–1.0; driven by Settings → Music Volume.
  double _musicVolume = 0.55;

  static const _assetPath = 'assets/audio/bgm/startscreen_bgm.mp3';

  void _cancelInactivePauseTimer() {
    _inactivePauseTimer?.cancel();
    _inactivePauseTimer = null;
  }

  Future<void> _disposePlayerAsync(AudioPlayer p) async {
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }

  /// Stops and disposes the player whenever the user leaves the app (another activity / home).
  void _tearDownPlaybackForLeavingApp() {
    _cancelInactivePauseTimer();
    if (_player == null && !_started && !_starting) return;
    _stoppedDueToAppBackground = true;
    _epoch++;
    _started = false;
    _starting = false;
    final p = _player;
    _player = null;
    if (p != null) {
      unawaited(_disposePlayerAsync(p));
    }
  }

  void _maybeRestartAfterReturningToApp() {
    if (!_stoppedDueToAppBackground || _pausedByRoute || kIsWeb) return;
    _stoppedDueToAppBackground = false;
    unawaited(start());
  }

  /// Called from [_StartScreenBgmLifecycleObserver] for every app transition.
  void handleAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _tearDownPlaybackForLeavingApp();
        return;
      case AppLifecycleState.resumed:
        _cancelInactivePauseTimer();
        _maybeRestartAfterReturningToApp();
        return;
      case AppLifecycleState.inactive:
        _cancelInactivePauseTimer();
        _inactivePauseTimer = Timer(const Duration(milliseconds: 280), () {
          _inactivePauseTimer = null;
          if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
            return;
          }
          _tearDownPlaybackForLeavingApp();
        });
        return;
      case AppLifecycleState.detached:
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
    if (_started || _starting || kIsWeb) return;
    await _startImpl();
  }

  /// Call on pointer down so web (and any platform) can start BGM after a gesture if needed.
  void notifyUserGesture() {
    if (_started || _starting) return;
    unawaited(_startImpl());
  }

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

  Future<void> _configureBgmAudioSession() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StartScreenBgm: AudioSession.configure failed: $e');
      }
    }
  }

  Future<void> _startImpl() async {
    if (_started || _starting) return;
    _starting = true;
    final myEpoch = _epoch;
    AudioPlayer? localPlayer;
    try {
      await _configureBgmAudioSession();
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
      if (_epoch == myEpoch) _starting = false;
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
    if (!_pausedByRoute) return;
    _pausedByRoute = false;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null &&
        (life == AppLifecycleState.paused ||
            life == AppLifecycleState.hidden ||
            life == AppLifecycleState.detached)) {
      return;
    }
    if (_player == null) {
      if (!kIsWeb) {
        await start();
      }
      return;
    }
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
    _starting = false;
    _pausedByRoute = false;
    _stoppedDueToAppBackground = false;
    _cancelInactivePauseTimer();
    _cancelInactivePauseTimer();
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
