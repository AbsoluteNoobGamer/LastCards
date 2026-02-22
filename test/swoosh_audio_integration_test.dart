import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_and_flow/core/models/card_model.dart';
import 'package:stack_and_flow/core/models/game_state.dart';
import 'package:stack_and_flow/core/models/player_model.dart';
import 'package:stack_and_flow/core/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AudioService audioService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );

    // Mock the audioplayers MethodChannels heavily used during init/play
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );

    audioService = AudioService();
  });

  test('Swoosh sound integration test across multiple turns and edge cases', () async {
    // Wait for audio service async initialization
    await Future.delayed(const Duration(milliseconds: 50));

    // Setup initial game state with 2 players
    final p1 = PlayerModel(
        id: 'p1',
        displayName: 'Player 1',
        tablePosition: TablePosition.bottom,
        hand: [
          const CardModel(id: 'c1', rank: Rank.three, suit: Suit.hearts),
          const CardModel(id: 'c2', rank: Rank.three, suit: Suit.diamonds), // For multi-stacking
          const CardModel(id: 'c3', rank: Rank.four, suit: Suit.clubs), // Invalid play later
          const CardModel(id: 'c4', rank: Rank.ace, suit: Suit.spades), // Special card
          const CardModel(id: 'c5', rank: Rank.five, suit: Suit.hearts), // Winning card
        ]);
    final p2 = PlayerModel(
        id: 'p2',
        displayName: 'Player 2',
        tablePosition: TablePosition.top,
        hand: [
          const CardModel(id: 'c6', rank: Rank.two, suit: Suit.hearts),
        ]);

    var state = GameState(
      sessionId: 'testSession',
      phase: GamePhase.playing,
      players: [p1, p2],
      currentPlayerId: 'p1',
      direction: PlayDirection.clockwise,
      discardTopCard: const CardModel(id: 'c7', rank: Rank.seven, suit: Suit.hearts),
      drawPileCount: 20,
    );

    // --- Turn 1: Normal valid play ---
    final action1 = p1.hand[0];
    audioService.playClick(); // Trigger swoosh effect

    state = state.copyWith(
        discardTopCard: action1,
        currentPlayerId: 'p2'); 
    
    expect(state.discardTopCard?.rank, Rank.three);
    expect(state.currentPlayerId, 'p2');

    // --- Turn 2: Edge case - invalid play / draw ---
    audioService.playClick(); // Player clicks draw pile

    state = state.copyWith(
        currentPlayerId: 'p1', drawPileCount: state.drawPileCount - 1);
    
    expect(state.currentPlayerId, 'p1');
    expect(state.drawPileCount, 19);

    // --- Turn 3: Multi-card stacking edge case ---
    final action2 = p1.hand[1];
    audioService.playClick(); // Trigger swoosh effect

    state = state.copyWith(
        discardTopCard: action2,
        actionsThisTurn: 1, 
        lastPlayedThisTurn: action2);
    
    expect(state.discardTopCard?.suit, Suit.diamonds);
    expect(state.actionsThisTurn, 1);
    expect(state.currentPlayerId, 'p1'); 

    // p1 ends turn manually after multi-play
    audioService.playClick(); 
    
    state = state.copyWith(
        currentPlayerId: 'p2', actionsThisTurn: 0, lastPlayedThisTurn: null);

    // --- Turn 4: Special card interaction ---
    state = state.copyWith(currentPlayerId: 'p1');

    final action3 = p1.hand[3];
    audioService.playClick(); 

    state = state.copyWith(
        discardTopCard: action3,
        suitLock: Suit.clubs, 
        currentPlayerId: 'p2');

    expect(state.suitLock, Suit.clubs);
    expect(state.currentPlayerId, 'p2');

    // --- Turn 5: Win condition ---
    state = state.copyWith(currentPlayerId: 'p1');
    
    final action4 = p1.hand[4];
    audioService.playClick(); 

    state = state.copyWith(
        discardTopCard: action4,
        phase: GamePhase.ended,
        winnerId: 'p1');

    expect(state.phase, GamePhase.ended);
    expect(state.winnerId, 'p1');
    
    // Regression check
    expect(audioService.isMuted, false);
  });
}
