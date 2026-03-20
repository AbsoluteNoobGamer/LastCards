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

  SharedPreferences? _prefs;
  Set<String> _availableAssets = const <String>{};

  bool _initialized = false;
  bool _soundEffectsEnabled = true;
  double _volume = 0.5;

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
    } catch (_) {
      // Fail silently: missing prefs or asset manifest should not crash gameplay.
    }

    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
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
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('AudioService: setAudioContext failed: $e');
    }

    try {
      _turnPlayer = AudioPlayer();
      _specialPlayer = AudioPlayer();
      _uiPlayer = AudioPlayer();
      for (var i = 0; i < _cardDrawPoolSize; i++) {
        _cardDrawPlayers.add(AudioPlayer());
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
    for (final p in _cardDrawPlayers) {
      p.setVolume(_volume);
    }
  }

  /// Stops all persistent players (e.g. between tournament rounds so prior
  /// table audio cannot bleed into the next round).
  Future<void> stopAll() async {
    final players = <AudioPlayer?>[
      _turnPlayer,
      _specialPlayer,
      _uiPlayer,
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
      debugPrint('AudioService: asset not in manifest for $sound, trying anyway');
    }

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
      debugPrint('AudioService._playOverlappingSound($assetSubpath) error: $e');
    }
  }

  /// Plays a sound on a shared, persistent [AudioPlayer].
  ///
  /// Calls [AudioPlayer.stop] first to cleanly cancel any in-progress playback
  /// on that player before starting the new sound.  Within a category only
  /// the latest sound matters, so earlier ones are cut.  Categories are kept
  /// separate so that, e.g., a tournamentQualify sound is never cut by turnStart.
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
      for (final p in _cardDrawPlayers) {
        await p.dispose();
      }
      _cardDrawPlayers.clear();
    } catch (e) {
      debugPrint('AudioService.dispose error: $e');
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
