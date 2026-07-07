import 'package:cloud_firestore/cloud_firestore.dart';

/// A single in-app notification (server-written; see `firestore.rules` —
/// clients may only read/mark-read/delete their own).
class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory InboxNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return InboxNotification(
      id: doc.id,
      type: data['type'] as String? ?? 'system',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
      read: data['read'] as bool? ?? false,
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;
}

class NotificationInboxService {
  static const _usersCollection = 'users';
  static const _notificationsSubcollection = 'notifications';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String uid) => _firestore
      .collection(_usersCollection)
      .doc(uid)
      .collection(_notificationsSubcollection);

  /// Most recent 50 notifications, newest first.
  Stream<List<InboxNotification>> streamForUser(String uid) {
    return _collection(uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(InboxNotification.fromDoc).toList());
  }

  Future<void> markRead(String uid, String notificationId) {
    return _collection(uid).doc(notificationId).set(
      {'read': true},
      SetOptions(merge: true),
    );
  }

  Future<void> delete(String uid, String notificationId) {
    return _collection(uid).doc(notificationId).delete();
  }
}
