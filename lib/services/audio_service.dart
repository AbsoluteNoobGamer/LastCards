import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
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
    GameSound.specialCard: 'special_card.wav',
    GameSound.penaltyDraw: 'penalty_draw.wav',
    GameSound.turnStart: 'turn_start.wav',
    GameSound.timerWarning: 'timer_warning.wav',
    GameSound.timerExpired: 'timer_expired.wav',
    GameSound.playerWin: 'player_win.wav',
    GameSound.tournamentQualify: 'tournament_qualify.wav',
    GameSound.tournamentEliminate: 'tournament_eliminate.wav',
    GameSound.tournamentWin: 'tournament_win.wav',
    GameSound.shuffleDeck: 'shuffle_deck.wav',
  };

  AudioPlayer? _oneShotPlayer;
  AudioPool? _cardDrawPool;
  AudioPool? _cardPlacePool;
  SharedPreferences? _prefs;
  Set<String> _availableAssets = const <String>{};

  bool _initialized = false;
  bool _soundEffectsEnabled = true;
  double _volume = 1.0;

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
      _oneShotPlayer = AudioPlayer();

      if (_hasAssetFor(GameSound.cardDraw)) {
        _cardDrawPool = await AudioPool.create(
          source: AssetSource(_assetSubpathFor(GameSound.cardDraw)),
          maxPlayers: 4,
        );
      }
      if (_hasAssetFor(GameSound.cardPlace)) {
        _cardPlacePool = await AudioPool.create(
          source: AssetSource(_assetSubpathFor(GameSound.cardPlace)),
          maxPlayers: 4,
        );
      }
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
  }

  Future<void> playSound(GameSound sound) async {
    if (!_initialized) {
      await init();
    }
    if (!_soundEffectsEnabled) return;
    if (!_hasAssetFor(sound)) return;

    try {
      switch (sound) {
        case GameSound.cardDraw:
          await _cardDrawPool?.start(volume: _volume);
          return;
        case GameSound.cardPlace:
          await _cardPlacePool?.start(volume: _volume);
          return;
        case GameSound.specialCard:
        case GameSound.penaltyDraw:
        case GameSound.turnStart:
        case GameSound.timerWarning:
        case GameSound.timerExpired:
        case GameSound.playerWin:
        case GameSound.tournamentQualify:
        case GameSound.tournamentEliminate:
        case GameSound.tournamentWin:
        case GameSound.shuffleDeck:
          final player = _oneShotPlayer;
          if (player == null) return;
          await player.setVolume(_volume);
          await player.play(AssetSource(_assetSubpathFor(sound)));
          return;
      }
    } catch (_) {
      // Missing/corrupt files or unsupported audio backend should not crash.
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
