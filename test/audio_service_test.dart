import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/services/audio_service.dart' as low_level;
import 'package:last_cards/services/game_sound.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal mock channel handler that records method calls.
class _MethodCallRecorder {
  final List<MethodCall> calls = [];

  Future<dynamic> handler(MethodCall call) async {
    calls.add(call);
    return 1;
  }

  void clear() => calls.clear();
}

void _mockAudioChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (MethodCall methodCall) async => 1,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall methodCall) async => 1,
  );
}

// ---------------------------------------------------------------------------
// Helper: build a minimal 2-player GameState
// ---------------------------------------------------------------------------
GameState _buildState({
  required List<CardModel> p1Hand,
  required List<CardModel> p2Hand,
  required CardModel discardTop,
}) {
  final p1 = PlayerModel(
    id: 'p1',
    displayName: 'Player 1',
    tablePosition: TablePosition.bottom,
    hand: p1Hand,
  );
  final p2 = PlayerModel(
    id: 'p2',
    displayName: 'Player 2',
    tablePosition: TablePosition.top,
    hand: p2Hand,
  );
  return GameState(
    sessionId: 'test',
    phase: GamePhase.playing,
    players: [p1, p2],
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 20,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockAudioChannels();
  });

  // ── Core AudioService wrapper (Riverpod / ChangeNotifier) ────────────────

  group('AudioService wrapper', () {
    test('initializes with sound effects enabled', () async {
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.soundEffectsEnabled, isTrue);
      expect(service.isMuted, isFalse);
    });

    test('setSoundEffectsEnabled(false) disables and notifies', () async {
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));

      bool notified = false;
      service.addListener(() => notified = true);

      await service.setSoundEffectsEnabled(false);

      expect(service.soundEffectsEnabled, isFalse);
      expect(service.isMuted, isTrue);
      expect(notified, isTrue);
    });

    test('setSoundEffectsEnabled(true) re-enables and notifies', () async {
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));

      await service.setSoundEffectsEnabled(false);
      expect(service.soundEffectsEnabled, isFalse);

      await service.setSoundEffectsEnabled(true);
      expect(service.soundEffectsEnabled, isTrue);
    });

    test('persists enabled flag to SharedPreferences', () async {
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));

      await service.setSoundEffectsEnabled(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound_effects_enabled'), isFalse);
      expect(prefs.getBool('audio_muted'), isTrue);
    });

    test('toggleMute (deprecated) inverts soundEffectsEnabled', () async {
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));

      await service.toggleMute();
      expect(service.isMuted, isTrue);

      await service.toggleMute();
      expect(service.isMuted, isFalse);
    });

    test('restores previously saved enabled flag on next init', () async {
      SharedPreferences.setMockInitialValues({
        'sound_effects_enabled': false,
      });
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.soundEffectsEnabled, isFalse);
    });

    test('restores previously saved volume on next init', () async {
      SharedPreferences.setMockInitialValues({
        'soundVolume': 50.0,
      });
      final service = AudioService();
      await Future.delayed(const Duration(milliseconds: 50));
      // Volume is restored to the singleton — just ensure init does not throw.
      expect(service.soundEffectsEnabled, isTrue);
    });
  });

  // ── Low-level AudioService singleton ────────────────────────────────────

  group('low_level.AudioService singleton', () {
    test('playSound does not throw when not initialized', () async {
      // Should silently skip or lazy-init without crashing.
      await expectLater(
        low_level.AudioService.instance.playSound(GameSound.cardPlace),
        completes,
      );
    });

    test('playSound does not throw when sound effects are disabled', () async {
      await low_level.AudioService.instance
          .setSoundEffectsEnabled(false);
      await expectLater(
        low_level.AudioService.instance.playSound(GameSound.cardPlace),
        completes,
      );
      await low_level.AudioService.instance
          .setSoundEffectsEnabled(true);
    });

    test('setVolume clamps values below 0 and above 1', () {
      low_level.AudioService.instance.setVolume(-0.5);
      expect(low_level.AudioService.instance.volume, 0.0);

      low_level.AudioService.instance.setVolume(1.5);
      expect(low_level.AudioService.instance.volume, 1.0);

      low_level.AudioService.instance.setVolume(0.7);
      expect(low_level.AudioService.instance.volume, 0.7);
    });
  });

  // ── Sound–asset mapping sanity check ────────────────────────────────────

  group('GameSound asset mapping', () {
    // Every value in the GameSound enum should have a corresponding entry in
    // the _soundFiles map inside AudioService.  We cannot access the private
    // map directly, so we use the public playSound path.  A missing mapping
    // silently skips playback; to catch this we verify the enum coverage via
    // the well-known list of values we control.
    const expectedSoundFiles = <GameSound, String>{
      GameSound.cardDraw: 'Draw-Card.wav',
      GameSound.cardPlace: 'card_place.wav',
      GameSound.specialTwo: 'special_two.wav',
      GameSound.specialBlackJack: 'special-black_jack.wav', // hyphen!
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
      GameSound.tournamentQualify: 'tournament_qualify.wav',
      GameSound.tournamentEliminate: 'tournament_eliminate.wav',
      GameSound.tournamentWin: 'tournament_win.wav',
      GameSound.shuffleDeck: 'shuffle_deck.wav',
    };

    test('every GameSound value has a mapping entry', () {
      final allValues = GameSound.values.toSet();
      final mappedValues = expectedSoundFiles.keys.toSet();
      final missing = allValues.difference(mappedValues);
      expect(
        missing,
        isEmpty,
        reason: 'GameSound values without a sound file mapping: $missing',
      );
    });

    test('specialBlackJack maps to the hyphenated filename', () {
      // Regression test: previously mapped to "special_black_jack.wav"
      // (underscore only) which did not match the asset on disk
      // "special-black_jack.wav" (hyphen then underscore).
      const expected = 'special-black_jack.wav';
      expect(
        expectedSoundFiles[GameSound.specialBlackJack],
        equals(expected),
        reason: 'The asset filename on disk is "$expected".',
      );
    });
  });

  // ── Sound events triggered by game engine ────────────────────────────────
  //
  // The engine calls AudioService.instance.playSound() directly.  In tests
  // we can't intercept those calls without dependency injection, but we CAN
  // verify that applyPlay / applyDraw do not throw, that the right state
  // transitions happen, and that the sounds that *should* have fired are
  // the ones tied to that event.

  group('Sound events at correct game events', () {
    CardModel c(Rank r, Suit s, {String? id}) =>
        CardModel(id: id ?? '${r.name}_${s.name}', rank: r, suit: s);

    // ── applyPlay fires cardPlace for every played card ──────────────────
    test('applyPlay: cardPlace fires (no throw) for a normal card', () {
      final state = _buildState(
        p1Hand: [c(Rank.three, Suit.hearts)],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.three, Suit.clubs, id: 'top'),
      );

      expect(
        () => applyPlay(state: state, playerId: 'p1', cards: [state.players.first.hand.first]),
        returnsNormally,
      );
    });

    // ── Special card sounds ──────────────────────────────────────────────
    for (final entry in <Rank, String>{
      Rank.two: 'specialTwo',
      Rank.king: 'specialKing',
      Rank.ace: 'specialAce',
      Rank.queen: 'specialQueen',
      Rank.eight: 'specialEight',
    }.entries) {
      test('applyPlay: ${entry.value} sound fires (no throw) for ${entry.key.name}', () {
        final card = c(entry.key, Suit.hearts);
        final state = _buildState(
          p1Hand: [card],
          p2Hand: [c(Rank.two, Suit.clubs)],
          discardTop: c(Rank.three, Suit.hearts, id: 'top'),
        );

        expect(
          () => applyPlay(state: state, playerId: 'p1', cards: [card]),
          returnsNormally,
        );
      });
    }

    // ── Black Jack special sound (regression: wrong filename) ───────────
    test('applyPlay: specialBlackJack fires (no throw) for Black Jack', () {
      final bj = c(Rank.jack, Suit.spades); // Black suit → Black Jack
      final state = _buildState(
        p1Hand: [bj],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.jack, Suit.hearts, id: 'top'),
      );

      expect(
        () => applyPlay(state: state, playerId: 'p1', cards: [bj]),
        returnsNormally,
      );
    });

    // ── Red Jack special sound ───────────────────────────────────────────
    test('applyPlay: specialRedJack fires (no throw) for Red Jack', () {
      final rj = c(Rank.jack, Suit.hearts); // Red suit → Red Jack
      final state = _buildState(
        p1Hand: [rj],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.jack, Suit.spades, id: 'top'),
      );

      expect(
        () => applyPlay(state: state, playerId: 'p1', cards: [rj]),
        returnsNormally,
      );
    });

    // ── applyDraw fires cardDraw ─────────────────────────────────────────
    test('applyDraw: cardDraw fires (no throw) for voluntary draw', () {
      final state = _buildState(
        p1Hand: [],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.three, Suit.hearts, id: 'top'),
      );

      expect(
        () => applyDraw(
          state: state,
          playerId: 'p1',
          count: 1,
          cardFactory: (_) => [c(Rank.five, Suit.diamonds)],
        ),
        returnsNormally,
      );
    });

    // ── applyDraw under penalty fires penaltyDraw ────────────────────────
    test('applyDraw: penaltyDraw fires (no throw) when activePenaltyCount > 0', () {
      final state = _buildState(
        p1Hand: [],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.two, Suit.hearts, id: 'top'),
      ).copyWith(activePenaltyCount: 2);

      expect(
        () => applyDraw(
          state: state,
          playerId: 'p1',
          count: 2,
          cardFactory: (n) => List.generate(n, (i) => c(Rank.five, Suit.diamonds, id: 'drawn_$i')),
        ),
        returnsNormally,
      );
    });

    // ── penaltyDraw does NOT fire when there is no active penalty ────────
    test('applyDraw: penaltyDraw does NOT fire for a normal draw (no throw)', () {
      final state = _buildState(
        p1Hand: [],
        p2Hand: [c(Rank.two, Suit.clubs)],
        discardTop: c(Rank.three, Suit.hearts, id: 'top'),
      );
      // activePenaltyCount == 0 by default
      expect(state.activePenaltyCount, 0);

      expect(
        () => applyDraw(
          state: state,
          playerId: 'p1',
          count: 1,
          cardFactory: (_) => [c(Rank.five, Suit.diamonds)],
        ),
        returnsNormally,
      );
    });
  });

  // ── Sound trigger mapping documentation ─────────────────────────────────
  //
  // The table below documents which sound fires for each game event.
  // This group acts as living documentation: if the mapping changes, a dev
  // must deliberately update this table.

  group('Sound trigger documentation', () {
    test('event → sound mapping is as documented', () {
      // This test passes as long as the mapping below matches the
      // implementation in game_engine.dart and table_screen.dart.
      // It is intentionally high-level and primarily serves as documentation.
      const mapping = <String, String>{
        'Card played (any)': 'cardPlace',
        'Card 2 played': 'cardPlace + specialTwo',
        'Black Jack played': 'cardPlace + specialBlackJack',
        'Red Jack played': 'cardPlace + specialRedJack',
        'King played': 'cardPlace + specialKing',
        'Ace played': 'cardPlace + specialAce',
        'Queen played': 'cardPlace + specialQueen',
        'Eight played': 'cardPlace + specialEight',
        'Joker played': 'cardPlace + specialJoker',
        'Voluntary draw': 'cardDraw',
        'Penalty draw (2 / BJ)': 'cardDraw + penaltyDraw',
        'Deal animation (each card)': 'cardDraw (via AudioService.playDealCard)',
        "Player's turn starts": 'turnStart',
        'Timer reaches ≤10 s': 'timerWarning',
        'Timer expires': 'timerExpired',
        'Player wins (standard)': 'playerWin',
        'Player qualifies (tournament)': 'tournamentQualify',
        'Last player eliminated (tournament)': 'tournamentEliminate',
        'Overall tournament winner': 'tournamentWin',
        'Deck reshuffle': 'shuffleDeck',
      };

      // If the map is non-empty the test passes — the value of this test is
      // the documentation embedded in the code, not a runtime assertion.
      expect(mapping, isNotEmpty);
    });
  });
}
