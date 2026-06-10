import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_event.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/providers/connection_provider.dart';
import 'package:last_cards/core/providers/game_provider.dart';

import '../../helpers/mock_audio_platform.dart';
import '../helpers/network_mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGameEventHandler mockHandler;
  late StreamController<StateSnapshotEvent> stateSnapshots;
  late StreamController<CardPlayedEvent> cardPlays;
  late StreamController<CardDrawnEvent> cardDraws;
  late StreamController<TurnChangedEvent> turnChanges;
  late StreamController<PenaltyAppliedEvent> penalties;
  late ProviderContainer container;

  GameState makeGameState({
    String currentPlayerId = 'p1',
    int drawPileCount = 20,
    int activePenaltyCount = 0,
  }) {
    final p1 = PlayerModel(
      id: 'p1',
      displayName: 'P1',
      tablePosition: TablePosition.bottom,
      hand: const [],
    );
    final p2 = PlayerModel(
      id: 'p2',
      displayName: 'P2',
      tablePosition: TablePosition.top,
      hand: const [],
    );
    return GameState(
      sessionId: 'test',
      phase: GamePhase.playing,
      players: [p1, p2],
      currentPlayerId: currentPlayerId,
      direction: PlayDirection.clockwise,
      discardTopCard: CardModel(id: 'c0', rank: Rank.five, suit: Suit.hearts),
      drawPileCount: drawPileCount,
      activePenaltyCount: activePenaltyCount,
    );
  }

  void stubHandlerStreams() {
    when(mockHandler.stateSnapshots)
        .thenAnswer((_) => stateSnapshots.stream);
    when(mockHandler.cardPlays).thenAnswer((_) => cardPlays.stream);
    when(mockHandler.cardDraws).thenAnswer((_) => cardDraws.stream);
    when(mockHandler.turnChanges).thenAnswer((_) => turnChanges.stream);
    when(mockHandler.penalties).thenAnswer((_) => penalties.stream);
    when(mockHandler.invalidPlayPenalties)
        .thenAnswer((_) => const Stream.empty());
    when(mockHandler.events).thenAnswer((_) => const Stream.empty());
    when(mockHandler.suitChoiceRequired)
        .thenAnswer((_) => const Stream.empty());
    when(mockHandler.jokerChoiceRequired)
        .thenAnswer((_) => const Stream.empty());
    when(mockHandler.turnTimeouts).thenAnswer((_) => const Stream.empty());
    when(mockHandler.reshuffles).thenAnswer((_) => const Stream.empty());
    when(mockHandler.sessionConfigs).thenAnswer((_) => const Stream.empty());
    when(mockHandler.errors).thenAnswer((_) => const Stream.empty());
    when(mockHandler.sendPlayCards(argThat(isA<PlayCardsAction>())))
        .thenReturn(true);
    when(mockHandler.sendDrawCard()).thenReturn(true);
    when(mockHandler.sendDeclareJoker(argThat(isA<DeclareJokerAction>())))
        .thenReturn(true);
    when(mockHandler.sendEndTurn()).thenReturn(true);
  }

  setUp(() {
    mockAudioChannels();
    mockHandler = MockGameEventHandler();
    stateSnapshots = StreamController<StateSnapshotEvent>.broadcast();
    cardPlays = StreamController<CardPlayedEvent>.broadcast();
    cardDraws = StreamController<CardDrawnEvent>.broadcast();
    turnChanges = StreamController<TurnChangedEvent>.broadcast();
    penalties = StreamController<PenaltyAppliedEvent>.broadcast();
    stubHandlerStreams();

    container = ProviderContainer(
      overrides: [
        gameEventHandlerProvider.overrideWithValue(mockHandler),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    stateSnapshots.close();
    cardPlays.close();
    cardDraws.close();
    turnChanges.close();
    penalties.close();
  });

  Future<void> flushEvents() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('GameNotifier event handling', () {
    test('state_snapshot replaces full GameState', () async {
      final gs = makeGameState();
      container.read(gameNotifierProvider);
      stateSnapshots.add(StateSnapshotEvent(gs));
      await flushEvents();

      expect(container.read(gameStateProvider)?.sessionId, 'test');
      expect(container.read(gameStateProvider)?.drawPileCount, 20);
    });

    test('card_played updates discardTopCard and discardPileHistory', () async {
      final gs = makeGameState();
      container.read(gameNotifierProvider);
      stateSnapshots.add(StateSnapshotEvent(gs));
      await flushEvents();

      final newTop = CardModel(id: 'c1', rank: Rank.six, suit: Suit.spades);
      cardPlays.add(
        CardPlayedEvent(
          playerId: 'p1',
          cards: [newTop],
          newDiscardTop: newTop,
        ),
      );
      await flushEvents();

      final updated = container.read(gameStateProvider)!;
      expect(updated.discardTopCard, newTop);
      expect(updated.discardPileHistory, hasLength(1));
      expect(updated.discardPileHistory.first.id, 'c0');
    });

    test('card_drawn decrements drawPileCount and never goes below 0', () async {
      final gs = makeGameState(drawPileCount: 1);
      container.read(gameNotifierProvider);
      stateSnapshots.add(StateSnapshotEvent(gs));
      await flushEvents();

      cardDraws.add(const CardDrawnEvent(playerId: 'p1'));
      await flushEvents();
      expect(container.read(gameStateProvider)!.drawPileCount, 0);

      cardDraws.add(const CardDrawnEvent(playerId: 'p1'));
      await flushEvents();
      expect(container.read(gameStateProvider)!.drawPileCount, 0);
    });

    test('turn_changed updates currentPlayerId only', () async {
      final gs = makeGameState(drawPileCount: 15, activePenaltyCount: 2);
      container.read(gameNotifierProvider);
      stateSnapshots.add(StateSnapshotEvent(gs));
      await flushEvents();

      turnChanges.add(
        const TurnChangedEvent(
          newCurrentPlayerId: 'p2',
          direction: PlayDirection.counterClockwise,
        ),
      );
      await flushEvents();

      final updated = container.read(gameStateProvider)!;
      expect(updated.currentPlayerId, 'p2');
      expect(updated.drawPileCount, 15);
      expect(updated.activePenaltyCount, 2);
    });

    test('penalty updates activePenaltyCount only', () async {
      final gs = makeGameState(currentPlayerId: 'p1', activePenaltyCount: 0);
      container.read(gameNotifierProvider);
      stateSnapshots.add(StateSnapshotEvent(gs));
      await flushEvents();

      penalties.add(
        const PenaltyAppliedEvent(
          targetPlayerId: 'p1',
          cardsDrawn: 2,
          newPenaltyStack: 4,
        ),
      );
      await flushEvents();

      final updated = container.read(gameStateProvider)!;
      expect(updated.activePenaltyCount, 4);
      expect(updated.currentPlayerId, 'p1');
    });
  });

  group('GameNotifier actions', () {
    test('playCards() calls sendPlayCards with correct IDs', () {
      container.read(gameNotifierProvider.notifier).playCards(['c1', 'c2']);

      final captured =
          verify(mockHandler.sendPlayCards(captureAny)).captured.single
              as PlayCardsAction;
      expect(captured.cardIds, ['c1', 'c2']);
    });

    test('drawCard() calls sendDrawCard()', () {
      container.read(gameNotifierProvider.notifier).drawCard();

      verify(mockHandler.sendDrawCard()).called(1);
    });

    test('declareJoker() calls sendDeclareJoker with suit and rank args', () {
      container.read(gameNotifierProvider.notifier).declareJoker(
            jokerCardId: 'j1',
            suitName: 'hearts',
            rankName: 'ace',
          );

      final captured =
          verify(mockHandler.sendDeclareJoker(captureAny)).captured.single
              as DeclareJokerAction;
      expect(captured.jokerCardId, 'j1');
      expect(captured.declaredSuit, Suit.hearts);
      expect(captured.declaredRank, Rank.ace);
    });
  });
}
