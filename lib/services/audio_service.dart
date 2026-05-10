import 'dart:async';
import 'dart:convert';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_sound.dart';

class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  static final AudioContext _sfxAudioContext = AudioContext(
    // Android: USAGE_GAME + sonification mixes reliably with in-app BGM on many
    // OEMs (e.g. Samsung). USAGE_ASSISTANCE_SONIFICATION + AUDIOFOCUS_NONE can be
    // muted or routed away while STREAM_MUSIC / music session is active.
    android: AudioContextAndroid(
      audioFocus: AndroidAudioFocus.none,
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
    ),
  );

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

  /// Flame [FlameAudio.play] gives a fresh [AudioPlayer] per sound; keep one active per lane so
  /// [stop]/[stopAll] can cut overlapping category SFX reliably.
  AudioPlayer? _laneTurn;
  AudioPlayer? _laneSpecial;
  AudioPlayer? _laneUi;

  /// Pre-loaded pool for repeating tick (same clip); see [FlameAudio.createPool].
  AudioPool? _timerTickPool;
  /// One pool per relative path (e.g. draw + deal_card variants) — [FlameAudio.createPool].
  final Map<String, AudioPool> _overlapPoolsByPath = {};

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
      await AudioPlayer.global.setAudioContext(_sfxAudioContext);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService: setAudioContext failed: $e');
      }
    }

    await _warmTimerTickPool();

    _initialized = true;
  }

  Future<void> _warmTimerTickPool() async {
    try {
      _timerTickPool ??= await FlameAudio.createPool(
        _assetRelativePath(GameSound.timerTick),
        maxPlayers: 2,
        minPlayers: 2,
        audioContext: _sfxAudioContext,
      );
    } catch (_) {
      _timerTickPool = null;
    }
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
    void apply(AudioPlayer? p) => p?.setVolume(_volume);
    apply(_laneTurn);
    apply(_laneSpecial);
    apply(_laneUi);
  }

  /// [value] is 0–1 (e.g. settings slider / 100). Persisted as 0–100.
  Future<void> setTimerTickVolume(double value) async {
    _timerTickVolumeMul = value.clamp(0.0, 1.0);
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setDouble(_prefsKeyTimerTickVolume, _timerTickVolumeMul * 100);
    } catch (_) {}
    // Tick volume applies on each pool.start via [_playTimerTickSound].
  }

  /// Stops all persistent players (e.g. between tournament rounds so prior
  /// table audio cannot bleed into the next round).
  Future<void> stopAll() async {
    Future<void> stopLane(AudioPlayer? p) async {
      try {
        await p?.stop();
      } catch (_) {}
    }

    await stopLane(_laneTurn);
    await stopLane(_laneSpecial);
    await stopLane(_laneUi);

    await _disposeTimerTickPool();
    await _disposeOverlapPools();
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

    final relativePath = _assetRelativePath(sound);

    switch (sound) {
      // ── Turn-start: isolated so rapid skip-chains don't stack ──────────────
      case GameSound.turnStart:
        await _playCategoryLaneTurn(relativePath);

      case GameSound.timerTick:
        if (_timerTickVolumeMul <= 0) return;
        await _playTimerTickSound(
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
        await _playCategoryLaneSpecial(relativePath);

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
        await _playCategoryLaneUi(relativePath);

      // ── Card draw: when player draws from deck (overlapping pool) ───────────
      case GameSound.cardDraw:
        await _playOverlappingSound(relativePath);

      // ── Deal card: dealer dealing at round start (overlapping pool) ──────────
      case GameSound.dealCard:
        await _playOverlappingSound(relativePath);
    }
  }

  /// Plays the deal sound for a specific player during the deal animation.
  /// [playerIndex] is 0-based: 0 = first opponent, 1 = second, ..., last = local.
  /// Uses deal_card_1.wav through deal_card_10.wav (wraps for 10+ players).
  Future<void> playDealCardSoundForPlayer(int playerIndex) async {
    if (!_initialized) await init();
    if (!_soundEffectsEnabled) return;
    final slot = (playerIndex % 10) + 1;
    await _playOverlappingSound('sfx/deal_card_$slot.wav');
  }

  Future<void> _disposeTimerTickPool() async {
    try {
      await _timerTickPool?.dispose();
    } catch (_) {}
    _timerTickPool = null;
  }

  Future<void> _disposeOverlapPools() async {
    for (final p in _overlapPoolsByPath.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _overlapPoolsByPath.clear();
  }

  Future<void> _playTimerTickSound(double volume) async {
    try {
      _timerTickPool ??= await FlameAudio.createPool(
        _assetRelativePath(GameSound.timerTick),
        maxPlayers: 2,
        minPlayers: 2,
        audioContext: _sfxAudioContext,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playTimerTickSound pool error: $e');
      }
      return;
    }
    final pool = _timerTickPool;
    if (pool == null) return;
    try {
      unawaited(pool.start(volume: volume));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playTimerTickSound start error: $e');
      }
    }
  }

  Future<void> _playOverlappingSound(String relativePath) async {
    try {
      var pool = _overlapPoolsByPath[relativePath];
      pool ??= await FlameAudio.createPool(
        relativePath,
        maxPlayers: 3,
        minPlayers: 1,
        audioContext: _sfxAudioContext,
      );
      _overlapPoolsByPath[relativePath] = pool;
      unawaited(pool.start(volume: _volume));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playOverlappingSound($relativePath) error: $e');
      }
    }
  }

  Future<void> _releaseCategoryLane(AudioPlayer? Function() getRef) async {
    final p = getRef();
    try {
      await p?.stop();
      await p?.dispose();
    } catch (_) {}
  }

  Future<void> _playCategoryLaneTurn(String relativePath) async {
    await _releaseCategoryLane(() => _laneTurn);
    _laneTurn = null;
    if (!_soundEffectsEnabled) return;
    try {
      _laneTurn = await FlameAudio.play(
        relativePath,
        volume: _volume,
        audioContext: _sfxAudioContext,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playCategoryLaneTurn($relativePath) error: $e');
      }
    }
  }

  Future<void> _playCategoryLaneSpecial(String relativePath) async {
    await _releaseCategoryLane(() => _laneSpecial);
    _laneSpecial = null;
    if (!_soundEffectsEnabled) return;
    try {
      _laneSpecial = await FlameAudio.play(
        relativePath,
        volume: _volume,
        audioContext: _sfxAudioContext,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playCategoryLaneSpecial($relativePath) error: $e');
      }
    }
  }

  Future<void> _playCategoryLaneUi(String relativePath) async {
    await _releaseCategoryLane(() => _laneUi);
    _laneUi = null;
    if (!_soundEffectsEnabled) return;
    try {
      _laneUi = await FlameAudio.play(
        relativePath,
        volume: _volume,
        audioContext: _sfxAudioContext,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService._playCategoryLaneUi($relativePath) error: $e');
      }
    }
  }

  /// Releases all native audio resources.  Call when the owning widget tree is
  /// torn down (e.g. in [State.dispose]).
  Future<void> dispose() async {
    try {
      await _releaseCategoryLane(() => _laneTurn);
      await _releaseCategoryLane(() => _laneSpecial);
      await _releaseCategoryLane(() => _laneUi);
      _laneTurn = null;
      _laneSpecial = null;
      _laneUi = null;
      await _disposeTimerTickPool();
      await _disposeOverlapPools();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService.dispose error: $e');
      }
    }
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

  /// Path under [FlameAudio.audioCache] prefix (`assets/audio/`), e.g. `sfx/card_place.wav`.
  String _assetRelativePath(GameSound sound) => 'sfx/${_soundFiles[sound]}';
}