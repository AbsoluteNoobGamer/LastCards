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
  /// 0–100 in [SharedPreferences]; multiplied with master SFX volume for [GameSound.timerTick] only.
  static const String _prefsKeyTimerTickVolume = 'timer_tick_volume';
  static const Map<GameSound, String> _soundFiles = {
    GameSound.cardDraw: 'Draw-Card.wav',
    GameSound.dealCard: 'deal_card.wav', // Add your deal sound to assets/audio/sfx/
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
    GameSound.timerTick: 'timer_tick.wav',
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
    GameSound.cardSelect: 'card_select.wav',
    GameSound.endTurnButton: 'end_turn-button.wav',
  };

  // Category players: each owns a single AudioPlayer that is stopped then
  // replayed for every new sound in that category.  Separating categories
  // prevents a rapid-fire turnStart (produced by tournament skip chains) from
  // silently dropping UI or special-card sounds and vice-versa.
  //
  // Using explicit stop() → play() is intentional: within each category only
  // the most-recent sound matters, so earlier sounds are cleanly cut.
  AudioPlayer? _turnPlayer;
  AudioPlayer? _specialPlayer;
  AudioPlayer? _uiPlayer;

  // Card-draw pool: allows overlapping plays during deal animations.
  // Without this, rapid playSound(cardDraw) calls would stop the previous
  // before it's heard. Rotating through 3 players lets each play to completion.
  static const int _cardDrawPoolSize = 3;
  final List<AudioPlayer> _cardDrawPlayers = [];
  int _cardDrawPoolIndex = 0;

  /// Timer ticks once per second; use a small pool without stop→play so other
  /// SFX on category players never preempt the tick via a shared stop path.
  static const int _timerTickPoolSize = 2;
  final List<AudioPlayer> _timerTickPlayers = [];
  int _timerTickPoolIndex = 0;

  SharedPreferences? _prefs;
  Set<String> _availableAssets = const <String>{};

  bool _initialized = false;
  bool _soundEffectsEnabled = true;
  double _volume = 0.5;
  /// 0–1; scales turn timer tick on top of [_volume].
  double _timerTickVolumeMul = 0.65;

  bool get soundEffectsEnabled => _soundEffectsEnabled;
  double get volume => _volume;

  double get timerTickVolumeMultiplier => _timerTickVolumeMul;

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
      _timerTickVolumeMul =
          ((_prefs?.getDouble(_prefsKeyTimerTickVolume) ?? 65.0) / 100.0)
              .clamp(0.0, 1.0);
      _availableAssets = await _loadAudioAssets();
    } catch (_) {
      // Fail silently: missing prefs or asset manifest should not crash gameplay.
    }

    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          // Mix with background apps (e.g. YouTube): no audio focus steal, and
          // usage sonification — not USAGE_GAME / media — so SFX reads as UI
          // sounds rather than competing primary playback.
          android: AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            isSpeakerphoneOn: false,
            audioMode: AndroidAudioMode.normal,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService: setAudioContext failed: $e');
      }
    }

    try {
      _turnPlayer = AudioPlayer();
      _specialPlayer = AudioPlayer();
      _uiPlayer = AudioPlayer();
      for (var i = 0; i < _cardDrawPoolSize; i++) {
        _cardDrawPlayers.add(AudioPlayer());
      }
      for (var i = 0; i < _timerTickPoolSize; i++) {
        _timerTickPlayers.add(AudioPlayer());
      }
    } catch (_) {
      // Fail silently: player creation should not crash gameplay.
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
    final tickVol = (_volume * _timerTickVolumeMul).clamp(0.0, 1.0);
    for (final p in _timerTickPlayers) {
      p.setVolume(tickVol);
    }
    for (final p in _cardDrawPlayers) {
      p.setVolume(_volume);
    }
  }

  /// [value] is 0–1 (e.g. settings slider / 100). Persisted as 0–100.
  Future<void> setTimerTickVolume(double value) async {
    _timerTickVolumeMul = value.clamp(0.0, 1.0);
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setDouble(_prefsKeyTimerTickVolume, _timerTickVolumeMul * 100);
    } catch (_) {}
    final tickVol = (_volume * _timerTickVolumeMul).clamp(0.0, 1.0);
    for (final p in _timerTickPlayers) {
      p.setVolume(tickVol);
    }
  }

  /// Stops all persistent players (e.g. between tournament rounds so prior
  /// table audio cannot bleed into the next round).
  Future<void> stopAll() async {
    final players = <AudioPlayer?>[
      _turnPlayer,
      _specialPlayer,
      _uiPlayer,
      ..._timerTickPlayers,
      ..._cardDrawPlayers,
    ];
    for (final player in players) {
      try {
        await player?.stop();
      } catch (_) {}
    }
  }

  Future<void> playSound(GameSound sound) async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    // Skip manifest check: attempt play for all sounds. Some platforms/manifests
    // format asset paths differently; false negatives would silence valid files.
    // Missing files will fail in _play* and are caught there.
    if (!_hasAssetFor(sound)) {
      // Log only in debug to avoid noise; still attempt play for path variations.
      if (kDebugMode) {
        debugPrint('AudioService: asset not in manifest for $sound, trying anyway');
      }
    }

    final assetSubpath = _assetSubpathFor(sound);

    switch (sound) {
      // ── Turn-start: isolated so rapid skip-chains don't stack ──────────────
      case GameSound.turnStart:
        await _playCategorySound(_turnPlayer, assetSubpath);

      case GameSound.timerTick:
        if (_timerTickVolumeMul <= 0) return;
        await _playTimerTickSound(
          assetSubpath,
          (_volume * _timerTickVolumeMul).clamp(0.0, 1.0),
        );

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
      case GameSound.cardSelect:
      case GameSound.endTurnButton:
      case GameSound.cardPlace:
      case GameSound.playerWin:
      case GameSound.playerLose:
      case GameSound.opponentOut:
        await _playCategorySound(_uiPlayer, assetSubpath);

      // ── Card draw: when player draws from deck (overlapping pool) ───────────
      case GameSound.cardDraw:
        await _playOverlappingSound(assetSubpath);

      // ── Deal card: dealer dealing at round start (overlapping pool) ──────────
      case GameSound.dealCard:
        await _playOverlappingSound(assetSubpath);
    }
  }

  /// Plays the deal sound for a specific player during the deal animation.
  /// [playerIndex] is 0-based: 0 = first opponent, 1 = second, ..., last = local.
  /// Uses deal_card_1.wav through deal_card_10.wav (wraps for 10+ players).
  Future<void> playDealCardSoundForPlayer(int playerIndex) async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    final slot = (playerIndex % 10) + 1;
    await _playOverlappingSound('audio/sfx/deal_card_$slot.wav');
  }

  Future<void> _playTimerTickSound(String assetSubpath, double volume) async {
    if (_timerTickPlayers.isEmpty) return;
    final player =
        _timerTickPlayers[_timerTickPoolIndex % _timerTickPlayers.length];
    _timerTickPoolIndex++;
    try {
      await player.setVolume(volume);
      // No stop(): let the clip finish; pool avoids clobbering a tick that
      // overlaps rare double-fires, and keeps ticks independent of category SFX.
      await player.play(AssetSource(assetSubpath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playTimerTickSound($assetSubpath) error: $e');
      }
    }
  }

  /// Plays a sound on a rotating pool, allowing overlapping playback.
  /// Used for cardDraw and dealCard; rapid plays would otherwise stop each other.
  Future<void> _playOverlappingSound(String assetSubpath) async {
    if (_cardDrawPlayers.isEmpty) return;
    final player = _cardDrawPlayers[_cardDrawPoolIndex % _cardDrawPlayers.length];
    _cardDrawPoolIndex++;
    try {
      await player.setVolume(_volume);
      await player.play(AssetSource(assetSubpath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playOverlappingSound($assetSubpath) error: $e');
      }
    }
  }

  /// Plays a sound on a shared, persistent [AudioPlayer].
  ///
  /// Calls [AudioPlayer.stop] first to cleanly cancel any in-progress playback
  /// on that player before starting the new sound.  Within a category only
  /// the latest sound matters, so earlier ones are cut.  Categories are kept
  /// separate so that, e.g., a tournamentQualify sound is never cut by turnStart.
  Future<void> _playCategorySound(
    AudioPlayer? player,
    String assetSubpath, {
    double? volume,
  }) async {
    if (player == null) return;
    try {
      await player.stop();
      await player.setVolume(volume ?? _volume);
      await player.play(AssetSource(assetSubpath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playCategorySound($assetSubpath) error: $e');
      }
    }
  }

  /// Releases all native audio resources.  Call when the owning widget tree is
  /// torn down (e.g. in [State.dispose]).
  Future<void> dispose() async {
    try {
      await _turnPlayer?.dispose();
      await _specialPlayer?.dispose();
      await _uiPlayer?.dispose();
      for (final p in _timerTickPlayers) {
        await p.dispose();
      }
      _timerTickPlayers.clear();
      for (final p in _cardDrawPlayers) {
        await p.dispose();
      }
      _cardDrawPlayers.clear();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService.dispose error: $e');
      }
    }
    _turnPlayer = null;
    _specialPlayer = null;
    _uiPlayer = null;
    _initialized = false;
  }

  Future<Set<String>> _loadAudioAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((path) =>
              path.startsWith('assets/audio/') ||
              path.contains('/assets/audio/'))
          .toSet();
    } catch (_) {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = jsonDecode(manifestJson);
      return manifest.keys
          .where((path) =>
              path.startsWith('assets/audio/') ||
              path.contains('/assets/audio/'))
          .map((k) => k.toString())
          .toSet();
    }
  }

  bool _hasAssetFor(GameSound sound) {
    final filename = _soundFiles[sound];
    if (filename == null) return false;
    final exactPath = 'assets/audio/sfx/$filename';
    if (_availableAssets.contains(exactPath)) return true;
    final name = filename; // Capture for closure
    return _availableAssets.any((p) =>
        p.contains('audio/sfx/$name') ||
        p.toLowerCase().endsWith(name.toLowerCase()));
  }

  String _assetSubpathFor(GameSound sound) => 'audio/sfx/${_soundFiles[sound]}';
}
