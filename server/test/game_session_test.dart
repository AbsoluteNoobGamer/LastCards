import 'dart:convert';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/models/table_position_layout.dart';
import 'package:test/test.dart';

import 'package:last_cards_server/game_session.dart';
import 'package:last_cards_server/trophy_recorder.dart';

// ── Fake WebSocket ────────────────────────────────────────────────────────────

class _FakeWs {
  final _sink = _FakeSink();

  _FakeSink get sink => _sink;

  List<Map<String, dynamic>> get messages => _sink.messages;

  Map<String, dynamic>? lastOfType(String type) =>
      messages.where((m) => m['type'] == type).toList().lastOrNull;

  List<Map<String, dynamic>> ofType(String type) =>
      messages.where((m) => m['type'] == type).toList();

  void clear() => _sink.messages.clear();
}

class _FakeSink {
  final messages = <Map<String, dynamic>>[];

  void add(String json) =>
      messages.add(jsonDecode(json) as Map<String, dynamic>);
}

// ── Card builders ─────────────────────────────────────────────────────────────

CardModel _card(Rank rank, Suit suit) =>
    CardModel(id: '${rank.name}_${suit.name}', rank: rank, suit: suit);

CardModel _joker(String id, Suit suit) =>
    CardModel(id: id, rank: Rank.joker, suit: suit);

/// Mirrors GameSession._positionFor for building test states.
TablePosition _positionFor(int index) => tablePositionForSeatIndex(index);

// ── Session builders ──────────────────────────────────────────────────────────

/// Creates a [GameSession] with [n] players added (not yet started).
({GameSession session, List<_FakeWs> sockets, List<String> ids})
    _makeSession(int n, {bool isBustMode = false}) {
  final session = GameSession('TEST', isBustMode: isBustMode);
  final sockets = <_FakeWs>[];
  final ids = <String>[];

  for (int i = 0; i < n; i++) {
    final ws = _FakeWs();
    sockets.add(ws);
    ids.add(session.addPlayer(ws, 'Player ${i + 1}'));
  }

  return (session: session, sockets: sockets, ids: ids);
}

/// Creates a started 2-player game with a **known, deterministic** state.
///
/// Player-1 hand: [3♠, 5♠, 7♠, 9♠, J♠, Q♠, K♠]  (all spades)
/// Player-2 hand: [3♥, 5♥, 7♥, 9♥, J♥, Q♥, K♥]  (all hearts)
/// Discard top  : 2♠  (2 of spades — no penalty because it's the opener and
///                      we seed via seedStateForTesting which skips
///                      applyInitialFaceUpEffect)
/// Draw pile    : 20 × 4♣ cards (arbitrary filler)
/// Discard under: empty
///
/// Player-1 goes first. No active penalty, no locks.
({
  GameSession session,
  _FakeWs p1ws,
  _FakeWs p2ws,
  String p1Id,
  String p2Id,
}) _makeKnownGame() {
  final (:session, :sockets, :ids) = _makeSession(2);
  final p1ws = sockets[0];
  final p2ws = sockets[1];
  final p1Id = ids[0]; // 'player-1'
  final p2Id = ids[1]; // 'player-2'

  final p1Hand = [
    _card(Rank.three, Suit.spades),
    _card(Rank.five, Suit.spades),
    _card(Rank.seven, Suit.spades),
    _card(Rank.nine, Suit.spades),
    _card(Rank.jack, Suit.spades),
    _card(Rank.queen, Suit.spades),
    _card(Rank.king, Suit.spades),
  ];
  final p2Hand = [
    _card(Rank.three, Suit.hearts),
    _card(Rank.five, Suit.hearts),
    _card(Rank.seven, Suit.hearts),
    _card(Rank.nine, Suit.hearts),
    _card(Rank.jack, Suit.hearts),
    _card(Rank.queen, Suit.hearts),
    _card(Rank.king, Suit.hearts),
  ];

  final discardTop = _card(Rank.two, Suit.spades);
  final drawPile = List.generate(
      20, (i) => CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs));

  final state = GameState(
    sessionId: 'TEST',
    phase: GamePhase.playing,
    players: [
      PlayerModel(
        id: p1Id,
        displayName: 'Player 1',
        tablePosition: TablePosition.bottom,
        hand: p1Hand,
        cardCount: p1Hand.length,
      ),
      PlayerModel(
        id: p2Id,
        displayName: 'Player 2',
        tablePosition: TablePosition.top,
        hand: p2Hand,
        cardCount: p2Hand.length,
      ),
    ],
    currentPlayerId: p1Id,
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: drawPile.length,
    preTurnCentreSuit: Suit.spades,
  );

  session.seedStateForTesting(state: state, drawPile: drawPile);

  return (
    session: session,
    p1ws: p1ws,
    p2ws: p2ws,
    p1Id: p1Id,
    p2Id: p2Id,
  );
}

