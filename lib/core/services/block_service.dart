import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore-backed user blocking and abuse reporting.
class BlockService {
  BlockService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const _users = 'users';
  static const _blocked = 'blockedUsers';
  static const _friends = 'friends';
  static const _reports = 'reports';

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection(_users).doc(uid);

  /// UIDs the current user has blocked.
  Stream<Set<String>> blockedUidStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _userDoc(uid).collection(_blocked).snapshots().map(
          (s) => s.docs.map((d) => d.id).toSet(),
        );
  }

  Future<bool> isBlocked(String otherUid) async {
    final uid = _uid;
    if (uid == null) return false;
    final doc = await _userDoc(uid).collection(_blocked).doc(otherUid).get();
    return doc.exists;
  }

  /// Blocks [otherUid] and removes any existing friendship on both sides.
  Future<void> blockUser(String otherUid) async {
    final me = _uid;
    if (me == null || me == otherUid) return;
    final batch = _firestore.batch();
    batch.set(_userDoc(me).collection(_blocked).doc(otherUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_userDoc(me).collection(_friends).doc(otherUid));
    batch.delete(_userDoc(otherUid).collection(_friends).doc(me));
    await batch.commit();
  }

  Future<void> unblockUser(String otherUid) async {
    final me = _uid;
    if (me == null) return;
    await _userDoc(me).collection(_blocked).doc(otherUid).delete();
  }

  /// Reports [reportedDisplayName] (and optionally a specific chat message)
  /// for review. [reportedUid] may be null for guest/AI opponents who have
  /// no Firebase identity.
  Future<void> reportUser({
    required String? reportedUid,
    required String reportedDisplayName,
    required String reason,
    String? messageText,
    String? roomCode,
  }) async {
    final me = _uid;
    if (me == null) return;
    await _firestore.collection(_reports).add({
      'reporterUid': me,
      'reportedUid': reportedUid,
      'reportedDisplayName': reportedDisplayName,
      'reason': reason,
      'messageText': messageText,
      'roomCode': roomCode,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
