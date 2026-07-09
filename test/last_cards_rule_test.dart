import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/engine/game_engine.dart';
import 'package:last_cards/shared/rules/last_cards_rules.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart'
    show needsUndeclaredLastCardsDraw;

CardModel c(Rank rank, Suit suit) =>
    CardModel(id: '${rank.name}_${suit.name}', rank: rank, suit: suit);

GameState stateForP1(List<CardModel> hand, {required CardModel discardTop}) {
  return GameState(
    sessionId: 't',
    phase: GamePhase.playing,
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    drawPileCount: 10,
    players: [
      PlayerModel(
        id: 'p1',
        displayName: 'P1',
        tablePosition: TablePosition.bottom,
        hand: hand,
        cardCount: hand.length,
      ),
      PlayerModel(
        id: 'p2',
        displayName: 'P2',
        tablePosition: TablePosition.top,
        hand: const [],
        cardCount: 0,
      ),
    ],
  );
}

void main() {
  group('canHandClearInOneTurnHandOnly', () {
    test('Joker in hand can chain with adjacent card', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.joker, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('single non-Queen is fine', () {
      expect(canHandClearInOneTurnHandOnly([c(Rank.five, Suit.hearts)]), isTrue);
    });

    test('single Queen fails', () {
      expect(canHandClearInOneTurnHandOnly([c(Rank.queen, Suit.spades)]), isFalse);
    });

    test('sequence + value chain', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('gap with no joker fails', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
    });

    test('Queen covered then play', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.five, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test('two Queens ending on Queen fails', () {
      final hand = [
        c(Rank.queen, Suit.spades),
        c(Rank.queen, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
    });

    test('unrelated pairs fail', () {
      expect(
        canHandClearInOneTurnHandOnly([
          c(Rank.three, Suit.hearts),
          c(Rank.seven, Suit.diamonds),
        ]),
        isFalse,
      );
    });

    test('penalty chain 2–2–J', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.two, Suit.clubs),
        c(Rank.jack, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isTrue);
    });

    test(
        'regression: a Queen mid-chain does NOT unconditionally accept any '
        'next card — it must still match by suit/rank like a real card', () {
      // Old bug: `_validChainStep` treated *any* card following a Queen as
      // legal ("next.effectiveRank == Rank.queen" returned true
      // unconditionally), which let a Queen act as a free bridge between two
      // otherwise-unconnected cards. 10♠ can open on a 10♦ discard (rank
      // match), but clubs Q♣/3♣ share no suit or rank with 10♠ — this hand
      // should NOT be clearable.
      final hand = [
        c(Rank.ten, Suit.spades),
        c(Rank.queen, Suit.clubs),
        c(Rank.three, Suit.clubs),
      ];
      expect(
        canHandClearInOneTurnHandOnly(hand, discardTop: c(Rank.ten, Suit.diamonds)),
        isFalse,
      );
    });

    test(
        'regression: a Joker mid-chain does NOT bridge to an unrelated card — '
        "it can only continue as something it could actually declare", () {
      // Old bug: `_validChainStep` treated a Joker on either side of a step
      // as an unconditional pass ("prev.isJoker || next.isJoker" returned
      // true), letting it bridge between two hand "islands" that share no
      // suit/rank with each other. 3♣ can open on a 3♦ discard (rank match),
      // but nothing the Joker could legally declare after 3♣ connects to 7♥.
      final hand = [
        c(Rank.three, Suit.clubs),
        c(Rank.joker, Suit.spades),
        c(Rank.seven, Suit.hearts),
      ];
      expect(
        canHandClearInOneTurnHandOnly(hand, discardTop: c(Rank.three, Suit.diamonds)),
        isFalse,
      );
    });
  });

  group('canClearHandInOneTurn (engine)', () {
    test(
        '2p King repeat turn: K♥ then 4♥ clears on 6♥ or 9♥ pile though hand-only is false',
        () {
      final hand = [
        c(Rank.king, Suit.hearts),
        c(Rank.four, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final onSix = stateForP1(hand, discardTop: c(Rank.six, Suit.hearts));
      expect(canClearHandInOneTurn(state: onSix, playerId: 'p1'), isTrue);

      final onNine = stateForP1(hand, discardTop: c(Rank.nine, Suit.hearts));
      expect(canClearHandInOneTurn(state: onNine, playerId: 'p1'), isTrue);
    });

    test(
        '2p Eight skip repeat turn: 8♥ then 4♥ clears on 6♥ or 9♥ pile though hand-only is false',
        () {
      final hand = [
        c(Rank.eight, Suit.hearts),
        c(Rank.four, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final onSix = stateForP1(hand, discardTop: c(Rank.six, Suit.hearts));
      expect(canClearHandInOneTurn(state: onSix, playerId: 'p1'), isTrue);

      final onNine = stateForP1(hand, discardTop: c(Rank.nine, Suit.hearts));
      expect(canClearHandInOneTurn(state: onNine, playerId: 'p1'), isTrue);
    });

    test(
        '3 players: multiple actions in one turn (e.g. pair then 6♠) even when '
        'nextPlayerId would be another seat',
        () {
      final hand = [
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.spades),
        c(Rank.six, Suit.spades),
      ];
      final state = GameState(
        sessionId: 't',
        phase: GamePhase.playing,
        currentPlayerId: 'p1',
        direction: PlayDirection.clockwise,
        discardTopCard: c(Rank.five, Suit.hearts),
        drawPileCount: 10,
        players: [
          PlayerModel(
            id: 'p1',
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: hand,
            cardCount: hand.length,
          ),
          PlayerModel(
            id: 'p2',
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p3',
            displayName: 'P3',
            tablePosition: TablePosition.left,
            hand: const [],
            cardCount: 0,
          ),
        ],
      );
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test(
        '5 players: four 8s in one play + 5♥ clears via skip wrap (hand-only false)',
        () {
      final hand = [
        c(Rank.eight, Suit.hearts),
        c(Rank.eight, Suit.diamonds),
        c(Rank.eight, Suit.clubs),
        c(Rank.eight, Suit.spades),
        c(Rank.five, Suit.hearts),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);

      final state = GameState(
        sessionId: 't',
        phase: GamePhase.playing,
        currentPlayerId: 'p1',
        direction: PlayDirection.clockwise,
        discardTopCard: c(Rank.eight, Suit.hearts),
        drawPileCount: 10,
        players: [
          PlayerModel(
            id: 'p1',
            displayName: 'P1',
            tablePosition: TablePosition.bottom,
            hand: hand,
            cardCount: hand.length,
          ),
          PlayerModel(
            id: 'p2',
            displayName: 'P2',
            tablePosition: TablePosition.top,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p3',
            displayName: 'P3',
            tablePosition: TablePosition.left,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p4',
            displayName: 'P4',
            tablePosition: TablePosition.right,
            hand: const [],
            cardCount: 0,
          ),
          PlayerModel(
            id: 'p5',
            displayName: 'P5',
            tablePosition: TablePosition.bottomLeft,
            hand: const [],
            cardCount: 0,
          ),
        ],
      );
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test(
        'sequence then value chain: NOT clearable when no card in hand can '
        'legally open against the discard top', () {
      // Regression for the "declared Last Cards" bug: a hand that only
      // chains among *itself* isn't actually clearable if nothing in it can
      // legally be the first card played. 3♥/4♥/5♥/5♣ vs K♠ shares no suit
      // or rank with any card in hand — there is no legal opener at all.
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      final mismatchTop = c(Rank.king, Suit.spades);
      final state = stateForP1(hand, discardTop: mismatchTop);
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
    });

    test('sequence then value chain: clearable once the discard top allows a legal opener', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      // King of hearts matches the hand's suit — 3♥ (or any ♥ card) can open.
      final matchingTop = c(Rank.king, Suit.hearts);
      final state = stateForP1(hand, discardTop: matchingTop);
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test(
        'Joker + failing hand-only chain: engine not clearable; human bluff uses Joker exemption at call site',
        () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.four, Suit.diamonds),
        c(Rank.six, Suit.clubs),
        c(Rank.eight, Suit.spades),
        c(Rank.joker, Suit.spades),
      ];
      expect(canHandClearInOneTurnHandOnly(hand), isFalse);
      final state = stateForP1(hand, discardTop: c(Rank.king, Suit.clubs));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
      final hasJoker = hand.any((c) => c.isJoker);
      final bluff = !hasJoker &&
          !canClearHandInOneTurn(state: state, playerId: 'p1');
      expect(bluff, isFalse);
    });

    test('non-Joker chain [2♥,3♥,4♥,4♠] NOT clearable when the discard top matches nothing in hand', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.four, Suit.spades),
      ];
      // Ace of diamonds shares no suit/rank with any card in this hand.
      final state = stateForP1(hand, discardTop: c(Rank.ace, Suit.diamonds));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
    });

    test('non-Joker chain [2♥,3♥,4♥,4♠] clearable once the discard top allows a legal opener', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.four, Suit.spades),
      ];
      final state = stateForP1(hand, discardTop: c(Rank.two, Suit.clubs));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isTrue);
    });

    test('non-Joker hand with broken run returns false', () {
      final hand = [
        c(Rank.two, Suit.hearts),
        c(Rank.three, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.four, Suit.spades),
      ];
      final state = stateForP1(hand, discardTop: c(Rank.two, Suit.hearts));
      expect(canClearHandInOneTurn(state: state, playerId: 'p1'), isFalse);
    });
  });

  group('Last Cards bluff detection ignores the discard pile', () {
    test(
        'regression: a single self-playable card must never be flagged as a '
        'bluff, no matter what the discard pile drifted to', () {
      // Reported bug: player declares Last Cards holding only 6♥ (trivially
      // playable — it's their whole hand). Other players take their turns
      // before play returns, and the discard pile drifts to 4♦ — sharing
      // neither suit nor rank with 6♥. canClearHandInOneTurn (discard-aware)
      // correctly reports this specific board position as unplayable...
      final driftedState =
          stateForP1([c(Rank.six, Suit.hearts)], discardTop: c(Rank.four, Suit.diamonds));
      expect(
        canClearHandInOneTurn(state: driftedState, playerId: 'p1'),
        isFalse,
        reason: '6♥ genuinely cannot open on 4♦ right now',
      );

      // ...but that must NOT be what bluff detection uses: declaring is a
      // statement about the hand itself, not a bet that the board stays
      // put. TableScreen._offlineApplyLastCardsBluffPenaltyIfNeeded and the
      // server's _handleDeclareLastCards both use this discard-independent
      // check instead, precisely so a shifting pile never turns an honest
      // declare into a false bluff penalty.
      expect(canHandClearInOneTurnHandOnly([c(Rank.six, Suit.hearts)]), isTrue);
    });
  });

  group('shouldShowLastCardsButton', () {
    test('respects bust and declared (no hand-size gate)', () {
      expect(
        shouldShowLastCardsButton(
          isBustMode: true,
          alreadyDeclared: false,
        ),
        isFalse,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          alreadyDeclared: false,
        ),
        isTrue,
      );
      expect(
        shouldShowLastCardsButton(
          isBustMode: false,
          alreadyDeclared: true,
        ),
        isFalse,
      );
    });
  });

  group('applyOpeningSeatLastCardsSeedIfNeeded', () {
    test('seeds opener when hand was clearable at deal (offline/online parity)', () {
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      // King of hearts lets 3♥ (or any ♥) legally open — genuinely clearable.
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.hearts));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      expect(
        state.playerById('p1')!.lastCardsHandWasClearableAtTurnStart,
        isTrue,
      );

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isTrue);
      expect(r.isBluff, isFalse);
      expect(r.state.lastCardsDeclaredBy, contains('p1'));
    });

    test(
        'regression: does NOT seed when the hand only chains among itself but '
        'has no legal opener against the real discard top', () {
      // This is the exact "Guest declared Last Cards" bug reported on a
      // brand-new game: a hand that happens to chain internally (3♥-4♥-5♥
      // value-chains to 5♣) but shares no suit/rank with the actual discard
      // top must NOT be seeded as an honest opening declaration.
      final hand = [
        c(Rank.three, Suit.hearts),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.five, Suit.clubs),
      ];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      expect(
        state.playerById('p1')!.lastCardsHandWasClearableAtTurnStart,
        isFalse,
        reason: 'No card in hand can legally open against K♠',
      );

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isFalse);
      expect(r.state.lastCardsDeclaredBy, isNot(contains('p1')));
    });

    test(
        'regression: does NOT seed for the exact 7-card hand reported live — '
        'Joker/Q♣/J♦/10♠/4♥/5♥/10♦ against a Q♦ discard top', () {
      // A Queen unconditionally accepting any next card, plus a Joker
      // unconditionally bridging to/from anything, together let the old DFS
      // "connect" three unrelated groups (J♦-10♦-10♠ / Q♣ / 4♥-5♥) that no
      // real declared-Joker sequence can actually play out — see the
      // `_validChainStep` regressions above for the isolated bugs.
      final hand = [
        c(Rank.joker, Suit.spades),
        c(Rank.queen, Suit.clubs),
        c(Rank.jack, Suit.diamonds),
        c(Rank.ten, Suit.spades),
        c(Rank.four, Suit.hearts),
        c(Rank.five, Suit.hearts),
        c(Rank.ten, Suit.diamonds),
      ];
      var state = stateForP1(hand, discardTop: c(Rank.queen, Suit.diamonds));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      expect(
        state.playerById('p1')!.lastCardsHandWasClearableAtTurnStart,
        isFalse,
      );

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isFalse);
      expect(r.state.lastCardsDeclaredBy, isNot(contains('p1')));
    });

    test('no-op when opener already declared', () {
      final hand = [c(Rank.five, Suit.hearts)];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: false);
      state = state.copyWith(lastCardsDeclaredBy: {'p1'});

      final r = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(r.applied, isFalse);
    });

    test('no-op in bust mode', () {
      final hand = [c(Rank.five, Suit.hearts)];
      var state = stateForP1(hand, discardTop: c(Rank.king, Suit.spades));
      state = initializeFirstTurnClearability(state, isBustMode: true);

      final r = applyOpeningSeatLastCardsSeedIfNeeded(
        state: state,
        isBustMode: true,
      );
      expect(r.applied, isFalse);
    });

    test('empty hand would not trigger undeclared draw after seed', () {
      var state = stateForP1(
        [
          c(Rank.five, Suit.hearts),
        ],
        discardTop: c(Rank.five, Suit.hearts),
      );
      state = initializeFirstTurnClearability(state, isBustMode: false);
      final seeded = applyOpeningSeatLastCardsSeedIfNeeded(state: state);
      expect(seeded.applied, isTrue);
      final empty = seeded.state.copyWith(
        players: seeded.state.players
            .map((p) {
              if (p.id != 'p1') return p;
              return p.copyWith(hand: [], cardCount: 0);
            })
            .toList(),
      );
      expect(
        needsUndeclaredLastCardsDraw(state: empty, playerId: 'p1'),
        isFalse,
      );
    });
  });
}
