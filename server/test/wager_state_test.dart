import 'package:last_cards_server/wager_state.dart';
import 'package:test/test.dart';

void main() {
  group('WagerConfig', () {
    test('rejects a non-positive stake', () {
      expect(
        () => WagerConfig(
            mode: WagerMode.pot, stakeCoins: 0, initiatorPlayerId: 'p1'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a sideBet with no targetPlayerId', () {
      expect(
        () => WagerConfig(
            mode: WagerMode.sideBet, stakeCoins: 10, initiatorPlayerId: 'p1'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a pot config does not require a targetPlayerId', () {
      final cfg = WagerConfig(
          mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1');
      expect(cfg.targetPlayerId, isNull);
    });
  });

  group('WagerState.setConfig', () {
    test('replacing the config clears prior accept/lock/settled state', () {
      final state = WagerState();
      state.setConfig(
        WagerConfig(mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'),
      );
      state.setAccept('p2', true);
      state.lockedPlayerIds.add('p2');
      state.settled = true;

      state.setConfig(
        WagerConfig(mode: WagerMode.pot, stakeCoins: 20, initiatorPlayerId: 'p1'),
      );

      expect(state.acceptStatus, isEmpty);
      expect(state.lockedPlayerIds, isEmpty);
      expect(state.settled, isFalse);
      expect(state.config!.stakeCoins, 20);
    });

    test('setConfig(null) clears an active proposal entirely', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      state.setConfig(null);
      expect(state.config, isNull);
    });
  });

  group('WagerState.participantPlayerIds', () {
    test('pot mode: every currently seated player', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      expect(
        state.participantPlayerIds(['p1', 'p2', 'p3']),
        {'p1', 'p2', 'p3'},
      );
    });

    test('sideBet mode: only the initiator and target, seated roster ignored',
        () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.sideBet,
            stakeCoins: 10,
            initiatorPlayerId: 'p2',
            targetPlayerId: 'p3'));
      expect(
        state.participantPlayerIds(['p1', 'p2', 'p3', 'p4']),
        {'p2', 'p3'},
      );
    });

    test('no active config: empty set', () {
      expect(WagerState().participantPlayerIds(['p1', 'p2']), isEmpty);
    });
  });

  group('WagerState.isFullyAccepted', () {
    test('pot: false until every non-initiator seat has accepted', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isFalse);

      state.setAccept('p2', true);
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isFalse);

      state.setAccept('p3', true);
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isTrue);
    });

    test('pot: the initiator is never required to accept their own proposal',
        () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      state.setAccept('p2', true);
      expect(state.isFullyAccepted(['p1', 'p2']), isTrue);
    });

    test('pot: a decline blocks the gate even if others accepted', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      state.setAccept('p2', true);
      state.setAccept('p3', false);
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isFalse);
    });

    test('sideBet: only the target seat needs to accept', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.sideBet,
            stakeCoins: 10,
            initiatorPlayerId: 'p2',
            targetPlayerId: 'p3'));
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isFalse);

      state.setAccept('p3', true);
      expect(state.isFullyAccepted(['p1', 'p2', 'p3']), isTrue);
    });

    test('no active config: always false', () {
      expect(WagerState().isFullyAccepted(['p1', 'p2']), isFalse);
    });
  });

  group('WagerState.reset', () {
    test('clears config, accept status, locked ids, and settled', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 10, initiatorPlayerId: 'p1'));
      state.setAccept('p2', true);
      state.lockedPlayerIds.add('p2');
      state.settled = true;

      state.reset();

      expect(state.config, isNull);
      expect(state.acceptStatus, isEmpty);
      expect(state.lockedPlayerIds, isEmpty);
      expect(state.settled, isFalse);
    });
  });

  group('WagerState.toJson', () {
    test('serializes an active pot proposal', () {
      final state = WagerState()
        ..setConfig(WagerConfig(
            mode: WagerMode.pot, stakeCoins: 30, initiatorPlayerId: 'p1'));
      state.setAccept('p2', true);
      state.setAccept('p3', false);

      final json = state.toJson();
      expect(json['mode'], 'pot');
      expect(json['stakeCoins'], 30);
      expect(json['initiatorPlayerId'], 'p1');
      expect(json['targetPlayerId'], isNull);
      expect(json['acceptStatus'], {'p2': 'accepted', 'p3': 'declined'});
      expect(json['settled'], isFalse);
    });

    test('serializes an empty state with null config fields', () {
      final json = WagerState().toJson();
      expect(json['mode'], isNull);
      expect(json['stakeCoins'], isNull);
      expect(json['acceptStatus'], isEmpty);
    });
  });
}
