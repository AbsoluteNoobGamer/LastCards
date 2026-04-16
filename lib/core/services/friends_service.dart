import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore-backed friends and in-app room invites.
class FriendsService {
  FriendsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const _users = 'users';
  static const _incoming = 'incomingFriendRequests';
  static const _friends = 'friends';
  static const _invites = 'gameInvites';

  /// Room-invite notifications expire after this; the Firestore doc is deleted.
  static const Duration gameInviteMaxAge = Duration(seconds: 30);

  final Map<String, Timer> _gameInviteExpireTimers = {};
  final Map<String, DateTime> _inviteExpiryAnchorWhenNoTimestamp = {};

  /// Cancels invite expiry timers. Safe to call when the service is torn down
  /// (e.g. [Provider] `onDispose`); does not delete Firestore documents.
  void dispose() {
    for (final t in _gameInviteExpireTimers.values) {
      t.cancel();
    }
    _gameInviteExpireTimers.clear();
    _inviteExpiryAnchorWhenNoTimestamp.clear();
  }

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection(_users).doc(uid);

  /// UIDs of accepted friends (document ids under `users/me/friends`).
  Stream<List<String>> friendUidStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _userDoc(uid).collection(_friends).snapshots().map(
          (s) => s.docs.map((d) => d.id).toList(),
        );
  }

  Stream<List<IncomingFriendRequest>> incomingRequestsStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _userDoc(uid).collection(_incoming).snapshots().map(
          (s) => s.docs
              .map((d) => IncomingFriendRequest(fromUid: d.id))
              .toList(),
        );
  }

  /// Pending game invites for the current user.
  ///
  /// **Single-subscription:** This stream performs side effects (stale deletes,
  /// expiry timers). Subscribe at most once (e.g. one `StreamProvider`); a
  /// second listener would duplicate timers on the shared [FriendsService] instance.
  Stream<List<GameInviteEntry>> gameInvitesStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _userDoc(uid).collection(_invites).snapshots().map((s) {
      final entries =
          s.docs.map(GameInviteEntry.fromDoc).whereType<GameInviteEntry>().toList();
      final now = DateTime.now();
      final fresh = <GameInviteEntry>[];
      final staleIds = <String>[];
      for (final e in entries) {
        final anchor = e.createdAt ??
            _inviteExpiryAnchorWhenNoTimestamp[e.id] ??
            _inviteExpiryAnchorWhenNoTimestamp.putIfAbsent(
              e.id,
              () => DateTime.now(),
            );
        if (now.difference(anchor) > gameInviteMaxAge) {
          staleIds.add(e.id);
          _inviteExpiryAnchorWhenNoTimestamp.remove(e.id);
        } else {
          fresh.add(e);
        }
      }
      if (staleIds.isNotEmpty) {
        for (final id in staleIds) {
          unawaited(_userDoc(uid).collection(_invites).doc(id).delete());
        }
      }
      fresh.sort((a, b) {
        final ca = a.createdAt;
        final cb = b.createdAt;
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
      });
      _syncGameInviteExpireTimers(fresh);
      return fresh;
    });
  }

  /// Ensures each visible invite is deleted from Firestore when its window ends,
  /// even if no further snapshots arrive (timers).
  void _syncGameInviteExpireTimers(List<GameInviteEntry> fresh) {
    final ids = fresh.map((e) => e.id).toSet();
    for (final id in _gameInviteExpireTimers.keys.toList()) {
      if (!ids.contains(id)) {
        _gameInviteExpireTimers.remove(id)?.cancel();
      }
    }
    for (final id in _inviteExpiryAnchorWhenNoTimestamp.keys.toList()) {
      if (!ids.contains(id)) {
        _inviteExpiryAnchorWhenNoTimestamp.remove(id);
      }
    }
    for (final e in fresh) {
      _scheduleGameInviteExpiry(e);
    }
  }

  void _scheduleGameInviteExpiry(GameInviteEntry e) {
    final anchor = e.createdAt ??
        _inviteExpiryAnchorWhenNoTimestamp.putIfAbsent(
          e.id,
          () => DateTime.now(),
        );
    var remaining = gameInviteMaxAge - DateTime.now().difference(anchor);
    if (remaining.isNegative) {
      remaining = Duration.zero;
    }

    _gameInviteExpireTimers[e.id]?.cancel();
    _gameInviteExpireTimers[e.id] = Timer(remaining, () {
      _gameInviteExpireTimers.remove(e.id);
      _inviteExpiryAnchorWhenNoTimestamp.remove(e.id);
      unawaited(deleteGameInvite(e.id));
    });
  }

  Future<FriendRelation> relationTo(String otherUid) async {
    final me = _uid;
    if (me == null) return FriendRelation.notSignedIn;
    if (me == otherUid) return FriendRelation.self;

    try {
      final batch = await Future.wait([
        _userDoc(me).collection(_friends).doc(otherUid).get(),
        _userDoc(me).collection(_incoming).doc(otherUid).get(),
        _userDoc(otherUid).collection(_incoming).doc(me).get(),
      ]);

      if (batch[0].exists) return FriendRelation.friends;
      if (batch[1].exists) return FriendRelation.incomingRequest;
      if (batch[2].exists) return FriendRelation.outgoingRequest;
      return FriendRelation.none;
    } catch (_) {
      return FriendRelation.none;
    }
  }

  Future<void> sendFriendRequest(String toUid) async {
    final from = _uid;
    if (from == null || from == toUid) return;
    await _userDoc(toUid).collection(_incoming).doc(from).set({
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelOutgoingFriendRequest(String toUid) async {
    final from = _uid;
    if (from == null) return;
    await _userDoc(toUid).collection(_incoming).doc(from).delete();
  }

  Future<void> acceptFriendRequest(String fromUid) async {
    final me = _uid;
    if (me == null || me == fromUid) return;

    final batch = _firestore.batch();
    batch.delete(_userDoc(me).collection(_incoming).doc(fromUid));
    batch.set(_userDoc(me).collection(_friends).doc(fromUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_userDoc(fromUid).collection(_friends).doc(me), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> declineFriendRequest(String fromUid) async {
    final me = _uid;
    if (me == null) return;
    await _userDoc(me).collection(_incoming).doc(fromUid).delete();
  }

  Future<void> removeFriend(String otherUid) async {
    final me = _uid;
    if (me == null || otherUid == me) return;
    final batch = _firestore.batch();
    batch.delete(_userDoc(me).collection(_friends).doc(otherUid));
    batch.delete(_userDoc(otherUid).collection(_friends).doc(me));
    await batch.commit();
  }

  /// Notifies [toUid] with a joinable room code (no copy/paste for them).
  Future<void> sendGameInvite({
    required String toUid,
    required String roomCode,
    required String fromDisplayName,
  }) async {
    final from = _uid;
    if (from == null || toUid == from) return;
    await _userDoc(toUid).collection(_invites).add({
      'fromUid': from,
      'fromDisplayName': fromDisplayName,
      'roomCode': roomCode.toUpperCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGameInvite(String inviteDocId) async {
    _gameInviteExpireTimers.remove(inviteDocId)?.cancel();
    _inviteExpiryAnchorWhenNoTimestamp.remove(inviteDocId);
    final uid = _uid;
    if (uid == null) return;
    await _userDoc(uid).collection(_invites).doc(inviteDocId).delete();
  }
}

enum FriendRelation {
  notSignedIn,
  self,
  none,
  friends,
  incomingRequest,
  outgoingRequest,
}

class IncomingFriendRequest {
  const IncomingFriendRequest({required this.fromUid});
  final String fromUid;
}

class GameInviteEntry {
  const GameInviteEntry({
    required this.id,
    required this.fromUid,
    required this.fromDisplayName,
    required this.roomCode,
    required this.createdAt,
  });

  final String id;
  final String fromUid;
  final String fromDisplayName;
  final String roomCode;
  final DateTime? createdAt;

  static GameInviteEntry? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    if (!d.exists) return null;
    final data = d.data();
    if (data == null) return null;
    final code = data['roomCode'] as String?;
    final from = data['fromUid'] as String?;
    if (code == null || from == null) return null;
    final createdRaw = data['createdAt'];
    DateTime? created;
    if (createdRaw is Timestamp) created = createdRaw.toDate();
    return GameInviteEntry(
      id: d.id,
      fromUid: from,
      fromDisplayName: data['fromDisplayName'] as String? ?? 'Player',
      roomCode: code,
      createdAt: created,
    );
  }
}