// ── Snapshot helpers ──────────────────────────────────────────────────────────

Map<String, dynamic> _latestSnapshot(_FakeWs ws) {
  final msg = ws.lastOfType('state_snapshot');
  expect(msg, isNotNull, reason: 'No state_snapshot found');
  return msg!['payload'] as Map<String, dynamic>;
}

List<dynamic> _hand(Map<String, dynamic> snapshot) {
  final players = snapshot['players'] as List;
  return (players.first as Map<String, dynamic>)['hand'] as List;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Game start (random deal) ───────────────────────────────────────────────

  group('game start (random deal)', () {
    test('all players receive a state_snapshot when game starts', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        expect(ws.ofType('state_snapshot'), isNotEmpty);
      }
    });

    test('each player sees themselves at tablePosition bottom', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final self = (snap['players'] as List).first as Map<String, dynamic>;
        expect(self['tablePosition'], equals('bottom'));
      }
    });

    test('each player receives own hand, opponents get empty hands', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final players = snap['players'] as List;
        final self = players.first as Map<String, dynamic>;
        final opponent = players[1] as Map<String, dynamic>;
        expect((self['hand'] as List).length, greaterThan(0));
        expect((opponent['hand'] as List).length, equals(0));
        expect(opponent['cardCount'], greaterThan(0));
      }
    });

    test('phase is playing after start', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      for (final id in ids) {
        session.markReady(id);
      }
      final snap = _latestSnapshot(sockets.first);
      expect(snap['phase'], equals('playing'));
    });

    test('4-player game deals 7 cards each', () {
      final (:session, :sockets, :ids) = _makeSession(4);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final self = (snap['players'] as List).first as Map<String, dynamic>;
        expect((self['hand'] as List).length, equals(7));
      }
    });

    test('7-player game deals 7 cards each', () {
      final (:session, :sockets, :ids) = _makeSession(7);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final self = (snap['players'] as List).first as Map<String, dynamic>;
        expect((self['hand'] as List).length, equals(7));
      }
    });

    test('8th player is rejected (max 7)', () {
      final (:session, :sockets, :ids) = _makeSession(7);
      final ws = _FakeWs();
      final id = session.addPlayer(ws, 'Player 8');
      expect(id, isEmpty);
      expect(ws.lastOfType('error')?['code'], equals('room_full'));
    });
  });

  // ── play_cards ─────────────────────────────────────────────────────────────

  group('play_cards', () {
    test('valid play broadcasts card_played and new state_snapshot', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      // Discard top is 2♠. Player-1 has 3♠ which matches suit (spades).
      // But 2♠ has no active penalty (we seeded with activePenaltyCount=0),
      // so a normal spades card is valid.
      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['three_spades'],
      });

      expect(p1ws.ofType('card_played'), isNotEmpty);
      expect(p1ws.ofType('state_snapshot'), isNotEmpty);
      final cp = p1ws.lastOfType('card_played');
      expect(cp!['activeSkipCountBefore'], isA<int>());
      expect(cp['activeSkipCountAfter'], isA<int>());
      expect(cp['skippedPlayers'], isA<List>());
      expect(cp['turnContinues'], isA<bool>());
      expect(cp['directionReversed'], isA<bool>());
    });

    test('not_your_turn error sent to wrong player', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      p2ws.clear();

      session.handleAction(p2Id, {
        'type': 'play_cards',
        'cardIds': ['three_hearts'],
      });

      final err = p2ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], equals('not_your_turn'));
    });

    test('invalid play sends error (card not in hand)', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      // 'three_hearts' is not in p1's hand (p1 has all spades).
      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['three_hearts'],
      });

      final err = p1ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], anyOf(equals('invalid_play'), equals('invalid_card')));
    });

    test('invalid play with card in hand draws 2-card penalty', () {
      // Seed a state where p1 has a card that cannot be played.
      // Discard: 4♥. P1 hand: [3♠] (doesn't match suit hearts or rank 4).
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.three, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts), _card(Rank.six, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.hearts);
      final drawPile = List.generate(
          10, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 2,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);

      final handBefore = _hand(_latestSnapshot(p1ws)).length;
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['three_spades'],
      });

      final err = p1ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], equals('invalid_play'));

      final penaltyAp = p1ws.lastOfType('penalty_applied');
      expect(penaltyAp, isNotNull);
      expect(penaltyAp!['targetPlayerId'], equals(p1Id));
      expect(penaltyAp['cardsDrawn'], equals(2));

      // 2-card penalty: hand grows by 2.
      final snapAfter = _latestSnapshot(p1ws);
      final handAfter = _hand(snapAfter).length;
      expect(handAfter, equals(handBefore + 2));
    });

    test('joker via play_cards is rejected', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];

      final joker = _joker('jk1', Suit.spades);
      final p1Hand = [joker, _card(Rank.five, Suit.spades)];
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: p1Hand.length,
          ),
          PlayerModel(
            id: ids[1],
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.six, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.seven, Suit.spades),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.spades,
      );
      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5, (i) => CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs)),
      );

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['jk1'],
      });

      final err = p1ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], equals('joker_must_declare'));
    });
  });

  // ── draw_card ──────────────────────────────────────────────────────────────

  group('draw_card', () {
    test('drawing player receives card details, others do not', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      p1ws.clear();
      p2ws.clear();

      session.handleAction(p1Id, {'type': 'draw_card'});

      final p1Draw = p1ws.lastOfType('card_drawn');
      expect(p1Draw, isNotNull);
      expect(p1Draw!['card'], isNotNull);

      final p2Draw = p2ws.lastOfType('card_drawn');
      expect(p2Draw, isNotNull);
      expect(p2Draw!.containsKey('card'), isFalse);
    });

    test('draw increments hand size by 1 when no penalty', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      // Known game has activePenaltyCount = 0.
      final handBefore = _hand(_latestSnapshot(p1ws)).length;

      session.handleAction(p1Id, {'type': 'draw_card'});

      final handAfter = _hand(_latestSnapshot(p1ws)).length;
      expect(handAfter, equals(handBefore + 1));
    });

    test('draw with active penalty draws penalty count cards', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.three, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.two, Suit.spades);
      final drawPile = List.generate(
          10, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
        activePenaltyCount: 4, // active penalty
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      final handBefore = _hand(_latestSnapshot(p1ws)).length;

      session.handleAction(p1Id, {'type': 'draw_card'});

      final handAfter = _hand(_latestSnapshot(p1ws)).length;
      expect(handAfter, equals(handBefore + 4));
    });

    test('not_your_turn error on draw by wrong player', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      p2ws.clear();

      session.handleAction(p2Id, {'type': 'draw_card'});

      expect(p2ws.lastOfType('error')?['code'], equals('not_your_turn'));
    });

    test(
        'draw_card on penalty stack ends game when opponent declared Last Cards '
        'and emptied on pick-up', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p2ws = sockets[1];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final drawPile = List.generate(
          10,
          (i) =>
              CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [],
            cardCount: 0,
            lastCardsHandWasClearableAtTurnStart: true,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.five, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p2Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
        activePenaltyCount: 2,
        lastCardsDeclaredBy: {p1Id},
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();
      p2ws.clear();

      session.handleAction(p2Id, {'type': 'draw_card'});

      final ended = p1ws.lastOfType('game_ended');
      expect(ended, isNotNull,
          reason: 'P1 should win after the penalty draw clears the chain');
      expect(ended!['winnerId'], equals(p1Id));
      expect(p2ws.lastOfType('game_ended'), isNotNull);
    });
  });

  // ── end_turn ───────────────────────────────────────────────────────────────

  group('end_turn', () {
    test('draw_card broadcasts turn_changed (draw auto-advances turn)', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();

      session.handleAction(p1Id, {'type': 'draw_card'});

      // A draw always ends the turn — turn_changed is broadcast immediately.
      expect(p1ws.lastOfType('turn_changed'), isNotNull);
      expect(p2ws.lastOfType('turn_changed'), isNotNull);
    });

    test('end_turn without action sends invalid_end_turn error', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      p1ws.clear();

      session.handleAction(p1Id, {'type': 'end_turn'});

      final err = p1ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], equals('invalid_end_turn'));
    });

    test('after draw_card, currentPlayerId changes to next player', () {
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();
      session.handleAction(p1Id, {'type': 'draw_card'});

      final snap = _latestSnapshot(p1ws);
      expect(snap['currentPlayerId'], equals(p2Id));
    });
  });

  // ── declare_joker ──────────────────────────────────────────────────────────

  group('declare_joker', () {
    test('declare_joker broadcasts card_played with declared suit/rank', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final joker = _joker('joker_r', Suit.hearts);
      final p1Hand = [joker];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.spades);
      final drawPile = List.generate(
          5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'declare_joker',
        'jokerCardId': 'joker_r',
        'declaredSuit': 'hearts',
        'declaredRank': 'four',
      });

      final played = p1ws.lastOfType('card_played');
      expect(played, isNotNull);
      final cards = played!['cards'] as List;
      expect(cards.length, equals(1));
      final card = cards.first as Map<String, dynamic>;
      expect(card['rank'], equals('joker'));
      expect(card['jokerDeclaredSuit'], equals('hearts'));
      expect(card['jokerDeclaredRank'], equals('four'));
    });

    test('invalid declare_joker sends error and does not play card', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final joker = _joker('joker_r', Suit.hearts);
      final p1Hand = [joker];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.spades);
      final drawPile = List.generate(
          5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'declare_joker',
        'jokerCardId': 'joker_r',
        'declaredSuit': 'hearts',
        'declaredRank': 'king',
      });

      final err = p1ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], equals('invalid_joker'));
      expect(p1ws.ofType('card_played'), isEmpty);
    });
  });

  // ── suit_choice ────────────────────────────────────────────────────────────

  group('suit_choice', () {
    test('playing Ace without declaredSuit sends suit_choice_required', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final ace = _card(Rank.ace, Suit.spades);
      final p1Hand = [ace, _card(Rank.five, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.spades);
      final drawPile = List.generate(
          5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 2,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['ace_spades'],
      });

      expect(p1ws.lastOfType('suit_choice_required'), isNotNull);
    });

    test('suit_choice response locks the declared suit in state', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final ace = _card(Rank.ace, Suit.spades);
      final p1Hand = [ace, _card(Rank.five, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.spades);
      final drawPile = List.generate(
          5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 2,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);

      // Play Ace without suit.
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['ace_spades'],
      });

      // Respond with suit choice.
      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'suit_choice',
        'suit': 'diamonds',
      });

      final snap = _latestSnapshot(p1ws);
      expect(snap['suitLock'], equals('diamonds'));
    });
  });

  // ── reshuffle ──────────────────────────────────────────────────────────────

  group('reshuffle', () {
    test('reshuffle event is broadcast when draw pile hits ≤ 5', () {
      // Seed a game with exactly 5 draw pile cards and a non-empty discard
      // under-top. The next draw should trigger a reshuffle.
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.three, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.spades);

      // 5 cards in draw pile — at the threshold.
      final drawPile = List.generate(
          5, (i) => CardModel(id: 'draw_$i', rank: Rank.seven, suit: Suit.clubs));

      // 10 cards in discard under-top — available for reshuffle.
      final discardUnder = List.generate(
          10, (i) => CardModel(id: 'disc_$i', rank: Rank.eight, suit: Suit.diamonds));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        discardUnderTop: discardUnder,
      );

      p1ws.clear();
      // Drawing a card with draw pile ≤ 5 and non-empty discard triggers reshuffle.
      session.handleAction(p1Id, {'type': 'draw_card'});

      expect(p1ws.lastOfType('reshuffle'), isNotNull,
          reason: 'Expected reshuffle event when draw pile ≤ 5');
      final reshuffleMsg = p1ws.lastOfType('reshuffle')!;
      expect(reshuffleMsg['newDrawPileCount'], greaterThan(0));
    });

    test('draw pile count increases after reshuffle', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1Id = ids[0];
      final p2Id = ids[1];

      final drawPile = List.generate(
          3, (i) => CardModel(id: 'draw_$i', rank: Rank.seven, suit: Suit.clubs));
      final discardUnder = List.generate(
          15, (i) => CardModel(id: 'disc_$i', rank: Rank.eight, suit: Suit.diamonds));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [_card(Rank.three, Suit.spades)],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.five, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.four, Suit.spades),
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        discardUnderTop: discardUnder,
      );

      session.handleAction(p1Id, {'type': 'draw_card'});

      // After reshuffle + draw, draw pile should have grown.
      expect(session.drawPileCountForTesting, greaterThan(3));
    });
  });

  // ── win detection ──────────────────────────────────────────────────────────

  group('win detection', () {
    test('game_ended is broadcast when a player empties their hand', () {
      // P1 has exactly 1 card that matches the discard. Playing it empties hand.
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final winCard = _card(Rank.five, Suit.spades);
      final discardTop = _card(Rank.five, Suit.hearts); // same rank → valid play

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [winCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.three, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final ended = p1ws.lastOfType('game_ended');
      expect(ended, isNotNull);
      expect(ended!['winnerId'], equals(p1Id));
    });

    test(
        'quickplay casual game calls recordLeaderboardOnlineCasual with Firebase uids',
        () {
      final fake = FakeTrophyRecorder();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isRanked: false,
        trophyRecorder: fake,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'firebase-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'firebase-p2');

      final winCard = _card(Rank.five, Suit.spades);
      final discardTop = _card(Rank.five, Suit.hearts);

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [winCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.three, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5,
            (i) =>
                CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      expect(fake.leaderboardOnlineCasualCalls, 1);
      expect(fake.lastCasualWinnerPlayerId, p1Id);
      expect(fake.lastCasualPlayers, isNotNull);
      expect(fake.lastCasualPlayers!.length, 2);
      expect(fake.lastCasualPlayers!.first.firebaseUid, 'firebase-p1');
    });

    test(
        'private lobby does not record leaderboard_online on win (not trophy eligible)',
        () {
      final fake = FakeTrophyRecorder();
      final session = GameSession(
        'TEST',
        isPrivate: true,
        isRanked: false,
        trophyRecorder: fake,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'firebase-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'firebase-p2');

      final winCard = _card(Rank.five, Suit.spades);
      final discardTop = _card(Rank.five, Suit.hearts);

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [winCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.three, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5,
            (i) =>
                CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      expect(fake.leaderboardOnlineCasualCalls, 0);
    });

    test('game_ended not sent while penalty chain is active', () {
      // P1 plays their last card (a 2) which starts a penalty chain.
      // Win should be deferred (activePenaltyCount > 0 after play).
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final lastCard = _card(Rank.two, Suit.spades);
      final discardTop = _card(Rank.two, Suit.hearts); // penalty chain

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [lastCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.three, Suit.hearts), _card(Rank.four, Suit.hearts)],
            cardCount: 2,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
        activePenaltyCount: 2, // existing penalty chain
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['two_spades'],
      });

      // Win should NOT be confirmed while penalty is active.
      expect(p1ws.lastOfType('game_ended'), isNull);
    });
  });

  // ── turn timer ─────────────────────────────────────────────────────────────

  group('turn timer', () {
    test('turn advances correctly after draw (draw auto-advances turn)', () {
      // The actual 60s timer is not testable synchronously.
      // We verify the state transitions that _onTurnTimeout performs:
      // draw 1 card → turn auto-advances.
      final (:session, :p1ws, :p2ws, :p1Id, :p2Id) = _makeKnownGame();

      session.handleAction(p1Id, {'type': 'draw_card'});

      final snap = _latestSnapshot(p1ws);
      expect(snap['currentPlayerId'], equals(p2Id));
    });

    test('turn timeout draws full active penalty chain', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.three, Suit.spades)];
      final discardTop = _card(Rank.two, Suit.hearts);
      final drawPile = List.generate(
          10,
          (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.five, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.hearts,
        activePenaltyCount: 4,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();

      session.triggerTurnTimeoutForTesting();

      final timeout = p1ws.lastOfType('turn_timeout');
      expect(timeout, isNotNull);
      expect(timeout!['cardsDrawn'], equals(4));
      expect(session.drawPileCountForTesting, equals(6));
    });
  });

  // ── position assignment ────────────────────────────────────────────────────

  group('position assignment', () {
    test('3-player game: each client sees themselves at bottom', () {
      final (:session, :sockets, :ids) = _makeSession(3);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final self = (snap['players'] as List).first as Map<String, dynamic>;
        expect(self['tablePosition'], equals('bottom'));
      }
    });

    test('3-player game: all 3 players appear in each snapshot', () {
      final (:session, :sockets, :ids) = _makeSession(3);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        expect((snap['players'] as List).length, equals(3));
      }
    });
  });

  // ── Bust mode ───────────────────────────────────────────────────────────────

  group('Bust mode', () {
    test('Bust game start: 5 players get 10 cards each, 52-card deck', () {
      final (:session, :sockets, :ids) = _makeSession(5, isBustMode: true);
      for (final id in ids) {
        session.markReady(id);
      }
      for (final ws in sockets) {
        final snap = _latestSnapshot(ws);
        final players = snap['players'] as List;
        expect(players.length, equals(5));
        for (final p in players) {
          final pm = p as Map<String, dynamic>;
          final handList = pm['hand'] as List?;
          final handLen = (handList?.isNotEmpty ?? false)
              ? handList!.length
              : (pm['cardCount'] as int? ?? 0);
          expect(handLen, equals(10), reason: 'Bust 5-player hand size = 10');
        }
      }
    });

    test('Bust round completes when all players have 2 turns, broadcasts bust_round_over', () {
      final (:session, :sockets, :ids) = _makeSession(5, isBustMode: true);
      final p1ws = sockets[0];
      final idsList = ids;

      // Card counts: p1=1, p2=2, p3=5, p4=8, p5=10 → p4,p5 eliminated
      final cardCounts = {idsList[0]: 1, idsList[1]: 2, idsList[2]: 5, idsList[3]: 8, idsList[4]: 10};
      final players = [
        for (var i = 0; i < 5; i++)
          PlayerModel(
            id: idsList[i],
            displayName: 'Player ${i + 1}',
            tablePosition: _positionFor(i),
            hand: List.generate(
                cardCounts[idsList[i]]!,
                (j) => _card(Rank.values[(j % 13) + 1], Suit.hearts)),
            cardCount: cardCounts[idsList[i]]!,
          ),
      ];
      final lastId = idsList[4];
      final drawPile = List.generate(
          20, (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: players,
        currentPlayerId: lastId,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: idsList,
        bustTurnsThisRound: {
          idsList[0]: 2,
          idsList[1]: 2,
          idsList[2]: 2,
          idsList[3]: 2,
          idsList[4]: 1,
        },
        bustPenaltyPoints: {},
      );

      p1ws.clear();
      session.handleAction(lastId, {'type': 'draw_card'});

      final roundOver = p1ws.lastOfType('bust_round_over');
      expect(roundOver, isNotNull);
      expect(roundOver!['roundNumber'], equals(1));
      expect(roundOver['eliminatedThisRound'], hasLength(2));
      expect(
        (roundOver['eliminatedThisRound'] as List).contains(idsList[3]),
        isTrue,
      );
      expect(
        (roundOver['eliminatedThisRound'] as List).contains(idsList[4]),
        isTrue,
      );
      expect(roundOver['survivorIds'], hasLength(3));
      expect(roundOver['isGameOver'], isFalse);
    });

    test('Bust 1v1: round does not finalize from turn count after 2 each', () {
      final (:session, :sockets, :ids) = _makeSession(2, isBustMode: true);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.four, Suit.clubs)];
      final p2Hand = List.generate(
          5, (i) => _card(Rank.values[i + 2], Suit.hearts));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 5,
          ),
        ],
        currentPlayerId: p2Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: 10,
        preTurnCentreSuit: Suit.spades,
      );

      final drawPile = List.generate(
          10, (i) => CardModel(id: 'draw_$i', rank: Rank.five, suit: Suit.clubs));

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: [p1Id, p2Id],
        bustTurnsThisRound: {p1Id: 2, p2Id: 2},
        bustPenaltyPoints: {},
      );

      p1ws.clear();
      session.handleAction(p2Id, {'type': 'draw_card'});

      expect(p1ws.ofType('bust_round_over'), isEmpty);
      expect(p1ws.lastOfType('turn_changed'), isNotNull);
    });

    test('Bust 1v1: empty hand ends game, bust_game_ended with winner', () {
      final (:session, :sockets, :ids) = _makeSession(2, isBustMode: true);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final winningCard = _card(Rank.three, Suit.spades);
      final p1Hand = [winningCard];
      final p2Hand = List.generate(
          5, (i) => _card(Rank.values[i + 2], Suit.hearts));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 5,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: 10,
        preTurnCentreSuit: Suit.spades,
      );

      final drawPile = List.generate(
          10, (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs));

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: [p1Id, p2Id],
        bustTurnsThisRound: {p1Id: 0, p2Id: 0},
        bustPenaltyPoints: {},
      );

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': [winningCard.id],
      });

      final roundOver = p1ws.lastOfType('bust_round_over');
      expect(roundOver, isNotNull);
      expect(roundOver!['isGameOver'], isTrue);
      expect(roundOver['winnerId'], equals(p1Id));
      expect(roundOver['eliminatedThisRound'], equals([p2Id]));

      final gameEnded = p1ws.lastOfType('bust_game_ended');
      expect(gameEnded, isNotNull);
      expect(gameEnded!['winnerId'], equals(p1Id));
    });

    test('Bust finals call recordLeaderboardBustOnline when trophy eligible', () {
      final fake = FakeTrophyRecorder();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isBustMode: true,
        trophyRecorder: fake,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-b1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-b2');

      final winningCard = _card(Rank.three, Suit.spades);
      final p1Hand = [winningCard];
      final p2Hand = List.generate(
          5, (i) => _card(Rank.values[i + 2], Suit.hearts));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: p1Hand,
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 5,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: 10,
        preTurnCentreSuit: Suit.spades,
      );

      final drawPile = List.generate(
          10, (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs));

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: [p1Id, p2Id],
        bustTurnsThisRound: {p1Id: 0, p2Id: 0},
        bustPenaltyPoints: {},
      );

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': [winningCard.id],
      });

      expect(fake.leaderboardBustOnlineCalls, 1);
      expect(fake.lastBustWinnerPlayerId, p1Id);
      expect(fake.lastBustPlayers, isNotNull);
      expect(fake.lastBustPlayers!.length, 2);
      expect(fake.lastBustPlayers!.every((p) => p.firebaseUid != null), isTrue);
    });

    test('Bust next round: bust_round_start broadcast with incremented round number', () {
      final (:session, :sockets, :ids) = _makeSession(5, isBustMode: true);
      final p1ws = sockets[0];
      final idsList = ids;

      final cardCounts = {idsList[0]: 1, idsList[1]: 2, idsList[2]: 5, idsList[3]: 8, idsList[4]: 10};
      final players = [
        for (var i = 0; i < 5; i++)
          PlayerModel(
            id: idsList[i],
            displayName: 'Player ${i + 1}',
            tablePosition: _positionFor(i),
            hand: List.generate(
                cardCounts[idsList[i]]!,
                (j) => _card(Rank.values[(j % 13) + 1], Suit.hearts)),
            cardCount: cardCounts[idsList[i]]!,
          ),
      ];

      final drawPile = List.generate(
          20, (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: players,
        currentPlayerId: idsList[4],
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: idsList,
        bustTurnsThisRound: {
          idsList[0]: 2,
          idsList[1]: 2,
          idsList[2]: 2,
          idsList[3]: 2,
          idsList[4]: 1,
        },
        bustPenaltyPoints: {},
      );

      p1ws.clear();
      session.handleAction(idsList[4], {'type': 'draw_card'});

      final roundStart = p1ws.lastOfType('bust_round_start');
      expect(roundStart, isNotNull);
      expect(roundStart!['roundNumber'], equals(2));
    });

    test('disconnect with more than 2 survivors continues (no game_ended)', () {
      final (:session, :sockets, :ids) = _makeSession(4, isBustMode: true);
      for (final id in ids) {
        session.markReady(id);
      }
      final p1ws = sockets[0];
      p1ws.clear();
      session.removePlayer(ids[3]);

      expect(p1ws.ofType('game_ended'), isEmpty);
      expect(p1ws.ofType('player_left'), isNotEmpty);
      expect(p1ws.ofType('state_snapshot'), isNotEmpty);
    });

    test(
        'disconnect when all remaining survivors already have 2 turns '
        'finalizes bust round immediately', () {
      final (:session, :sockets, :ids) = _makeSession(4, isBustMode: true);
      for (final id in ids) {
        session.markReady(id);
      }
      final aId = ids[0];
      final bId = ids[1];
      final cId = ids[2];
      final dId = ids[3];
      final observerWs = sockets[1];

      final tinyHand = [_card(Rank.three, Suit.spades)];
      final players = [
        PlayerModel(
          id: aId,
          displayName: 'A',
          tablePosition: _positionFor(0),
          hand: tinyHand,
          cardCount: 1,
        ),
        PlayerModel(
          id: bId,
          displayName: 'B',
          tablePosition: _positionFor(1),
          hand: tinyHand,
          cardCount: 1,
        ),
        PlayerModel(
          id: cId,
          displayName: 'C',
          tablePosition: _positionFor(2),
          hand: tinyHand,
          cardCount: 1,
        ),
        PlayerModel(
          id: dId,
          displayName: 'D',
          tablePosition: _positionFor(3),
          hand: tinyHand,
          cardCount: 1,
        ),
      ];
      final drawPile = List.generate(
          20,
          (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: players,
        currentPlayerId: aId,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: drawPile,
        bustSurvivorIds: [aId, bId, cId, dId],
        bustTurnsThisRound: {
          aId: 1,
          bId: 2,
          cId: 2,
          dId: 2,
        },
        bustPenaltyPoints: {for (final id in ids) id: 0},
      );

      observerWs.clear();
      session.removePlayer(aId);

      expect(observerWs.ofType('player_left'), isNotEmpty);
      expect(observerWs.ofType('bust_round_over'), isNotEmpty);
      expect(observerWs.ofType('turn_changed'), isEmpty,
          reason: 'Round should end without advancing to another turn');
    });

    test('disconnect leaving <=2 survivors ends game', () {
      final (:session, :sockets, :ids) = _makeSession(3, isBustMode: true);
      for (final id in ids) {
        session.markReady(id);
      }
      final p1ws = sockets[0];
      p1ws.clear();
      session.removePlayer(ids[2]);

      expect(p1ws.ofType('game_ended'), isNotEmpty);
    });

    test(
        'Bust: skipped players gain a turn count when Eight ends turn '
        '(activeSkipCount)',
        () {
      final (:session, :sockets, :ids) = _makeSession(3, isBustMode: true);
      final aId = ids[0];
      final bId = ids[1];
      final cId = ids[2];

      final eightPlayed = _card(Rank.eight, Suit.spades);
      final aHand = [_card(Rank.king, Suit.spades)];
      final bHand = [_card(Rank.five, Suit.hearts)];
      final cHand = [_card(Rank.six, Suit.diamonds)];

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: aId,
            displayName: 'A',
            tablePosition: _positionFor(0),
            hand: aHand,
            cardCount: 1,
          ),
          PlayerModel(
            id: bId,
            displayName: 'B',
            tablePosition: _positionFor(1),
            hand: bHand,
            cardCount: 1,
          ),
          PlayerModel(
            id: cId,
            displayName: 'C',
            tablePosition: _positionFor(2),
            hand: cHand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: aId,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.seven, Suit.spades),
        drawPileCount: 10,
        preTurnCentreSuit: Suit.spades,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: eightPlayed,
        activeSkipCount: 1,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            10, (i) => CardModel(id: 'draw_$i', rank: Rank.four, suit: Suit.clubs)),
        bustSurvivorIds: [aId, bId, cId],
        bustTurnsThisRound: {aId: 0, bId: 0, cId: 0},
        bustPenaltyPoints: {},
      );

      session.handleAction(aId, {'type': 'end_turn'});

      final turns = session.bustTurnsThisRoundForTesting;
      expect(turns[aId], equals(1),
          reason: 'Player A completed a turn');
      expect(turns[bId], equals(1),
          reason: 'Player B was skipped and should still accrue a Bust turn');
      expect(turns[cId], equals(0));

      expect(
        (_latestSnapshot(sockets[0])['currentPlayerId'] as String?) ?? '',
        equals(cId),
      );
    });

    test(
        'Bust placement pile: reshuffles under-top into draw when discard '
        'reaches 5 cards',
        () {
      final (:session, :sockets, :ids) = _makeSession(2, isBustMode: true);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final playCard = _card(Rank.five, Suit.spades);
      final discardTop = _card(Rank.four, Suit.spades);
      final under = List.generate(
          3,
          (i) => CardModel(
                id: 'under_$i',
                rank: Rank.nine,
                suit: Suit.hearts,
              ));

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [playCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.six, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 5,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5, (i) => CardModel(id: 'draw_$i', rank: Rank.seven, suit: Suit.clubs)),
        discardUnderTop: under,
        bustSurvivorIds: [p1Id, p2Id],
        bustTurnsThisRound: {p1Id: 0, p2Id: 0},
        bustPenaltyPoints: {},
      );

      final drawBefore = session.drawPileCountForTesting;
      expect(session.discardUnderTopCountForTesting, equals(3));

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      expect(p1ws.lastOfType('reshuffle'), isNotNull);
      expect(session.discardUnderTopCountForTesting, equals(0));
      expect(session.drawPileCountForTesting, equals(drawBefore + 4));
    });
  });

  // ── penalty chain ──────────────────────────────────────────────────────────

  group('penalty chain', () {
    test('stacking a 2 on an active penalty increases penalty count', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final twoCard = _card(Rank.two, Suit.spades);
      final discardTop = _card(Rank.two, Suit.hearts);

      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [twoCard, _card(Rank.five, Suit.spades)],
            cardCount: 2,
          ),
          PlayerModel(
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.five, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: 10,
        preTurnCentreSuit: Suit.hearts,
        activePenaltyCount: 2,
      );

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            10, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['two_spades'],
      });

      final snap = _latestSnapshot(p1ws);
      expect(snap['activePenaltyCount'], equals(4)); // 2 + 2
    });
  });

  group('disconnect grace (standard)', () {
    test('handleSocketDisconnected does not broadcast game_ended immediately',
        () {
      final g = _makeKnownGame();
      g.p2ws.clear();
      g.session.handleSocketDisconnected(g.p1Id);
      expect(g.p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
    });

    test('removePlayer after grace ends game for other player', () {
      final g = _makeKnownGame();
      g.p2ws.clear();
      g.session.handleSocketDisconnected(g.p1Id);
      g.session.removePlayer(g.p1Id);
      expect(g.p2ws.lastOfType('game_ended')?['reason'], 'player_disconnected');
    });

    test('tryReattachSocket sends state_snapshot to new socket', () {
      final g = _makeKnownGame();
      g.session.handleSocketDisconnected(g.p1Id);
      final newWs = _FakeWs();
      expect(g.session.tryReattachSocket(g.p1Id, newWs), isTrue);
      expect(newWs.messages.any((m) => m['type'] == 'state_snapshot'), isTrue);
    });

    test('declare_last_cards works on current player turn', () {
      final g = _makeKnownGame();
      expect(g.p1ws.messages.any((m) => m['type'] == 'last_cards_pressed'),
          isFalse);
      g.session.handleAction(g.p1Id, {'type': 'declare_last_cards'});
      expect(g.p1ws.lastOfType('last_cards_pressed')?['playerId'], g.p1Id);
      final snap = _latestSnapshot(g.p1ws);
      expect(
        (snap['lastCardsDeclaredBy'] as List).map((e) => e as String),
        contains(g.p1Id),
      );
    });
  });
}
