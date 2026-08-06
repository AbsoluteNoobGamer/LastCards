import 'dart:async';

import 'firestore_client.dart';
import 'logger.dart';

// ── Wallet persistence (implemented by [WalletService]) ──────────────────────

/// Hooks for the server-authoritative coin wallet used by [GameSession] wager
/// settlement.
///
/// Production code uses [WalletService.instance]; tests may supply a
/// lightweight implementation that records call counts without Firestore.
abstract class WalletPersistence {
  /// Reads the current `coins` balance for [uid] from `users/{uid}`.
  ///
  /// Returns null if the read failed (Firestore not configured, network
  /// error) or the profile document doesn't exist. Callers must treat a
  /// null result as "cannot confirm sufficient funds" and refuse to lock in
  /// a stake, not as a zero balance.
  Future<int?> checkBalance(String uid);

  /// Atomically decrements [uid]'s `coins` by [amount] (a locked-in stake).
  ///
  /// Fire-and-forget — callers must call [checkBalance] first to confirm
  /// sufficient funds; this call does not re-validate or clamp at zero.
  void chargeStake(String uid, int amount);

  /// Atomically increments [uid]'s `coins` by [amount] (a wager win).
  void payout(String uid, int amount);

  /// Atomically increments [uid]'s `coins` by [amount] (returning a
  /// previously-charged stake — disconnect/abandon or a side-bet push).
  void refund(String uid, int amount);
}

// ── WalletService ─────────────────────────────────────────────────────────────

/// Server-side coin wallet, backed by the same `users/{uid}` Firestore
/// documents the client already reads/writes via `CurrencyNotifier`.
///
/// Every mutation also bumps `walletVersion` by 1 so the client can tell a
/// server-authoritative balance apart from its own stale local cache on
/// reconciliation (see `CurrencyNotifier.applyServerBalance`).
///
/// **Environment setup**: same `GOOGLE_CREDENTIALS_JSON` service account
/// used by [TrophyRecorder] — see that class's doc comment.
class WalletService implements WalletPersistence {
  WalletService._() {
    _firestoreClient.init();
  }
  static final WalletService instance = WalletService._();

  final _log = Logger('WalletService');
  final _firestoreClient = FirestoreClient.instance;

  static const _collection = 'users';

  @override
  Future<int?> checkBalance(String uid) async {
    final fields = await _firestoreClient.getDocumentFields(
      collection: _collection,
      docId: uid,
    );
    if (fields == null) return null;
    final coins = fields['coins'];
    if (coins is int) return coins;
    if (coins is num) return coins.toInt();
    return 0;
  }

  @override
  void chargeStake(String uid, int amount) {
    unawaited(_applyDelta(uid, -amount, reason: 'chargeStake'));
  }

  @override
  void payout(String uid, int amount) {
    unawaited(_applyDelta(uid, amount, reason: 'payout'));
  }

  @override
  void refund(String uid, int amount) {
    unawaited(_applyDelta(uid, amount, reason: 'refund'));
  }

  Future<void> _applyDelta(
    String uid,
    int delta, {
    required String reason,
  }) async {
    final ok = await _firestoreClient.atomicUpdate(
      collection: _collection,
      docId: uid,
      increments: {
        'coins': delta,
        'walletVersion': 1,
      },
      // Only applied if the doc doesn't exist yet — in practice a wager
      // participant always already has a profile doc (verified UID, has
      // played before), so this is a safety net, not the common path.
      defaultFields: {
        'coins': 0,
        'walletVersion': 0,
      },
    );
    if (ok) {
      _log.info('Wallet $reason applied: uid=$uid delta=$delta');
    } else if (!_firestoreClient.isFirestoreConfigured) {
      _log.warning(
        'Wallet $reason not persisted: Firestore credentials missing '
        '(GOOGLE_CREDENTIALS_JSON).',
      );
    } else {
      _log.error(
        'Wallet $reason Firestore write failed: uid=$uid delta=$delta',
      );
    }
  }
}

/// No-op for tests without Firestore.
class NoOpWalletService implements WalletPersistence {
  @override
  Future<int?> checkBalance(String uid) async => null;

  @override
  void chargeStake(String uid, int amount) {}

  @override
  void payout(String uid, int amount) {}

  @override
  void refund(String uid, int amount) {}
}
