import 'dart:async';
import 'dart:convert';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/models/table_position_layout.dart';
import 'package:last_cards/shared/engine/game_engine.dart'
    show canClearHandInOneTurn, standardFiftyFourDeckInCanonicalOrder;
import 'package:last_cards/shared/rules/last_cards_rules.dart'
    show canHandClearInOneTurnHandOnly;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:last_cards_server/game_session.dart';
import 'package:last_cards_server/trophy_recorder.dart';
import 'package:last_cards_server/wallet_service.dart';

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

/// In-memory [TrophyPersistence] for tests (no Firestore).
class _CapturingTrophyPersistence implements TrophyPersistence {
  int leaderboardOnlineCasualCalls = 0;
  int leaderboardBustOnlineCalls = 0;
  String? lastCasualWinnerPlayerId;
  List<({String playerId, String? firebaseUid, String displayName})>?
      lastCasualPlayers;
  int? lastCasualPlayerCount;
  String? lastBustWinnerPlayerId;
  List<({String playerId, String? firebaseUid, String displayName})>?
      lastBustPlayers;
  int? lastBustPlayerCount;

  int rankedResultCalls = 0;
  String? lastRankedWinnerUid;
  List<({String playerId, String uid, String displayName})>?
      lastRankedAllPlayerUids;
  int? lastRankedPlayerCount;

  int leavePenaltyCalls = 0;
  bool lastRankedHardcore = false;

  @override
  void recordRankedResult({
    required String winnerUid,
    required List<({String playerId, String uid, String displayName})>
        allPlayerUids,
    int playerCount = 0,
    bool rankedHardcore = false,
  }) {
    rankedResultCalls++;
    lastRankedHardcore = rankedHardcore;
    lastRankedWinnerUid = winnerUid;
    lastRankedAllPlayerUids = allPlayerUids;
    lastRankedPlayerCount = playerCount;
  }

  @override
  void recordLeavePenalty(String uid,
      {required String displayName,
      bool rankedHardcore = false,
      int playerCount = 4}) {
    leavePenaltyCalls++;
    lastRankedHardcore = rankedHardcore;
  }

  @override
  void recordLeaderboardOnlineCasual({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  }) {
    leaderboardOnlineCasualCalls++;
    lastCasualWinnerPlayerId = winnerPlayerId;
    lastCasualPlayers = players;
    lastCasualPlayerCount = playerCount;
  }

  @override
  void recordLeaderboardBustOnline({
    required String winnerPlayerId,
    required List<({String playerId, String? firebaseUid, String displayName})>
        players,
    required int playerCount,
  }) {
    leaderboardBustOnlineCalls++;
    lastBustWinnerPlayerId = winnerPlayerId;
    lastBustPlayers = players;
    lastBustPlayerCount = playerCount;
  }
}

/// In-memory [WalletPersistence] for tests (no Firestore). [balances] seeds
/// starting coin balances by uid; charge/payout/refund calls mutate it and
/// are recorded for assertions.
class _FakeWalletPersistence implements WalletPersistence {
  final Map<String, int> balances = {};
  final chargeCalls = <({String uid, int amount})>[];
  final payoutCalls = <({String uid, int amount})>[];
  final refundCalls = <({String uid, int amount})>[];

  @override
  Future<int?> checkBalance(String uid) async => balances[uid];

  @override
  void chargeStake(String uid, int amount) {
    chargeCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) - amount;
  }

  @override
  void payout(String uid, int amount) {
    payoutCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) + amount;
  }

  @override
  void refund(String uid, int amount) {
    refundCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) + amount;
  }
}

/// Like [_FakeWalletPersistence], but [checkBalance] doesn't resolve until
/// the test explicitly releases a gate — lets tests drive races that happen
/// while [GameSession] is suspended mid-`await` inside its wager lock-in
/// (e.g. a decline or the match ending arriving before the balance check
/// returns).
class _ControllableWalletPersistence implements WalletPersistence {
  final Map<String, int> balances = {};
  final chargeCalls = <({String uid, int amount})>[];
  final payoutCalls = <({String uid, int amount})>[];
  final refundCalls = <({String uid, int amount})>[];
  Completer<void>? _gate;

  /// The next [checkBalance] call blocks until [releaseGate] is called.
  void armGate() => _gate = Completer<void>();
  void releaseGate() => _gate?.complete();

  @override
  Future<int?> checkBalance(String uid) async {
    if (_gate != null) await _gate!.future;
    return balances[uid];
  }

  @override
  void chargeStake(String uid, int amount) {
    chargeCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) - amount;
  }

  @override
  void payout(String uid, int amount) {
    payoutCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) + amount;
  }

  @override
  void refund(String uid, int amount) {
    refundCalls.add((uid: uid, amount: amount));
    balances[uid] = (balances[uid] ?? 0) + amount;
  }
}

/// Mirrors [RoomManager]'s real cross-session double-lock guard, so tests can
/// share one instance across two [GameSession]s the way [RoomManager] does.
class _FakeWagerLockGuard {
  final locked = <String>{};

  bool tryLock(Set<String> uids) {
    if (uids.any(locked.contains)) return false;
    locked.addAll(uids);
    return true;
  }

