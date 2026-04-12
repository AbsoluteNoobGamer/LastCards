import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Display name from Firebase Auth for merging into Firestore public profile.
/// Matches the merge logic in [userProfileProvider] (name, then email local part).
String? resolvedPublicDisplayNameFromAuth(User user) {
  final authName = user.displayName?.trim();
  final emailLocal = user.email?.split('@').first;
  if (authName != null && authName.isNotEmpty) return authName;
  if (emailLocal != null && emailLocal.isNotEmpty) return emailLocal;
  return null;
}

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

  /// If Firestore has no public display name / avatar but Firebase Auth does
  /// (e.g. Google sign-in), merge those into [users/uid] so friends lists and
  /// profiles show real names. Does not set [profileLastChangedAt] (no 14-day
  /// cooldown); only [updateProfile] does.
  Future<void> syncAuthToPublicProfileIfNeeded(User user) async {
    final docRef = _firestore.collection(_usersCollection).doc(user.uid);
    Map<String, dynamic> data;
    try {
      final snap = await docRef.get();
      data = snap.data() ?? {};
    } catch (_) {
      return;
    }

    final existingName = (data['displayName'] as String?)?.trim() ?? '';
    final existingAvatar = data['avatarUrl'] as String?;

    final resolvedName = resolvedPublicDisplayNameFromAuth(user);

    final authPhoto = user.photoURL;

    final updates = <String, dynamic>{};
    if (existingName.isEmpty &&
        resolvedName != null &&
        resolvedName.isNotEmpty) {
      updates['displayName'] = resolvedName;
    }
    if ((existingAvatar == null || existingAvatar.isEmpty) &&
        authPhoto != null &&
        authPhoto.isNotEmpty) {
      updates['avatarUrl'] = authPhoto;
    }

    if (updates.isEmpty) return;

    updates['updatedAt'] = FieldValue.serverTimestamp();
    try {
      await docRef.set(updates, SetOptions(merge: true));
    } catch (_) {
      // Ignore; user may be offline or rules may reject.
    }
  }

  /// One-shot read of another user's public profile (requires signed-in user).
  /// Returns null if the doc is missing or on permission / network failure.
  Future<FirestoreUserProfile?> getProfileForUid(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap =
          await _firestore.collection(_usersCollection).doc(uid).get();
      if (!snap.exists) return null;
      return FirestoreUserProfile.fromDoc(snap);
    } catch (_) {
      return null;
    }
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
    // Cooldown applies only after explicit profile saves ([updateProfile] sets this).
    // Do not fall back to [updatedAt] or auth sync would block edits for 14 days.
    final profileLastChangedAtRaw = data['profileLastChangedAt'];
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
