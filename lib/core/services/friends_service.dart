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

  Stream<List<GameInviteEntry>> gameInvitesStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _userDoc(uid).collection(_invites).snapshots().map((s) {
      return s.docs.map(GameInviteEntry.fromDoc).whereType<GameInviteEntry>().toList();
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
