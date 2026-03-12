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
  static const Map<GameSound, String> _soundFiles = {
    GameSound.cardDraw: 'Draw-Card.wav',
    GameSound.cardPlace: 'card_place.wav',
    GameSound.specialTwo: 'special_two.wav',
    GameSound.specialBlackJack: 'special-black_jack.wav',
    GameSound.specialRedJack: 'special_red_jack.wav',
    GameSound.specialKing: 'special_king.wav',
    GameSound.specialAce: 'special_ace.wav',
    GameSound.specialQueen: 'special_queen.wav',
    GameSound.specialEight: 'special_eight.wav',
    GameSound.specialJoker: 'special_joker.wav',
    GameSound.penaltyDraw: 'penalty_draw.wav',
    GameSound.turnStart: 'turn_start.wav',
    GameSound.timerWarning: 'timer_warning.wav',
    GameSound.timerExpired: 'timer_expired.wav',
    GameSound.playerWin: 'player_win.wav',
    GameSound.playerLose: 'player_lose.wav',
    GameSound.tournamentQualify: 'tournament_qualify.wav',
    GameSound.tournamentEliminate: 'tournament_eliminate.wav',
    GameSound.tournamentWin: 'tournament_win.wav',
    GameSound.shuffleDeck: 'shuffle_deck.wav',
    GameSound.bustRoundStart: 'bust_round_start.wav',
    GameSound.bustRoundEnd: 'bust_round_end.wav',
    GameSound.skipApplied: 'skip_applied.wav',
    GameSound.directionReversed: 'direction_reversed.wav',
    GameSound.opponentOut: 'opponent_out.wav',
    // Note: cardSelect and endTurnButton wav files are currently missing from assets/audio/sfx/
  };

  // Category players: each owns a single AudioPlayer that is stopped then
  // replayed for every new sound in that category.  Separating categories
  // prevents a rapid-fire turnStart (produced by tournament skip chains) from
  // silently dropping UI or special-card sounds and vice-versa.
  //
  // Using explicit stop() → play() (rather than fire-and-forget) is intentional:
  // within each category only the most-recent sound matters, so earlier sounds
  // are cleanly cut and not left dangling.  The Android
  // prepareAsync-race-condition guard (the reason _playOneShotAsset still exists
  // for cardDraw/cardPlace) does NOT apply here because we call stop() ourselves
  // before play(); the problematic race only occurs when stop() is called from
  // the onPlayerComplete callback after the next play() has already started.
  AudioPlayer? _turnPlayer;
  AudioPlayer? _specialPlayer;
  AudioPlayer? _uiPlayer;

  SharedPreferences? _prefs;
  Set<String> _availableAssets = const <String>{};

  bool _initialized = false;
  bool _soundEffectsEnabled = true;
  double _volume = 0.5;

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
      _turnPlayer = AudioPlayer();
      _specialPlayer = AudioPlayer();
      _uiPlayer = AudioPlayer();
    } catch (_) {
      // Fail silently: missing assets or audio init should never crash gameplay.
    }

    _initialized = true;
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    _soundEffectsEnabled = enabled;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setBool(_prefsKeySfxEnabled, enabled);
    } catch (_) {
      // Persistence failures should not break runtime audio behavior.
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _turnPlayer?.setVolume(_volume);
    _specialPlayer?.setVolume(_volume);
    _uiPlayer?.setVolume(_volume);
  }

  Future<void> playSound(GameSound sound) async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    if (!_hasAssetFor(sound)) return;

    final assetSubpath = _assetSubpathFor(sound);

    switch (sound) {
      // ── Turn-start: isolated so rapid skip-chains don't stack ──────────────
      case GameSound.turnStart:
        await _playCategorySound(_turnPlayer, assetSubpath);

      // ── Special card sounds: their own lane so they survive turnStart ───────
      case GameSound.specialTwo:
      case GameSound.specialBlackJack:
      case GameSound.specialRedJack:
      case GameSound.specialKing:
      case GameSound.specialAce:
      case GameSound.specialQueen:
      case GameSound.specialEight:
      case GameSound.specialJoker:
        await _playCategorySound(_specialPlayer, assetSubpath);

      // ── UI / tournament sounds ──────────────────────────────────────────────
      case GameSound.tournamentQualify:
      case GameSound.tournamentEliminate:
      case GameSound.tournamentWin:
      case GameSound.timerWarning:
      case GameSound.timerExpired:
      case GameSound.shuffleDeck:
      case GameSound.penaltyDraw:
      case GameSound.bustRoundStart:
      case GameSound.bustRoundEnd:
      case GameSound.skipApplied:
      case GameSound.directionReversed:
        await _playCategorySound(_uiPlayer, assetSubpath);

      // ── High-frequency / burst sounds: fire-and-forget to avoid cut-offs ───
      case GameSound.cardDraw:
      case GameSound.cardPlace:
      case GameSound.playerWin:
      case GameSound.playerLose:
      case GameSound.opponentOut:
      case GameSound.endTurnButton:
      case GameSound.cardSelect:
        await _playOneShotAsset(assetSubpath);
    }
  }

  /// Plays a sound on a shared, persistent [AudioPlayer].
  ///
  /// Calls [AudioPlayer.stop] first to cleanly cancel any in-progress playback
  /// on that player before starting the new sound.  This is intentionally
  /// different from [_playOneShotAsset]: within a category only the latest
  /// sound matters, so earlier ones are cut.  Categories are kept separate so
  /// that, e.g., a tournamentQualify sound is never cut by turnStart.
  Future<void> _playCategorySound(
      AudioPlayer? player, String assetSubpath) async {
    if (player == null) return;
    try {
      await player.stop();
      await player.setVolume(_volume);
      await player.play(AssetSource(assetSubpath));
    } catch (e) {
      debugPrint('AudioService._playCategorySound($assetSubpath) error: $e');
    }
  }

  /// Releases all native audio resources.  Call when the owning widget tree is
  /// torn down (e.g. in [State.dispose]).
  Future<void> dispose() async {
    try {
      await _turnPlayer?.dispose();
      await _specialPlayer?.dispose();
      await _uiPlayer?.dispose();
    } catch (e) {
      debugPrint('AudioService.dispose error: $e');
    }
    _turnPlayer = null;
    _specialPlayer = null;
    _uiPlayer = null;
    _initialized = false;
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
      _availableAssets.contains('assets/audio/sfx/${_soundFiles[sound]}');

  String _assetSubpathFor(GameSound sound) => 'audio/sfx/${_soundFiles[sound]}';
}
