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

  /// Updates display name and optionally avatar URL in Firestore.
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
    updates['updatedAt'] = FieldValue.serverTimestamp();

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
    await _firestore.collection(_usersCollection).doc(uid).set(
      {'avatarUrl': null, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}

class FirestoreUserProfile {
  final String displayName;
  final String? avatarUrl;

  const FirestoreUserProfile({
    required this.displayName,
    this.avatarUrl,
  });

  factory FirestoreUserProfile.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FirestoreUserProfile(
      displayName: data['displayName'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
    );
  }
}
