import 'dart:convert';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:test/test.dart';

import 'package:last_cards_server/game_session.dart';

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

// ── Session builders ──────────────────────────────────────────────────────────

/// Creates a [GameSession] with [n] players added (not yet started).
({GameSession session, List<_FakeWs> sockets, List<String> ids})
    _makeSession(int n) {
  final session = GameSession('TEST');
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
        isActiveTurn: true,
      ),
      PlayerModel(
        id: p2Id,
        displayName: 'Player 2',
        tablePosition: TablePosition.top,
        hand: p2Hand,
        cardCount: p2Hand.length,
        isActiveTurn: false,
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
            isActiveTurn: true,
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

      // 2-card penalty: hand grows by 2.
      final snapAfter = _latestSnapshot(p1ws);
      final handAfter = _hand(snapAfter).length;
      expect(handAfter, equals(handBefore + 2));
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
        'declaredRank': 'seven',
      });

      final played = p1ws.lastOfType('card_played');
      expect(played, isNotNull);
      final cards = played!['cards'] as List;
      expect(cards.length, equals(1));
      final card = cards.first as Map<String, dynamic>;
      expect(card['rank'], equals('joker'));
      expect(card['jokerDeclaredSuit'], equals('hearts'));
      expect(card['jokerDeclaredRank'], equals('seven'));
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
            isActiveTurn: true,
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
}