  void release(Set<String> uids) => locked.removeAll(uids);
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

/// Two-player game: P1 has already played a King this turn ([lastPlayedThisTurn]),
/// unless [p2Turn] is true — then it is P2's turn so P1 may declare Last Cards
/// (not on own turn). [nextPlayerId] after P2 [end_turn] is P1, so the bluff check
/// still applies to P1 when appropriate.
({
  GameSession session,
  _FakeWs p1ws,
  _FakeWs p2ws,
  String p1Id,
  String p2Id,
}) _makeTwoPlayerKingRepeatTurnForP1(
  List<CardModel> p1Hand, {
  bool p2Turn = false,
}) {
  final (:session, :sockets, :ids) = _makeSession(2);
  final p1ws = sockets[0];
  final p2ws = sockets[1];
  final p1Id = ids[0];
  final p2Id = ids[1];

  final kingPlayed = _card(Rank.king, Suit.hearts);
  final p2PlayThisTurn = _card(Rank.three, Suit.hearts);
  final p2Hand = p2Turn
      ? [
          _card(Rank.five, Suit.hearts),
          _card(Rank.seven, Suit.hearts),
          _card(Rank.nine, Suit.hearts),
          _card(Rank.jack, Suit.hearts),
          _card(Rank.queen, Suit.hearts),
          _card(Rank.king, Suit.diamonds),
        ]
      : [
          _card(Rank.three, Suit.hearts),
          _card(Rank.five, Suit.hearts),
          _card(Rank.seven, Suit.hearts),
          _card(Rank.nine, Suit.hearts),
          _card(Rank.jack, Suit.hearts),
          _card(Rank.queen, Suit.hearts),
          _card(Rank.king, Suit.diamonds),
        ];
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
    currentPlayerId: p2Turn ? p2Id : p1Id,
    direction: PlayDirection.clockwise,
    discardTopCard: p2Turn ? p2PlayThisTurn : kingPlayed,
    drawPileCount: drawPile.length,
    preTurnCentreSuit: Suit.hearts,
    actionsThisTurn: 1,
    cardsPlayedThisTurn: 1,
    lastPlayedThisTurn: p2Turn ? p2PlayThisTurn : kingPlayed,
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
      expect(cp['cardsPlayedThisTurn'], equals(1));
    });

    test(
        'multi-card play_cards broadcasts cardsPlayedThisTurn and card count',
        () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p2ws = sockets[1];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final s7 = _card(Rank.seven, Suit.spades);
      final h7 = _card(Rank.seven, Suit.hearts);
      final d7 = _card(Rank.seven, Suit.diamonds);
      final c7 = _card(Rank.seven, Suit.clubs);
      final filler = _card(Rank.three, Suit.spades);
      final p1Hand = [s7, h7, d7, c7, filler];
      final p2Hand = [
        _card(Rank.four, Suit.hearts),
        _card(Rank.five, Suit.hearts),
      ];
      final discardTop = _card(Rank.seven, Suit.hearts);
      final drawPile = List.generate(
          16, (i) => CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs));

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
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: p2Hand.length,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);

      p1ws.clear();
      p2ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': [s7.id, h7.id, d7.id, c7.id],
      });

      expect(p1ws.ofType('error'), isEmpty);
      final cp = p1ws.lastOfType('card_played');
      expect(cp, isNotNull);
      expect(cp!['cardsPlayedThisTurn'], equals(4));
      expect((cp['cards'] as List).length, equals(4));
    });

    test(
        '2-player Skip (8): auto-advances same seat so actionsThisTurn resets '
        '(matches offline TableScreen)', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p2ws = sockets[1];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final eightH = _card(Rank.eight, Suit.hearts);
      final threeH = _card(Rank.three, Suit.hearts);
      final p1Hand = [eightH, threeH];
      final p2Hand = [
        _card(Rank.four, Suit.spades),
        _card(Rank.five, Suit.spades),
      ];
      final discardTop = _card(Rank.seven, Suit.hearts);
      final drawPile = List.generate(
          10, (i) => CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs));

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
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: p2Hand.length,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.hearts,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);

      p1ws.clear();
      p2ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': [eightH.id],
      });

      expect(p1ws.ofType('error'), isEmpty);
      final turnChanged = p1ws.ofType('turn_changed');
      expect(turnChanged, isNotEmpty);
      expect(
        turnChanged.last['currentPlayerId'],
        equals(p1Id),
        reason: 'skip wraps to same player in 2p',
      );

      final snap = _latestSnapshot(p1ws);
      expect(snap['currentPlayerId'], equals(p1Id));
      expect(snap['actionsThisTurn'], equals(0));
      expect(snap['activeSkipCount'], equals(0));
    });

    test(
        '2-player Skip (8): same-seat reset keeps lastCardsDeclaredBy for the '
        'actor (does not use advanceTurn)', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final eightH = _card(Rank.eight, Suit.hearts);
      final threeH = _card(Rank.three, Suit.hearts);
      final p1Hand = [eightH, threeH];
      final p2Hand = [
        _card(Rank.four, Suit.spades),
        _card(Rank.five, Suit.spades),
      ];
      final discardTop = _card(Rank.seven, Suit.hearts);
      final drawPile = List.generate(
          10, (i) => CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs));

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
            id: p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: p2Hand.length,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: discardTop,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.hearts,
        lastCardsDeclaredBy: {p1Id},
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);

      p1ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': [eightH.id],
      });

      final snap = _latestSnapshot(p1ws);
      final declared =
          (snap['lastCardsDeclaredBy'] as List).cast<String>().toSet();
      expect(declared, contains(p1Id));
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

    test('invalid play under stacked pick-up draws full stack not 2', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final p1Hand = [_card(Rank.three, Suit.spades)];
      final p2Hand = [_card(Rank.five, Suit.hearts), _card(Rank.six, Suit.hearts)];
      final discardTop = _card(Rank.four, Suit.hearts);
      final drawPile = List.generate(
          20, (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs));

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
        activePenaltyCount: 7,
        penaltyChainLive: true,
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

      final invalidEv = p1ws.lastOfType('invalid_play_penalty');
      expect(invalidEv, isNotNull);
      expect(invalidEv!['drawCount'], equals(7));

      final penaltyAp = p1ws.lastOfType('penalty_applied');
      expect(penaltyAp, isNotNull);
      expect(penaltyAp!['targetPlayerId'], equals(p1Id));
      expect(penaltyAp['cardsDrawn'], equals(7));
      expect(penaltyAp['newPenaltyStack'], equals(0));

      final snapAfter = _latestSnapshot(p1ws);
      expect(_hand(snapAfter).length, equals(handBefore + 7));
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

    test(
        'declare_joker after 2-player King accepts turn-starter declaration (5♠ on K♠)',
        () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p1Id = ids[0];
      final p2Id = ids[1];

      final joker = _joker('joker_r', Suit.hearts);
      final kingPlayed = _card(Rank.king, Suit.spades);
      final p1Hand = [joker];
      final p2Hand = [_card(Rank.five, Suit.hearts)];
      final drawPile = List.generate(
          5,
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
        discardTopCard: kingPlayed,
        drawPileCount: drawPile.length,
        preTurnCentreSuit: Suit.spades,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: kingPlayed,
      );

      session.seedStateForTesting(state: state, drawPile: drawPile);
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'declare_joker',
        'jokerCardId': 'joker_r',
        'declaredSuit': 'spades',
        'declaredRank': 'five',
      });

      expect(p1ws.lastOfType('error'), isNull);
      final played = p1ws.lastOfType('card_played');
      expect(played, isNotNull);
      final cards = played!['cards'] as List;
      expect(cards.length, equals(1));
      final card = cards.first as Map<String, dynamic>;
      expect(card['jokerDeclaredSuit'], equals('spades'));
      expect(card['jokerDeclaredRank'], equals('five'));
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
      final recorder = _CapturingTrophyPersistence();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isRanked: false,
        trophyRecorder: recorder,
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

      expect(recorder.leaderboardOnlineCasualCalls, 1);
      expect(recorder.lastCasualWinnerPlayerId, p1Id);
      expect(recorder.lastCasualPlayers, isNotNull);
      expect(recorder.lastCasualPlayers!.length, 2);
      expect(recorder.lastCasualPlayers!.first.firebaseUid, 'firebase-p1');
    });

    test(
        'public ranked game broadcasts game_ended with ratingChanges and records ranked',
        () {
      final recorder = _CapturingTrophyPersistence();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isRanked: true,
        trophyRecorder: recorder,
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

      p1ws.clear();
      p2ws.clear();
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final ended = p1ws.lastOfType('game_ended');
      expect(ended, isNotNull);
      expect(ended!['winnerId'], equals(p1Id));
      expect(ended['trophyEligible'], isTrue);
      final changes = ended['ratingChanges'] as Map<String, dynamic>?;
      expect(changes, isNotNull);
      // 2-player table: scaled MMR (+15 / −10), not the historic 4p +25/−15.
      expect(changes![p1Id], 15);
      expect(changes[p2Id], -10);

      expect(recorder.rankedResultCalls, 1);
      expect(recorder.lastRankedWinnerUid, 'firebase-p1');
      expect(recorder.lastRankedPlayerCount, 2);
      expect(recorder.lastRankedAllPlayerUids, isNotNull);
      expect(recorder.lastRankedAllPlayerUids!.length, 2);
      expect(recorder.leaderboardOnlineCasualCalls, 0);
    });

    test(
        'private lobby does not record leaderboard_online on win (not trophy eligible)',
        () {
      final recorder = _CapturingTrophyPersistence();
      final session = GameSession(
        'TEST',
        isPrivate: true,
        isRanked: false,
        trophyRecorder: recorder,
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

      expect(recorder.leaderboardOnlineCasualCalls, 0);
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
      final recorder = _CapturingTrophyPersistence();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isBustMode: true,
        trophyRecorder: recorder,
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

      expect(recorder.leaderboardBustOnlineCalls, 1);
      expect(recorder.lastBustWinnerPlayerId, p1Id);
      expect(recorder.lastBustPlayers, isNotNull);
      expect(recorder.lastBustPlayers!.length, 2);
      expect(recorder.lastBustPlayers!.every((p) => p.firebaseUid != null), isTrue);
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

    test('socket disconnect keeps bust survivor under silent AI', () {
      final (:session, :sockets, :ids) = _makeSession(4, isBustMode: true);
      for (final id in ids) {
        session.markReady(id);
      }
      final observer = sockets[0];
      observer.clear();
      session.handleSocketDisconnected(ids[3], sockets[3]);

      expect(session.isControlledByAiForTesting(ids[3]), isTrue);
      expect(observer.ofType('game_ended'), isEmpty);
      expect(observer.ofType('player_left'), isEmpty);
      expect(observer.ofType('player_socket_lost'), isEmpty);
      expect(session.gameStateForTesting.players.length, 4);
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

  group('disconnect (standard)', () {
    test('forced leave keeps two-player seat under silent AI', () {
      fakeAsync((async) {
        final g = _makeKnownGame();
        g.p2ws.clear();
        g.session.handleSocketDisconnected(g.p1Id, g.p1ws, forceRemove: true);
        expect(g.session.isControlledByAiForTesting(g.p1Id), isTrue);
        expect(g.p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
        expect(
          g.p2ws.messages.any((m) => m['type'] == 'player_socket_lost'),
          isFalse,
        );
        expect(
          g.p2ws.messages.any((m) => m['type'] == 'player_left'),
          isFalse,
        );

        async.elapse(GameSession.aiActionDelayUpperBound);
        // AI acts for the vacant seat; opponent still sees a human-shaped roster.
        final snap = _latestSnapshot(g.p2ws);
        final players = snap['players'] as List<dynamic>;
        expect(players.length, 2);
        final p1 = players.cast<Map<String, dynamic>>().firstWhere(
              (p) => p['id'] == g.p1Id,
            );
        expect(p1['isAi'], isFalse);
        expect(p1['displayName'], isNotNull);
      });
    });

    test('brief disconnect uses AI then allows silent rejoin', () {
      fakeAsync((async) {
        final g = _makeKnownGame();
        g.p2ws.clear();
        g.session.handleSocketDisconnected(g.p1Id, g.p1ws);
        expect(g.session.isControlledByAiForTesting(g.p1Id), isTrue);
        expect(
          g.p2ws.messages.any((m) => m['type'] == 'player_socket_lost'),
          isFalse,
        );
        expect(g.p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);

        final newWs = _FakeWs();
        expect(g.session.tryReattachSocket(g.p1Id, newWs), isTrue);
        expect(g.session.isControlledByAiForTesting(g.p1Id), isFalse);
        expect(
          g.p2ws.messages.any((m) => m['type'] == 'player_socket_restored'),
          isFalse,
        );
        expect(newWs.messages.any((m) => m['type'] == 'state_snapshot'), isTrue);
      });
    });

    test('disconnect never removes seat after former grace window', () {
      fakeAsync((async) {
        final g = _makeKnownGame();
        g.p2ws.clear();
        g.session.handleSocketDisconnected(g.p1Id, g.p1ws);
        async.elapse(Duration.zero);
        async.elapse(GameSession.socketDisconnectGrace);
        expect(g.session.isControlledByAiForTesting(g.p1Id), isTrue);
        expect(g.p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
        expect(g.p2ws.messages.any((m) => m['type'] == 'player_left'), isFalse);
      });
    });

    test('disconnect on current turn lets server AI resolve the turn', () {
      fakeAsync((async) {
        final (:session, :sockets, :ids) = _makeSession(2);
        final p1ws = sockets[0];
        final p2ws = sockets[1];
        final p1Id = ids[0];
        final p2Id = ids[1];

        final p1Hand = [_card(Rank.three, Suit.spades)];
        final p2Hand = [_card(Rank.five, Suit.hearts)];
        final discardTop = _card(Rank.two, Suit.spades);
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
          activePenaltyCount: 4,
        );

        session.seedStateForTesting(state: state, drawPile: drawPile);
        p2ws.clear();
        session.handleSocketDisconnected(p1Id, p1ws);
        expect(session.isControlledByAiForTesting(p1Id), isTrue);

        // Disconnect AI must not blaze through the turn — humans need time to
        // declare Last Cards on an opponent's turn (offline has the same grace).
        async.elapse(
          Duration(milliseconds: GameSession.aiOpeningThinkMsMin - 1),
        );
        expect(
          p2ws.messages.any((m) => m['type'] == 'card_drawn'),
          isFalse,
        );

        async.elapse(GameSession.aiActionDelayUpperBound);

        // Facing a pick-up stack with no Two, AI draws the penalty and advances.
        expect(
          p2ws.messages.any((m) => m['type'] == 'card_drawn'),
          isTrue,
        );
        expect(
          p2ws.lastOfType('turn_changed')?['currentPlayerId'],
          equals(p2Id),
        );
        final snap = _latestSnapshot(p2ws);
        final p1 = (snap['players'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((p) => p['id'] == p1Id);
        expect(p1['isAi'], isFalse);
      });
    });

    test('disconnect keeps three-player roster and hand (no pile dump)', () {
      fakeAsync((async) {
        final (:session, :sockets, :ids) = _makeSession(3);
        final p2ws = sockets[1];
        final p3ws = sockets[2];
        final p1Id = ids[0];
        final p2Id = ids[1];
        final p3Id = ids[2];

        final leaverCard = _card(Rank.six, Suit.diamonds);
        final drawPileBefore = List.generate(
            8,
            (i) =>
                CardModel(id: 'pile_$i', rank: Rank.four, suit: Suit.clubs));

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
            PlayerModel(
              id: p3Id,
              displayName: 'P3',
              tablePosition: TablePosition.left,
              hand: [leaverCard],
              cardCount: 1,
            ),
          ],
          currentPlayerId: p1Id,
          direction: PlayDirection.clockwise,
          discardTopCard: _card(Rank.two, Suit.spades),
          drawPileCount: drawPileBefore.length,
          preTurnCentreSuit: Suit.spades,
        );

        session.seedStateForTesting(state: state, drawPile: drawPileBefore);
        p2ws.clear();
        session.handleSocketDisconnected(p3Id, p3ws);
        async.elapse(GameSession.socketDisconnectGrace);

        expect(session.isControlledByAiForTesting(p3Id), isTrue);
        expect(session.drawPileCountForTesting, drawPileBefore.length);
        expect(session.gameStateForTesting.players.length, 3);
        expect(p2ws.messages.any((m) => m['type'] == 'player_left'), isFalse);
      });
    });

    test('forced leave keeps three-player seat under AI without dumping hand',
        () {
      final (:session, :sockets, :ids) = _makeSession(3);
      final p1ws = sockets[0];
      final p2ws = sockets[1];
      final p3ws = sockets[2];
      final p1Id = ids[0];
      final p2Id = ids[1];
      final p3Id = ids[2];

      final drawPileBefore = List.generate(
          10,
          (i) =>
              CardModel(id: 'filler_$i', rank: Rank.four, suit: Suit.clubs));
      final p3Hand = [_card(Rank.six, Suit.diamonds)];

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
          PlayerModel(
            id: p3Id,
            displayName: 'P3',
            tablePosition: TablePosition.left,
            hand: p3Hand,
            cardCount: 1,
          ),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: drawPileBefore.length,
        preTurnCentreSuit: Suit.spades,
      );

      session.seedStateForTesting(state: state, drawPile: drawPileBefore);

      p2ws.clear();
      session.handleSocketDisconnected(p3Id, p3ws, forceRemove: true);

      expect(p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
      expect(session.isControlledByAiForTesting(p3Id), isTrue);
      expect(session.drawPileCountForTesting, drawPileBefore.length);

      final snap = _latestSnapshot(p1ws);
      final players = snap['players'] as List<dynamic>;
      expect(players.length, 3);
    });

    test('last connected human leaving tears down AI-only room', () {
      var emptyCalled = false;
      final session = GameSession(
        'ROOM',
        onBecameEmpty: (_) => emptyCalled = true,
      );
      final w1 = _FakeWs();
      final w2 = _FakeWs();
      final id1 = session.addPlayer(w1, 'A');
      final id2 = session.addPlayer(w2, 'B');
      session.markReady(id1);
      session.markReady(id2);

      session.handleSocketDisconnected(id1, w1);
      expect(emptyCalled, isFalse);
      expect(session.isControlledByAiForTesting(id1), isTrue);

      session.handleSocketDisconnected(id2, w2);
      expect(emptyCalled, isTrue);
      expect(session.isEmpty, isTrue);
    });

    test('tryReattachSocket fails after permanent leave', () {
      final g = _makeKnownGame();
      g.session.handleSocketDisconnected(g.p1Id, g.p1ws, forceRemove: true);
      g.p2ws.clear();
      final newWs = _FakeWs();
      expect(g.session.tryReattachSocket(g.p1Id, newWs), isFalse);
      expect(newWs.messages.any((m) => m['type'] == 'state_snapshot'), isFalse);
      expect(g.session.isControlledByAiForTesting(g.p1Id), isTrue);
    });

    test('tryReattachSocket replaces socket when previous still connected', () {
      final g = _makeKnownGame();
      final newWs = _FakeWs();
      expect(g.session.tryReattachSocket(g.p1Id, newWs), isTrue);
      expect(newWs.messages.any((m) => m['type'] == 'state_snapshot'), isTrue);
    });

    test('handleSocketDisconnected ignores stale socket after reattach', () {
      final g = _makeKnownGame();
      final newWs = _FakeWs();
      expect(g.session.tryReattachSocket(g.p1Id, newWs), isTrue);
      g.p2ws.clear();
      g.session.handleSocketDisconnected(g.p1Id, g.p1ws);
      expect(g.p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
      expect(g.session.isControlledByAiForTesting(g.p1Id), isFalse);
    });

    test('onBecameEmpty when last connected player disconnects after game ended',
        () {
      var emptyCalled = false;
      final session = GameSession(
        'ROOM',
        onBecameEmpty: (_) => emptyCalled = true,
      );
      final w1 = _FakeWs();
      final w2 = _FakeWs();
      final id1 = session.addPlayer(w1, 'A');
      final id2 = session.addPlayer(w2, 'B');
      session.markReady(id1);
      session.markReady(id2);
      session.handleSocketDisconnected(id1, w1, forceRemove: true);
      expect(emptyCalled, isFalse);
      session.handleSocketDisconnected(id2, w2, forceRemove: true);
      expect(emptyCalled, isTrue);
    });

    test(
        'ranked 1v1: opponent leave applies leave penalty and continues under AI',
        () {
      final recorder = _CapturingTrophyPersistence();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 2,
        isRanked: true,
        trophyRecorder: recorder,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'firebase-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'firebase-p2');

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
        discardTopCard: _card(Rank.two, Suit.spades),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.spades,
      );
      // markReady triggers _startGame, which sets _wasFullRoster = true and
      // _startingPlayerCount = 2.  seedStateForTesting then overwrites the
      // dealt hands with our deterministic state.
      session.markReady(p1Id);
      session.markReady(p2Id);

      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(
            5, (i) => CardModel(id: 'f$i', rank: Rank.seven, suit: Suit.clubs)),
      );

      // P1 leaves — seat stays under AI; leave penalty now; match continues.
      session.handleSocketDisconnected(p1Id, p1ws, forceRemove: true);

      expect(session.isControlledByAiForTesting(p1Id), isTrue);
      expect(p2ws.messages.any((m) => m['type'] == 'game_ended'), isFalse);
      expect(recorder.leavePenaltyCalls, 1);
      expect(recorder.rankedResultCalls, 0,
          reason: 'match continues; end MMR waits for a natural finish');
      expect(session.tryReattachSocket(p1Id, _FakeWs()), isFalse);
      expect(p2Id, isNotEmpty);
    });

    test('declare_last_cards rejected on own turn', () {
      final g = _makeKnownGame();
      expect(g.p1ws.messages.any((m) => m['type'] == 'last_cards_pressed'),
          isFalse);
      g.session.handleAction(g.p1Id, {'type': 'declare_last_cards'});
      expect(g.p1ws.lastOfType('error')?['code'], 'last_cards_own_turn');
      expect(g.p1ws.ofType('last_cards_pressed'), isEmpty);
    });
  });

  group('text chat', () {
    test('lobby text_chat broadcasts sanitized message', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p1ws = sockets[0];
      final p2ws = sockets[1];
      p2ws.clear();

      session.handleTextChat(ids[0], {'type': 'text_chat', 'text': '  gl hf  '});

      final msg = p2ws.lastOfType('text_chat');
      expect(msg, isNotNull);
      expect(msg!['playerId'], ids[0]);
      expect(msg['displayName'], 'Player 1');
      expect(msg['text'], 'gl hf');
      expect(
        p1ws.messages.any((m) => m['type'] == 'text_chat'),
        isTrue,
      );
    });

    test('text_chat masks fuck and rejects hate speech', () {
      final (:session, :sockets, :ids) = _makeSession(2);
      final p2ws = sockets[1];
      p2ws.clear();

      session.handleTextChat(ids[0], {'type': 'text_chat', 'text': 'what the fuck'});
      expect(p2ws.lastOfType('text_chat')?['text'], 'what the Fu*k');

      p2ws.clear();
      sockets[0].clear();
      session.handleTextChat(ids[0], {'type': 'text_chat', 'text': 'you nigger'});
      expect(p2ws.messages.any((m) => m['type'] == 'text_chat'), isFalse);
      expect(sockets[0].lastOfType('error')?['code'], 'chat_rejected');
    });
  });

  group('last_cards declare — server Joker bluff exemption', () {
    test('holding Joker: non-clearable hand does not record bluff penalty', () {
      final p1Hand = [
        _card(Rank.two, Suit.hearts),
        _card(Rank.four, Suit.diamonds),
        _card(Rank.six, Suit.clubs),
        _card(Rank.eight, Suit.spades),
        _joker('joker_r', Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(p1Hand), isFalse);

      final g = _makeTwoPlayerKingRepeatTurnForP1(p1Hand, p2Turn: true);
      expect(
        canClearHandInOneTurn(
          state: g.session.gameStateForTesting,
          playerId: g.p1Id,
          isBustMode: false,
        ),
        isFalse,
      );

      g.p1ws.clear();
      g.p2ws.clear();
      g.session.handleAction(g.p1Id, {'type': 'declare_last_cards'});
      g.session.handleAction(g.p2Id, {'type': 'end_turn'});

      expect(g.p1ws.ofType('last_cards_bluff'), isEmpty);
    });

    test('no Joker: non-clearable hand records bluff; penalty on repeat turn',
        () {
      final p1Hand = [
        _card(Rank.two, Suit.hearts),
        _card(Rank.four, Suit.diamonds),
        _card(Rank.six, Suit.clubs),
        _card(Rank.eight, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(p1Hand), isFalse);

      final g = _makeTwoPlayerKingRepeatTurnForP1(p1Hand, p2Turn: true);
      expect(
        canClearHandInOneTurn(
          state: g.session.gameStateForTesting,
          playerId: g.p1Id,
          isBustMode: false,
        ),
        isFalse,
      );

      g.p1ws.clear();
      g.p2ws.clear();
      g.session.handleAction(g.p1Id, {'type': 'declare_last_cards'});
      g.session.handleAction(g.p2Id, {'type': 'end_turn'});

      expect(g.p1ws.lastOfType('last_cards_bluff')?['playerId'], g.p1Id);
    });
  });

  group('wager', () {
    ({
      GameSession session,
      _FakeWs p1ws,
      _FakeWs p2ws,
      String p1Id,
      String p2Id,
      _FakeWalletPersistence wallet,
      _FakeWagerLockGuard guard,
    }) makePrivateWagerLobby({int p1Balance = 100, int p2Balance = 100}) {
      final wallet = _FakeWalletPersistence();
      final guard = _FakeWagerLockGuard();
      wallet.balances['fb-p1'] = p1Balance;
      wallet.balances['fb-p2'] = p2Balance;
      final session = GameSession(
        'TEST',
        isPrivate: true,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      return (
        session: session,
        p1ws: p1ws,
        p2ws: p2ws,
        p1Id: p1Id,
        p2Id: p2Id,
        wallet: wallet,
        guard: guard,
      );
    }

    test('non-host cannot set a pot wager', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p2Id, mode: 'pot', stakeCoins: 20);
      expect(g.p2ws.lastOfType('error')?['code'], 'not_host');
      expect(g.session.wagerState.config, isNull);
    });

    test('host setting a pot wager broadcasts wager_state to everyone', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      final broadcast = g.p2ws.lastOfType('wager_state');
      expect(broadcast?['mode'], 'pot');
      expect(broadcast?['stakeCoins'], 20);
      expect(broadcast?['initiatorPlayerId'], g.p1Id);
    });

    test('side-bet targeting self is rejected', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 20, targetPlayerId: g.p1Id);
      expect(g.p1ws.lastOfType('error')?['code'], 'invalid_wager');
      expect(g.session.wagerState.config, isNull);
    });

    test('a negative stake is rejected', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: -5);
      expect(g.p1ws.lastOfType('error')?['code'], 'invalid_wager');
    });

    test('stakeCoins: 0 clears a proposed pot wager (host only)', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.p2ws.clear();

      g.session.setWagerConfig(g.p2Id, mode: 'pot', stakeCoins: 0);
      expect(g.p2ws.lastOfType('error')?['code'], 'not_host');
      expect(g.session.wagerState.config, isNotNull);

      g.p1ws.clear();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 0);
      expect(g.p1ws.lastOfType('wager_state')?['mode'], isNull);
      expect(g.session.wagerState.config, isNull);
    });

    test('stakeCoins: 0 with no active wager is a silent no-op', () {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 0);
      expect(g.p1ws.lastOfType('error'), isNull);
      expect(g.p1ws.lastOfType('wager_state'), isNull);
    });

    test('a declined side-bet is silently dropped and the table starts '
        'normally, without blocking on the other two participants',
        () async {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p2Id,
          mode: 'sideBet', stakeCoins: 15, targetPlayerId: g.p1Id);
      // p1 (the target) never accepts.
      g.p1ws.clear();

      await g.session.startGameFromHost(g.p1Id);

      // The match starts normally...
      expect(g.p1ws.lastOfType('session_config'), isNotNull);
      // ...but the side-bet itself never charged anyone or stayed active.
      expect(g.wallet.chargeCalls, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test('a participant with no Firebase UID makes the wager ineligible', () {
      final wallet = _FakeWalletPersistence();
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: true,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      session.addPlayer(p2ws, 'P2'); // no firebaseUid — guest seat

      session.setWagerConfig(p1Id, mode: 'pot', stakeCoins: 20);
      expect(p1ws.lastOfType('error')?['code'], 'wager_ineligible');
      expect(session.wagerState.config, isNull);
    });

    test('start is blocked until every seat accepts the pot wager', () async {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.p1ws.clear();

      await g.session.startGameFromHost(g.p1Id);

      expect(g.p1ws.lastOfType('error')?['code'], 'wager_not_accepted');
      expect(g.p1ws.lastOfType('session_config'), isNull);
      expect(g.wallet.chargeCalls, isEmpty);
    });

    test('start is blocked when a participant lacks sufficient coins',
        () async {
      final g = makePrivateWagerLobby(p2Balance: 5);
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);
      g.p1ws.clear();
      g.p2ws.clear();

      await g.session.startGameFromHost(g.p1Id);

      expect(g.p2ws.lastOfType('error')?['code'], 'insufficient_coins');
      expect(g.p1ws.lastOfType('session_config'), isNull);
      expect(g.wallet.chargeCalls, isEmpty,
          reason: 'balance check must fail before any stake is charged');
    });

    test('start is blocked when a participant uid is already wager-locked '
        'elsewhere', () async {
      final g = makePrivateWagerLobby();
      g.guard.locked.add('fb-p1'); // as if locked by another session
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);
      g.p1ws.clear();

      await g.session.startGameFromHost(g.p1Id);

      expect(g.p1ws.lastOfType('error')?['code'], 'wager_locked');
      expect(g.p1ws.lastOfType('session_config'), isNull);
      expect(g.wallet.chargeCalls, isEmpty);
    });

    test('accepted + funded pot wager charges every participant and starts',
        () async {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);

      await g.session.startGameFromHost(g.p1Id);

      expect(g.p1ws.lastOfType('session_config'), isNotNull);
      expect(
        g.wallet.chargeCalls.toSet(),
        {(uid: 'fb-p1', amount: 20), (uid: 'fb-p2', amount: 20)},
      );
      expect(g.guard.locked, {'fb-p1', 'fb-p2'});
      expect(g.session.wagerState.lockedPlayerIds, {g.p1Id, g.p2Id});
    });

    test('pot wager pays the match winner the full pot and refunds the '
        'loser\'s nothing back', () async {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);
      await g.session.startGameFromHost(g.p1Id);

      // Override the randomly-dealt hand with a deterministic one-card win
      // for p1 — seedStateForTesting only touches _state/_drawPile/etc, so
      // the wager lock-in state from startGameFromHost above is untouched.
      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: g.p1Id,
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: [winCard],
            cardCount: 1,
          ),
          PlayerModel(
            id: g.p2Id,
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: [_card(Rank.three, Suit.hearts)],
            cardCount: 1,
          ),
        ],
        currentPlayerId: g.p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      g.session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      g.p1ws.clear();
      g.p2ws.clear();

      g.session.handleAction(g.p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = g.p1ws.lastOfType('wager_settled');
      expect(settled, isNotNull);
      expect(settled!['mode'], 'pot');
      expect(settled['potTotal'], 40);
      expect(settled['winnerPlayerId'], g.p1Id);
      expect(settled['perPlayerDelta'], {g.p1Id: 20, g.p2Id: -20});

      expect(g.wallet.payoutCalls, [(uid: 'fb-p1', amount: 40)]);
      expect(g.wallet.refundCalls, isEmpty);
      expect(g.wallet.balances['fb-p1'], 120); // 100 -20 charged +40 payout
      expect(g.wallet.balances['fb-p2'], 80); // 100 -20 charged, never refunded

      expect(g.guard.locked, isEmpty,
          reason: 'settlement must release the cross-session lock');
      expect(g.session.wagerState.config, isNull,
          reason: 'settlement must reset for a possible next match');
    });

    test('side-bet settles by remaining hand size, independent of the '
        'overall match winner', () async {
      final wallet = _FakeWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100
        ..balances['fb-p3'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: true,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p3ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      final p3Id = session.addPlayer(p3ws, 'P3', firebaseUid: 'fb-p3');

      // p2 challenges p3 to a side-bet; p3 must accept (p1/host is uninvolved).
      session.setWagerConfig(p2Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p3Id);
      session.acceptWager(p3Id);
      await session.startGameFromHost(p1Id);

      // p1 wins the overall match (empty hand); side-bet is p2 (2 cards) vs
      // p3 (4 cards) — p2 should win the side-bet despite not winning outright.
      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: p1Id,
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [winCard],
              cardCount: 1),
          PlayerModel(
              id: p2Id,
              displayName: 'P2',
              tablePosition: TablePosition.left,
              hand: [
                _card(Rank.three, Suit.hearts),
                _card(Rank.four, Suit.hearts)
              ],
              cardCount: 2),
          PlayerModel(
              id: p3Id,
              displayName: 'P3',
              tablePosition: TablePosition.right,
              hand: [
                _card(Rank.three, Suit.diamonds),
                _card(Rank.four, Suit.diamonds),
                _card(Rank.six, Suit.diamonds),
                _card(Rank.eight, Suit.diamonds),
              ],
              cardCount: 4),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = p1ws.lastOfType('wager_settled');
      expect(settled?['mode'], 'sideBet');
      expect(settled?['potTotal'], 20);
      expect(settled?['winnerPlayerId'], p2Id);
      expect(settled?['perPlayerDelta'], {p2Id: 10, p3Id: -10});
      expect(wallet.payoutCalls, [(uid: 'fb-p2', amount: 20)]);
    });

    test('side-bet tie refunds both participants as a push', () async {
      final wallet = _FakeWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100
        ..balances['fb-p3'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: true,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p3ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      final p3Id = session.addPlayer(p3ws, 'P3', firebaseUid: 'fb-p3');

      session.setWagerConfig(p2Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p3Id);
      session.acceptWager(p3Id);
      await session.startGameFromHost(p1Id);

      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: p1Id,
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [winCard],
              cardCount: 1),
          PlayerModel(
              id: p2Id,
              displayName: 'P2',
              tablePosition: TablePosition.left,
              hand: [_card(Rank.three, Suit.hearts)],
              cardCount: 1),
          PlayerModel(
              id: p3Id,
              displayName: 'P3',
              tablePosition: TablePosition.right,
              hand: [_card(Rank.three, Suit.diamonds)],
              cardCount: 1),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      p1ws.clear();

      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = p1ws.lastOfType('wager_settled');
      expect(settled?['winnerPlayerId'], isNull);
      expect(settled?['perPlayerDelta'], {p2Id: 0, p3Id: 0});
      expect(wallet.payoutCalls, isEmpty);
      expect(wallet.refundCalls.toSet(),
          {(uid: 'fb-p2', amount: 10), (uid: 'fb-p3', amount: 10)});
      expect(wallet.balances['fb-p2'], 100);
      expect(wallet.balances['fb-p3'], 100);
    });

    test(
        'a single mid-game disconnect does NOT refund — the seat goes AI '
        'and the wager rides through to a normal settlement', () async {
      // Mid-game human disconnects take silent, permanent AI control of the
      // seat rather than ending the match (see
      // GameSession._beginAiControlForDisconnectedHuman) — a wager stays
      // live and settles normally through _checkWin, not through a refund.
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);
      await g.session.startGameFromHost(g.p1Id);
      expect(g.wallet.chargeCalls, hasLength(2));

      g.session.handleSocketDisconnected(g.p2Id, g.p2ws, forceRemove: true);

      expect(g.wallet.refundCalls, isEmpty);
      expect(g.session.wagerState.config, isNotNull,
          reason: 'wager stays active — the match has not ended');
      expect(g.guard.locked, {'fb-p1', 'fb-p2'});
    });

    test(
        'the match being abandoned (every human socket gone) refunds every '
        'locked participant, never pays out', () async {
      final g = makePrivateWagerLobby();
      g.session.setWagerConfig(g.p1Id, mode: 'pot', stakeCoins: 20);
      g.session.acceptWager(g.p2Id);
      await g.session.startGameFromHost(g.p1Id);
      expect(g.wallet.chargeCalls, hasLength(2));

      g.session.handleSocketDisconnected(g.p1Id, g.p1ws);
      expect(g.wallet.refundCalls, isEmpty,
          reason: 'one human still connected — match continues under AI');

      g.session.handleSocketDisconnected(g.p2Id, g.p2ws);

      expect(g.session.isEmpty, isTrue);
      expect(g.wallet.payoutCalls, isEmpty);
      expect(g.wallet.refundCalls.toSet(),
          {(uid: 'fb-p1', amount: 20), (uid: 'fb-p2', amount: 20)});
      expect(g.wallet.balances['fb-p1'], 100);
      expect(g.wallet.balances['fb-p2'], 100);
      expect(g.guard.locked, isEmpty);
    });

    test('the cross-session guard blocks a second room from locking a uid '
        'already wagering elsewhere', () async {
      final sharedGuard = _FakeWagerLockGuard();

      final walletA = _FakeWalletPersistence()
        ..balances['fb-shared'] = 100
        ..balances['fb-a2'] = 100;
      final sessionA = GameSession(
        'ROOM_A',
        isPrivate: true,
        walletService: walletA,
        tryLockWagerUids: sharedGuard.tryLock,
        releaseWagerUids: sharedGuard.release,
      );
      final aw1 = _FakeWs();
      final aw2 = _FakeWs();
      final a1 = sessionA.addPlayer(aw1, 'A1', firebaseUid: 'fb-shared');
      final a2 = sessionA.addPlayer(aw2, 'A2', firebaseUid: 'fb-a2');
      sessionA.setWagerConfig(a1, mode: 'pot', stakeCoins: 10);
      sessionA.acceptWager(a2);
      await sessionA.startGameFromHost(a1);
      expect(sharedGuard.locked, {'fb-shared', 'fb-a2'});

      final walletB = _FakeWalletPersistence()
        ..balances['fb-shared'] = 100
        ..balances['fb-b2'] = 100;
      final sessionB = GameSession(
        'ROOM_B',
        isPrivate: true,
        walletService: walletB,
        tryLockWagerUids: sharedGuard.tryLock,
        releaseWagerUids: sharedGuard.release,
      );
      final bw1 = _FakeWs();
      final bw2 = _FakeWs();
      final b1 = sessionB.addPlayer(bw1, 'B1', firebaseUid: 'fb-shared');
      final b2 = sessionB.addPlayer(bw2, 'B2', firebaseUid: 'fb-b2');
      sessionB.setWagerConfig(b1, mode: 'pot', stakeCoins: 10);
      sessionB.acceptWager(b2);
      bw1.clear();

      await sessionB.startGameFromHost(b1);

      expect(bw1.lastOfType('error')?['code'], 'wager_locked');
      expect(bw1.lastOfType('session_config'), isNull);
      expect(walletB.chargeCalls, isEmpty);
    });
  });

  group('mid-game side-bet', () {
    ({
      GameSession session,
      _FakeWs p1ws,
      _FakeWs p2ws,
      String p1Id,
      String p2Id,
      _FakeWalletPersistence wallet,
      _FakeWagerLockGuard guard,
    }) makeQuickplayWagerMatch({int p1Balance = 100, int p2Balance = 100}) {
      final wallet = _FakeWalletPersistence();
      final guard = _FakeWagerLockGuard();
      wallet.balances['fb-p1'] = p1Balance;
      wallet.balances['fb-p2'] = p2Balance;
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 2,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      // Mirrors how RoomManager._startMatch auto-readies every seat the
      // instant a quickplay queue bucket fills — no lobby, no host.
      session.markReady(p1Id);
      session.markReady(p2Id);
      return (
        session: session,
        p1ws: p1ws,
        p2ws: p2ws,
        p1Id: p1Id,
        p2Id: p2Id,
        wallet: wallet,
        guard: guard,
      );
    }

    test('ranked matches reject a mid-game side-bet proposal', () {
      final wallet = _FakeWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100;
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isRanked: true,
        maxPlayerCount: 2,
        walletService: wallet,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      session.markReady(p1Id);
      session.markReady(p2Id);
      p1ws.clear();

      session.setWagerConfig(p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p2Id);

      expect(p1ws.lastOfType('error')?['code'], 'wager_unsupported');
      expect(session.wagerState.config, isNull);
    });

    test(
        'quickplay mid-game: propose, accept, charge, and settle by '
        'remaining hand size — independent of when the bet was placed',
        () async {
      final g = makeQuickplayWagerMatch();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      g.session.acceptWager(g.p2Id);
      await g.session.wagerLockInFlightFuture;

      expect(
        g.wallet.chargeCalls.toSet(),
        {(uid: 'fb-p1', amount: 10), (uid: 'fb-p2', amount: 10)},
      );
      expect(g.guard.locked, {'fb-p1', 'fb-p2'});
      expect(g.session.wagerState.lockedPlayerIds, {g.p1Id, g.p2Id});

      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: g.p1Id,
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [winCard],
              cardCount: 1),
          PlayerModel(
              id: g.p2Id,
              displayName: 'P2',
              tablePosition: TablePosition.top,
              hand: [_card(Rank.three, Suit.hearts)],
              cardCount: 1),
        ],
        currentPlayerId: g.p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      g.session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      g.p1ws.clear();

      g.session.handleAction(g.p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = g.p1ws.lastOfType('wager_settled');
      expect(settled?['mode'], 'sideBet');
      expect(settled?['winnerPlayerId'], g.p1Id);
      expect(settled?['perPlayerDelta'], {g.p1Id: 10, g.p2Id: -10});
      expect(g.wallet.payoutCalls, [(uid: 'fb-p1', amount: 20)]);
      expect(g.guard.locked, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test('mid-game accept with insufficient balance drops the config cleanly',
        () async {
      final g = makeQuickplayWagerMatch(p2Balance: 5);
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      g.p2ws.clear();

      g.session.acceptWager(g.p2Id);
      await g.session.wagerLockInFlightFuture;

      expect(g.p2ws.lastOfType('error')?['code'], 'insufficient_coins');
      expect(g.wallet.chargeCalls, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test(
        'mid-game accept when the uid is already locked elsewhere drops the '
        'config cleanly', () async {
      final g = makeQuickplayWagerMatch();
      g.guard.locked.add('fb-p1');
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      g.p1ws.clear();

      g.session.acceptWager(g.p2Id);
      await g.session.wagerLockInFlightFuture;

      expect(g.p1ws.lastOfType('error')?['code'], 'wager_locked');
      expect(g.wallet.chargeCalls, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test('mid-game target decline clears the config and unblocks a new '
        'proposal', () {
      final g = makeQuickplayWagerMatch();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);

      g.session.declineWager(g.p2Id);

      expect(g.session.wagerState.config, isNull);
      expect(g.p1ws.lastOfType('wager_state')?['mode'], isNull);

      g.session.setWagerConfig(g.p2Id,
          mode: 'sideBet', stakeCoins: 5, targetPlayerId: g.p1Id);
      expect(g.session.wagerState.config, isNotNull);
      expect(g.session.wagerState.config!.stakeCoins, 5);
    });

    test('a decline arriving during the balance-check await prevents the '
        'charge', () async {
      final wallet = _ControllableWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 2,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      session.markReady(p1Id);
      session.markReady(p2Id);

      session.setWagerConfig(p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p2Id);
      wallet.armGate();
      session.acceptWager(p2Id);
      final pending = session.wagerLockInFlightFuture;
      expect(pending, isNotNull);

      // The target changes their mind while the balance check is suspended.
      session.declineWager(p2Id);
      expect(session.wagerState.config, isNull);

      wallet.releaseGate();
      await pending;

      expect(wallet.chargeCalls, isEmpty);
      expect(guard.locked, isEmpty);
      expect(session.wagerState.config, isNull);
    });

    test(
        'the match ending during the balance-check await prevents the '
        'charge', () async {
      final wallet = _ControllableWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 2,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      session.markReady(p1Id);
      session.markReady(p2Id);

      session.setWagerConfig(p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p2Id);
      wallet.armGate();
      session.acceptWager(p2Id);
      final pending = session.wagerLockInFlightFuture;

      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: p1Id,
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [winCard],
              cardCount: 1),
          PlayerModel(
              id: p2Id,
              displayName: 'P2',
              tablePosition: TablePosition.top,
              hand: [_card(Rank.three, Suit.hearts)],
              cardCount: 1),
        ],
        currentPlayerId: p1Id,
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      session.handleAction(p1Id, {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      wallet.releaseGate();
      await pending;

      expect(wallet.chargeCalls, isEmpty);
      expect(wallet.payoutCalls, isEmpty);
      expect(guard.locked, isEmpty);
    });

    test('a new proposal is rejected outright while one is already locked in',
        () async {
      final g = makeQuickplayWagerMatch();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      g.session.acceptWager(g.p2Id);
      await g.session.wagerLockInFlightFuture;
      expect(g.session.wagerState.lockedPlayerIds, isNotEmpty);

      g.p1ws.clear();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 5, targetPlayerId: g.p2Id);

      expect(g.p1ws.lastOfType('error')?['code'], 'wager_in_progress');
      expect(g.session.wagerState.config!.stakeCoins, 10);
    });

    test('challenging an already-disconnected (AI-driven) seat is rejected',
        () {
      final g = makeQuickplayWagerMatch();
      g.session.handleSocketDisconnected(g.p2Id, g.p2ws);
      expect(g.session.isControlledByAiForTesting(g.p2Id), isTrue);

      g.p1ws.clear();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);

      expect(g.p1ws.lastOfType('error')?['code'], 'invalid_wager');
      expect(g.session.wagerState.config, isNull);
    });

    test(
        'the target disconnecting while a proposal is pending-unlocked '
        'auto-clears it', () {
      final g = makeQuickplayWagerMatch();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      expect(g.session.wagerState.config, isNotNull);

      g.session.handleSocketDisconnected(g.p2Id, g.p2ws);

      expect(g.session.wagerState.config, isNull);
    });

    test('an unanswered mid-game proposal expires after the timeout', () {
      fakeAsync((async) {
        final g = makeQuickplayWagerMatch();
        g.session.setWagerConfig(g.p1Id,
            mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
        expect(g.session.wagerState.config, isNotNull);

        async.elapse(
            GameSession.midGameWagerProposalTimeout + const Duration(seconds: 1));

        expect(g.session.wagerState.config, isNull);
      });
    });

    test(
        "a decline from a non-participant does not clear someone else's "
        'side-bet', () {
      final wallet = _FakeWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100
        ..balances['fb-p3'] = 100;
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 3,
        walletService: wallet,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p3ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      final p3Id = session.addPlayer(p3ws, 'P3', firebaseUid: 'fb-p3');
      session.markReady(p1Id);
      session.markReady(p2Id);
      session.markReady(p3Id);

      session.setWagerConfig(p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: p2Id);
      session.declineWager(p3Id);

      expect(session.wagerState.config, isNotNull);
      expect(session.wagerState.acceptStatus[p3Id], isNull);
    });

    test(
        'quickplay match abandoned mid-wager (every human socket gone) '
        'refunds both, never pays out', () async {
      final g = makeQuickplayWagerMatch();
      g.session.setWagerConfig(g.p1Id,
          mode: 'sideBet', stakeCoins: 10, targetPlayerId: g.p2Id);
      g.session.acceptWager(g.p2Id);
      await g.session.wagerLockInFlightFuture;
      expect(g.wallet.chargeCalls, hasLength(2));

      g.session.handleSocketDisconnected(g.p1Id, g.p1ws);
      g.session.handleSocketDisconnected(g.p2Id, g.p2ws);

      expect(g.session.isEmpty, isTrue);
      expect(g.wallet.payoutCalls, isEmpty);
      expect(
        g.wallet.refundCalls.toSet(),
        {(uid: 'fb-p1', amount: 10), (uid: 'fb-p2', amount: 10)},
      );
      expect(g.wallet.balances['fb-p1'], 100);
      expect(g.wallet.balances['fb-p2'], 100);
      expect(g.guard.locked, isEmpty);
    });
  });

  group('mid-game table-pot wager', () {
    ({
      GameSession session,
      List<_FakeWs> ws,
      List<String> ids,
      _FakeWalletPersistence wallet,
      _FakeWagerLockGuard guard,
    }) makeQuickplayTablePotMatch({int playerCount = 3, int balance = 100}) {
      final wallet = _FakeWalletPersistence();
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: playerCount,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final wsList = <_FakeWs>[];
      final idList = <String>[];
      for (var i = 0; i < playerCount; i++) {
        final w = _FakeWs();
        final id = session.addPlayer(w, 'P${i + 1}', firebaseUid: 'fb-p${i + 1}');
        wallet.balances['fb-p${i + 1}'] = balance;
        wsList.add(w);
        idList.add(id);
      }
      for (final id in idList) {
        session.markReady(id);
      }
      return (
        session: session,
        ws: wsList,
        ids: idList,
        wallet: wallet,
        guard: guard,
      );
    }

    test('ranked matches reject a table-pot proposal', () {
      final wallet = _FakeWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100;
      final session = GameSession(
        'TEST',
        isPrivate: false,
        isRanked: true,
        maxPlayerCount: 2,
        walletService: wallet,
      );
      final p1ws = _FakeWs();
      final p2ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      final p2Id = session.addPlayer(p2ws, 'P2', firebaseUid: 'fb-p2');
      session.markReady(p1Id);
      session.markReady(p2Id);
      p1ws.clear();

      session.setWagerConfig(p1Id, mode: 'tablePot', stakeCoins: 10);

      expect(p1ws.lastOfType('error')?['code'], 'wager_unsupported');
      expect(session.wagerState.config, isNull);
    });

    test('a table-pot proposal before the match starts is rejected', () {
      final wallet = _FakeWalletPersistence()..balances['fb-p1'] = 100;
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 2,
        walletService: wallet,
      );
      final p1ws = _FakeWs();
      final p1Id = session.addPlayer(p1ws, 'P1', firebaseUid: 'fb-p1');
      p1ws.clear();

      session.setWagerConfig(p1Id, mode: 'tablePot', stakeCoins: 10);

      expect(p1ws.lastOfType('error')?['code'], 'wager_unsupported');
      expect(session.wagerState.config, isNull);
    });

    test(
        'propose, join from two other seats, start, charge, and settle '
        'winner-take-all to the match winner', () async {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.acceptWager(g.ids[2]);
      expect(g.session.wagerState.lockedPlayerIds, isEmpty);

      g.session.startWager(g.ids[0]);
      await g.session.wagerLockInFlightFuture;

      expect(
        g.wallet.chargeCalls.toSet(),
        {
          (uid: 'fb-p1', amount: 10),
          (uid: 'fb-p2', amount: 10),
          (uid: 'fb-p3', amount: 10),
        },
      );
      expect(g.guard.locked, {'fb-p1', 'fb-p2', 'fb-p3'});
      expect(g.session.wagerState.lockedPlayerIds,
          {g.ids[0], g.ids[1], g.ids[2]});

      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: g.ids[0],
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [winCard],
              cardCount: 1),
          PlayerModel(
              id: g.ids[1],
              displayName: 'P2',
              tablePosition: TablePosition.left,
              hand: [_card(Rank.three, Suit.hearts)],
              cardCount: 1),
          PlayerModel(
              id: g.ids[2],
              displayName: 'P3',
              tablePosition: TablePosition.right,
              hand: [_card(Rank.four, Suit.clubs)],
              cardCount: 1),
        ],
        currentPlayerId: g.ids[0],
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      g.session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      g.ws[0].clear();

      g.session.handleAction(g.ids[0], {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = g.ws[0].lastOfType('wager_settled');
      expect(settled?['mode'], 'tablePot');
      expect(settled?['winnerPlayerId'], g.ids[0]);
      expect(settled?['perPlayerDelta'],
          {g.ids[0]: 20, g.ids[1]: -10, g.ids[2]: -10});
      expect(g.wallet.payoutCalls, [(uid: 'fb-p1', amount: 30)]);
      expect(g.guard.locked, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test('starting with zero joiners is rejected', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.ws[0].clear();

      g.session.startWager(g.ids[0]);

      expect(g.ws[0].lastOfType('error')?['code'], 'wager_not_accepted');
      expect(g.session.wagerState.lockedPlayerIds, isEmpty);
    });

    test('only the initiator can start the wager', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.ws[1].clear();

      g.session.startWager(g.ids[1]);

      expect(g.ws[1].lastOfType('error')?['code'], 'invalid_wager');
      expect(g.session.wagerState.lockedPlayerIds, isEmpty);
    });

    test('a joiner can leave and rejoin before Start without affecting '
        'others', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.acceptWager(g.ids[2]);

      g.session.declineWager(g.ids[1]);
      expect(g.session.wagerState.config, isNotNull);
      expect(
        g.session.wagerState.participantPlayerIds(g.ids.toSet()),
        {g.ids[0], g.ids[2]},
      );

      g.session.acceptWager(g.ids[1]);
      expect(
        g.session.wagerState.participantPlayerIds(g.ids.toSet()),
        {g.ids[0], g.ids[1], g.ids[2]},
      );
    });

    test(
        'a join arriving mid-lock-in (during the balance-check await) is '
        'excluded from lockedPlayerIds and never charged', () async {
      final wallet = _ControllableWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100
        ..balances['fb-p3'] = 100
        ..balances['fb-p4'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 4,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final wsList = <_FakeWs>[];
      final idList = <String>[];
      for (var i = 0; i < 4; i++) {
        final w = _FakeWs();
        final id = session.addPlayer(w, 'P${i + 1}', firebaseUid: 'fb-p${i + 1}');
        wsList.add(w);
        idList.add(id);
      }
      for (final id in idList) {
        session.markReady(id);
      }

      session.setWagerConfig(idList[0], mode: 'tablePot', stakeCoins: 10);
      session.acceptWager(idList[1]);
      wallet.armGate();
      session.startWager(idList[0]);
      final pending = session.wagerLockInFlightFuture;
      expect(pending, isNotNull);

      // A fourth player joins mid-flight, after the participant set has
      // already been captured for this lock-in attempt.
      session.acceptWager(idList[2]);

      wallet.releaseGate();
      await pending;

      expect(session.wagerState.lockedPlayerIds, {idList[0], idList[1]});
      expect(
        wallet.chargeCalls.toSet(),
        {(uid: 'fb-p1', amount: 10), (uid: 'fb-p2', amount: 10)},
      );
      expect(wallet.chargeCalls.any((c) => c.uid == 'fb-p3'), isFalse);
    });

    test('a joiner disconnecting before Start is silently dropped, '
        'proposal survives for the rest', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.acceptWager(g.ids[2]);

      g.session.handleSocketDisconnected(g.ids[1], g.ws[1]);

      expect(g.session.wagerState.config, isNotNull);
      expect(
        g.session.wagerState.participantPlayerIds(g.ids.toSet()),
        {g.ids[0], g.ids[2]},
      );
    });

    test('the initiator disconnecting before Start clears the whole '
        'proposal', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);

      g.session.handleSocketDisconnected(g.ids[0], g.ws[0]);

      expect(g.session.wagerState.config, isNull);
    });

    test('the initiator disconnecting mid-lock-in aborts the charge for '
        'everyone', () async {
      final wallet = _ControllableWalletPersistence()
        ..balances['fb-p1'] = 100
        ..balances['fb-p2'] = 100
        ..balances['fb-p3'] = 100;
      final guard = _FakeWagerLockGuard();
      final session = GameSession(
        'TEST',
        isPrivate: false,
        maxPlayerCount: 3,
        walletService: wallet,
        tryLockWagerUids: guard.tryLock,
        releaseWagerUids: guard.release,
      );
      final wsList = <_FakeWs>[];
      final idList = <String>[];
      for (var i = 0; i < 3; i++) {
        final w = _FakeWs();
        final id = session.addPlayer(w, 'P${i + 1}', firebaseUid: 'fb-p${i + 1}');
        wsList.add(w);
        idList.add(id);
      }
      for (final id in idList) {
        session.markReady(id);
      }

      session.setWagerConfig(idList[0], mode: 'tablePot', stakeCoins: 10);
      session.acceptWager(idList[1]);
      session.acceptWager(idList[2]);
      wallet.armGate();
      session.startWager(idList[0]);
      final pending = session.wagerLockInFlightFuture;

      session.handleSocketDisconnected(idList[0], wsList[0]);
      expect(session.wagerState.config, isNull);

      wallet.releaseGate();
      await pending;

      expect(wallet.chargeCalls, isEmpty);
      expect(guard.locked, isEmpty);
    });

    test('insufficient balance on any one joiner drops the whole config '
        'and charges nobody', () async {
      final g = makeQuickplayTablePotMatch(balance: 100);
      g.wallet.balances['fb-p3'] = 2;
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.acceptWager(g.ids[2]);
      g.ws[2].clear();

      g.session.startWager(g.ids[0]);
      await g.session.wagerLockInFlightFuture;

      expect(g.ws[2].lastOfType('error')?['code'], 'insufficient_coins');
      expect(g.wallet.chargeCalls, isEmpty);
      expect(g.session.wagerState.config, isNull);
    });

    test('the match winner not among the joiners refunds everyone',
        () async {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.startWager(g.ids[0]);
      await g.session.wagerLockInFlightFuture;
      expect(g.wallet.chargeCalls, hasLength(2));

      final winCard = _card(Rank.five, Suit.spades);
      final state = GameState(
        sessionId: 'TEST',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
              id: g.ids[0],
              displayName: 'P1',
              tablePosition: TablePosition.bottom,
              hand: [_card(Rank.three, Suit.hearts)],
              cardCount: 1),
          PlayerModel(
              id: g.ids[1],
              displayName: 'P2',
              tablePosition: TablePosition.left,
              hand: [_card(Rank.four, Suit.clubs)],
              cardCount: 1),
          PlayerModel(
              id: g.ids[2],
              displayName: 'P3',
              tablePosition: TablePosition.right,
              hand: [winCard],
              cardCount: 1),
        ],
        currentPlayerId: g.ids[2],
        direction: PlayDirection.clockwise,
        discardTopCard: _card(Rank.five, Suit.hearts),
        drawPileCount: 5,
        preTurnCentreSuit: Suit.hearts,
      );
      g.session.seedStateForTesting(
        state: state,
        drawPile: List.generate(5,
            (i) => CardModel(id: 'filler_$i', rank: Rank.seven, suit: Suit.clubs)),
      );
      g.ws[2].clear();

      // P3 (not a wager participant) wins the match.
      g.session.handleAction(g.ids[2], {
        'type': 'play_cards',
        'cardIds': ['five_spades'],
      });

      final settled = g.ws[2].lastOfType('wager_settled');
      expect(settled?['winnerPlayerId'], isNull);
      expect(settled?['perPlayerDelta'], {g.ids[0]: 0, g.ids[1]: 0});
      expect(g.wallet.payoutCalls, isEmpty);
      expect(
        g.wallet.refundCalls.toSet(),
        {(uid: 'fb-p1', amount: 10), (uid: 'fb-p2', amount: 10)},
      );
    });

    test('a new proposal is rejected outright while a table-pot is already '
        'locked in', () async {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.session.startWager(g.ids[0]);
      await g.session.wagerLockInFlightFuture;
      g.ws[2].clear();

      g.session.setWagerConfig(g.ids[2], mode: 'tablePot', stakeCoins: 5);

      expect(g.ws[2].lastOfType('error')?['code'], 'wager_in_progress');
      expect(g.session.wagerState.lockedPlayerIds, {g.ids[0], g.ids[1]});
    });

    test('no proposal-expiry timer fires for an unanswered table-pot '
        'proposal', () {
      fakeAsync((async) {
        final g = makeQuickplayTablePotMatch();
        g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);

        async.elapse(GameSession.midGameWagerProposalTimeout +
            const Duration(seconds: 30));

        expect(g.session.wagerState.config, isNotNull);
      });
    });

    test('withdrawing before anyone joins clears cleanly', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);

      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 0);

      expect(g.session.wagerState.config, isNull);
    });

    test('withdrawing after joins clears and no one is charged', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);

      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 0);

      expect(g.session.wagerState.config, isNull);
      expect(g.wallet.chargeCalls, isEmpty);
    });

    test('a non-initiator cannot withdraw a table-pot proposal', () {
      final g = makeQuickplayTablePotMatch();
      g.session.setWagerConfig(g.ids[0], mode: 'tablePot', stakeCoins: 10);
      g.session.acceptWager(g.ids[1]);
      g.ws[1].clear();

      g.session.setWagerConfig(g.ids[1], mode: 'tablePot', stakeCoins: 0);

      expect(g.ws[1].lastOfType('error')?['code'], 'invalid_wager');
      expect(g.session.wagerState.config, isNotNull);
    });
  });
}
