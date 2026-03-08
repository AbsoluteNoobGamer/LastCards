import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_sound.dart';

class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  static const String _prefsKeySfxEnabled = 'sound_effects_enabled';
  static const String _bgmAssetSubpath = 'audio/sfx/bgm.wav';
  static const Map<GameSound, String> _soundFiles = {
    GameSound.cardDraw: 'sfx/Draw-Card.wav',
    GameSound.cardPlace: 'sfx/card_place.wav',
    GameSound.specialTwo: 'sfx/special_two.wav',
    GameSound.specialBlackJack: 'sfx/special-black_jack.wav',
    GameSound.specialRedJack: 'sfx/special_red_jack.wav',
    GameSound.specialKing: 'sfx/special_king.wav',
    GameSound.specialAce: 'sfx/special_ace.wav',
    GameSound.specialQueen: 'sfx/special_queen.wav',
    GameSound.specialEight: 'sfx/special_eight.wav',
    GameSound.specialJoker: 'sfx/special_joker.wav',
    GameSound.penaltyDraw: 'sfx/penalty_draw.wav',
    GameSound.turnStart: 'sfx/turn_start.wav',
    GameSound.timerWarning: 'sfx/timer_warning.wav',
    GameSound.timerExpired: 'sfx/timer_expired.wav',
    GameSound.playerWin: 'sfx/player_win.wav',
    GameSound.tournamentQualify: 'sfx/tournament_qualify.wav',
    GameSound.tournamentEliminate: 'sfx/tournament_eliminate.wav',
    GameSound.tournamentWin: 'sfx/tournament_win.wav',
    GameSound.shuffleDeck: 'sfx/shuffle_deck.wav',
  };

  // Dedicated looping player for background music only.
  // SFX use fire-and-forget players (see _playOneShotAsset) to avoid the
  // AudioPool / single-player ReleaseMode.stop re-prepare race condition that
  // causes IllegalStateException (prepareAsync called on wrong state) on Android.
  AudioPlayer? _bgmPlayer;
  SharedPreferences? _prefs;
  Set<String> _availableAssets = const <String>{};

  bool _initialized = false;
  bool _soundEffectsEnabled = true;
  bool _bgmActive = false;
  double _volume = 1.0;

  // Tracks in-flight SFX players. Opening too many native MediaPlayers
  // simultaneously exhausts the Android audio session, causing ENODEV (-19)
  // errors on subsequent plays. Cap at a reasonable number for a card game.
  int _activeSfxCount = 0;
  static const int _maxConcurrentSfx = 6;

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  double get volume => _volume;

  Future<void> init() async {
    if (_initialized) return;

    // In pure Dart/unit tests the binding may be unavailable.
    // If so, skip audio initialization silently.
    try {
      ServicesBinding.instance;
    } catch (_) {
      return;
    }

    try {
      _prefs = await SharedPreferences.getInstance();
      _soundEffectsEnabled = _prefs?.getBool(_prefsKeySfxEnabled) ?? true;
      _availableAssets = await _loadAudioAssets();
      _bgmPlayer = AudioPlayer();
    } catch (_) {
      // Fail silently: missing assets or audio init should never crash gameplay.
    }

    _initialized = true;
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    _soundEffectsEnabled = enabled;
    if (!enabled) {
      await stopBgm();
    }
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setBool(_prefsKeySfxEnabled, enabled);
    } catch (_) {
      // Persistence failures should not break runtime audio behavior.
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
  }

  /// Starts looping background music. Safe to call multiple times — re-entrant
  /// calls while BGM is already active are ignored.
  Future<void> startBgm() async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    if (_bgmActive) return;
    if (!_availableAssets.contains('assets/$_bgmAssetSubpath')) {
      debugPrint('AudioService.startBgm: asset not found — $_bgmAssetSubpath');
      return;
    }

    try {
      final player = _bgmPlayer;
      if (player == null) return;

      // Dispose and recreate the BGM player to guarantee a clean MediaPlayer
      // state regardless of what happened previously.
      await player.dispose();
      _bgmPlayer = AudioPlayer();

      // Absorb mid-playback platform errors so they never become unhandled
      // exceptions. In audioplayers 6.x platform errors propagate as stream
      // errors on eventStream; any listener without onError: forwards the error
      // to the Zone handler, which rethrows it as an unhandled exception and
      // crashes the app. Subscribing with onError: absorbs them for our listener.
      _bgmPlayer!.eventStream.listen(
        (_) {},
        onError: (Object e) {
          debugPrint('AudioService BGM error: $e');
          _bgmActive = false;
        },
      );

      await _bgmPlayer!.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer!.setVolume(0.3);
      await _bgmPlayer!.play(AssetSource(_bgmAssetSubpath));
      _bgmActive = true;
    } catch (e) {
      debugPrint('AudioService.startBgm error: $e');
      _bgmActive = false;
    }
  }

  /// Stops background music. Safe to call even if nothing is playing.
  Future<void> stopBgm() async {
    _bgmActive = false;
    try {
      await _bgmPlayer?.stop();
    } catch (e) {
      debugPrint('AudioService.stopBgm error: $e');
    }
  }

  Future<void> playSound(GameSound sound) async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    if (!_hasAssetFor(sound)) return;
    await _playOneShotAsset(_assetSubpathFor(sound));
  }

  /// Creates a fresh [AudioPlayer] for every SFX play and disposes it after
  /// completion. This is the only safe pattern on Android: reusing a single
  /// player or using AudioPool both trigger a ReleaseMode.stop re-prepare cycle
  /// (onCompletion → stop() → prepareAsync()) that races with the next play()
  /// call and causes a fatal IllegalStateException in MediaPlayer.
  Future<void> _playOneShotAsset(String assetSubpath) async {
    // Drop the sound if too many players are already open. Exceeding Android's
    // audio session capacity causes MEDIA_ERROR_UNKNOWN ENODEV (-19) errors on
    // the next open, so backpressure here prevents the cascade.
    if (_activeSfxCount >= _maxConcurrentSfx) return;
    _activeSfxCount++;

    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(_volume);
      // CRITICAL: subscribe with onError: before calling play().
      // In audioplayers 6.x, platform errors (e.g. MEDIA_ERROR_UNKNOWN extra:-19
      // = ENODEV / audio focus loss) arrive as stream errors on eventStream after
      // play() has already resolved — the try/catch below does NOT cover them.
      // For broadcast streams, any listener without onError: forwards the error
      // to the Zone handler, which rethrows it as an unhandled exception and
      // crashes the app. onPlayerComplete is derived from eventStream via .where()
      // so stream errors propagate through it too; adding onError: here absorbs
      // them for our subscription.
      // onError must also dispose the player to avoid a native resource leak.
      player.onPlayerComplete.listen(
        (_) {
          _activeSfxCount--;
          player!.dispose().catchError((_) {});
        },
        onError: (Object e) {
          _activeSfxCount--;
          debugPrint('AudioService SFX error ($assetSubpath): $e');
          player!.dispose().catchError((_) {});
        },
      );
      await player.play(AssetSource(assetSubpath));
    } catch (e) {
      _activeSfxCount--;
      player?.dispose().catchError((_) {});
      debugPrint('AudioService._playOneShotAsset($assetSubpath) error: $e');
    }
  }

  Future<Set<String>> _loadAudioAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((path) => path.startsWith('assets/audio/'))
          .toSet();
    } catch (_) {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = jsonDecode(manifestJson);
      return manifest.keys
          .where((path) => path.startsWith('assets/audio/'))
          .toSet();
    }
  }

  bool _hasAssetFor(GameSound sound) =>
      _availableAssets.contains('assets/audio/${_soundFiles[sound]}');

  String _assetSubpathFor(GameSound sound) => 'audio/${_soundFiles[sound]}';
}
