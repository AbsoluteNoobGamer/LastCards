import 'dart:async';

import 'package:flame_audio/bgm.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
/// Uses [FlameAudio.bgm] for playback. We intentionally do **not** call
/// [Bgm.initialize], so Flame's built-in lifecycle observer is not registered;
/// this class keeps its own aggressive teardown (stop, not dispose of the
/// global [Bgm]) when the app leaves the foreground.
///
/// **App switch:** [FlameAudio.bgm.stop] whenever the app is no longer in the
/// foreground, then [start] on [AppLifecycleState.resumed] when the start
/// screen is visible (not covered by another route).
///
/// **Opaque routes:** A [NavigatorObserver] ([startScreenBgmNavigatorObserver]) stops
/// BGM when a non-[PopupRoute] (e.g. table, profile) is pushed. Modal bottom sheets
/// are [PopupRoute]s and do **not** stop BGM. When that overlay is popped, the start
/// route’s [RouteAware.didPopNext] calls [notifyStartMenuExposedFromOpaqueChild] to
/// resume BGM if needed.
///
/// **Web:** [start] is a no-op until [notifyUserGesture]; we do not auto-restart BGM on
/// tab focus (autoplay policy).
///
/// Stopped when the screen disposes ([stop]).
class StartScreenBgm {
  StartScreenBgm._();
  static final StartScreenBgm instance = StartScreenBgm._();

  Bgm get _bgm => FlameAudio.bgm;

  bool _started = false;
  bool _starting = false;
  /// True while a fullscreen navigator route (non-[PopupRoute]) may be above the
  /// start menu—blocks [start] on app resume; see [notifyOpaqueNavigatorRoutePushed].
  bool _coveredByOpaqueNavigatorRoute = false;
  Timer? _inactivePauseTimer;
  /// Set when [_tearDownPlaybackForLeavingApp] actually stopped playback; used so
  /// [AppLifecycleState.resumed] does not call [start] on cold launch / splash.
  bool _stoppedDueToAppBackground = false;

  /// Incremented in [stop] and when tearing down for app background so in-flight [_startImpl] aborts.
  int _epoch = 0;

  /// 0.0–1.0; driven by Settings → Music Volume.
  double _musicVolume = 0.55;

  AudioContext _bgmPlaybackContext() {
    return AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
      ),
    );
  }

  void _cancelInactivePauseTimer() {
    _inactivePauseTimer?.cancel();
    _inactivePauseTimer = null;
  }

  /// Stops BGM when the user leaves the app (another activity / home).
  void _tearDownPlaybackForLeavingApp() {
    _cancelInactivePauseTimer();
    if (!_started && !_starting) return;
    _stoppedDueToAppBackground = true;
    _epoch++;
    _started = false;
    _starting = false;
    unawaited(_bgmStopSafe());
  }

  Future<void> _bgmStopSafe() async {
    try {
      await _bgm.stop();
    } catch (_) {}
  }

  void _maybeRestartAfterReturningToApp() {
    if (!_stoppedDueToAppBackground ||
        _coveredByOpaqueNavigatorRoute ||
        kIsWeb) {
      return;
    }
    _stoppedDueToAppBackground = false;
    unawaited(start());
  }

  /// Called from [_StartScreenBgmLifecycleObserver] for every app transition.
  void handleAppLifecycle(AppLifecycleState state) {
    if (kIsWeb) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _tearDownPlaybackForLeavingApp();
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
    unawaited(_bgm.audioPlayer.setVolume(_musicVolume));
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

  Future<void> _startImpl() async {
    if (_started || _starting) return;
    _starting = true;
    final myEpoch = _epoch;
    try {
      final ap = _bgm.audioPlayer;
      await ap.setAudioContext(_bgmPlaybackContext());
      if (_epoch != myEpoch) return;

      await ap.setPlayerMode(PlayerMode.mediaPlayer);
      if (_epoch != myEpoch) return;

      await _bgm.play('bgm/startscreen_bgm.mp3', volume: _musicVolume);
      if (_epoch != myEpoch) {
        await _bgmStopSafe();
        return;
      }

      _started = true;
      if (kDebugMode) {
        debugPrint(
          'StartScreenBgm: FlameAudio.bgm playing bgm/startscreen_bgm.mp3 at volume $_musicVolume',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('StartScreenBgm._startImpl failed: $e\n$st');
      }
      _started = false;
      await _bgmStopSafe();
    } finally {
      if (_epoch == myEpoch) _starting = false;
    }
  }

  /// [StartScreenBgmNavigatorObserver] calls this when e.g. [TableScreen] is pushed.
  void notifyOpaqueNavigatorRoutePushed() {
    _coveredByOpaqueNavigatorRoute = true;
    _started = false;
    _starting = false;
    unawaited(_bgmStopSafe());
  }

  /// Start route’s [RouteAware.didPopNext]: a route pushed on top of [/start] was popped;
  /// restart menu BGM when appropriate.
  Future<void> notifyStartMenuExposedFromOpaqueChild() async {
    _coveredByOpaqueNavigatorRoute = false;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null &&
        (life == AppLifecycleState.paused ||
            life == AppLifecycleState.hidden ||
            life == AppLifecycleState.detached)) {
      return;
    }
    if (!kIsWeb) {
      await start();
    }
  }

  Future<void> stop() async {
    _epoch++;
    _started = false;
    _starting = false;
    _coveredByOpaqueNavigatorRoute = false;
    _stoppedDueToAppBackground = false;
    _cancelInactivePauseTimer();

    await _bgmStopSafe();
  }
}
