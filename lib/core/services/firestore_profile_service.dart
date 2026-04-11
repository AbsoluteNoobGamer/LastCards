import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Server-side user profile: displayName and avatarUrl stored in Firestore.
/// Avatar images are uploaded to Firebase Storage.
class FirestoreProfileService {
  static const _usersCollection = 'users';
  static const _avatarStoragePath = 'avatars';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Streams the user profile from Firestore. Returns null when no user.
  Stream<FirestoreUserProfile?> profileStream(User? user) {
    if (user == null) return Stream.value(null);
    return _firestore
        .collection(_usersCollection)
        .doc(user.uid)
        .snapshots()
        .map((snap) => snap.exists ? FirestoreUserProfile.fromDoc(snap) : null);
  }

  /// One-shot read of another user's public profile (requires signed-in user).
  Future<FirestoreUserProfile?> getProfileForUid(String uid) async {
    final snap =
        await _firestore.collection(_usersCollection).doc(uid).get();
    if (!snap.exists) return null;
    return FirestoreUserProfile.fromDoc(snap);
  }

  /// Updates display name and optionally avatar URL in Firestore.
  /// Also sets [profileLastChangedAt] for the 14-day edit cooldown.
  Future<void> updateProfile({
    required String uid,
    String? displayName,
    String? avatarUrl,
  }) async {
    final ref = _firestore.collection(_usersCollection).doc(uid);
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;

    if (updates.isEmpty) return;
    final now = FieldValue.serverTimestamp();
    updates['updatedAt'] = now;
    updates['profileLastChangedAt'] = now;

    await ref.set(updates, SetOptions(merge: true));
  }

  /// Uploads avatar bytes to Storage and returns the download URL.
  /// Use XFile.readAsBytes() from image_picker for cross-platform support.
  Future<String> uploadAvatar(String uid, Uint8List bytes) async {
    final path = '$_avatarStoragePath/$uid.jpg';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Clears the avatar (sets avatarUrl to null in Firestore).
  Future<void> clearAvatar(String uid) async {
    final now = FieldValue.serverTimestamp();
    await _firestore.collection(_usersCollection).doc(uid).set(
      {
        'avatarUrl': null,
        'updatedAt': now,
        'profileLastChangedAt': now,
      },
      SetOptions(merge: true),
    );
  }
}

class FirestoreUserProfile {
  final String displayName;
  final String? avatarUrl;
  final DateTime? profileLastChangedAt;

  const FirestoreUserProfile({
    required this.displayName,
    this.avatarUrl,
    this.profileLastChangedAt,
  });

  factory FirestoreUserProfile.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final profileLastChangedAtRaw = data['profileLastChangedAt'] ?? data['updatedAt'];
    DateTime? profileLastChangedAt;
    if (profileLastChangedAtRaw is Timestamp) {
      profileLastChangedAt = profileLastChangedAtRaw.toDate();
    }
    return FirestoreUserProfile(
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      profileLastChangedAt: profileLastChangedAt,
    );
  }
}
