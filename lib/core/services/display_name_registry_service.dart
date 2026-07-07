import 'package:cloud_firestore/cloud_firestore.dart';

import '../../shared/leaderboard/display_name_leaderboard_rules.dart';

/// Thrown when a display name is already claimed by another account.
class DisplayNameTakenException implements Exception {
  DisplayNameTakenException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Firestore-backed unique display names (`display_name_registry/{key}`).
class DisplayNameRegistryService {
  DisplayNameRegistryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _collection = 'display_name_registry';

  final FirebaseFirestore _firestore;

  /// Returns a user-facing validation error, or null if [name] is acceptable.
  Future<String?> validateNameForProfile({
    required String name,
    required String uid,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    if (isDefaultOrReservedDisplayName(trimmed)) {
      return 'Choose a unique name — Guest and Player are not allowed on leaderboards';
    }
    final available = await isNameAvailable(trimmed, exceptUid: uid);
    if (!available) {
      return 'That name is already taken — try another';
    }
    return null;
  }

  /// Looks up a UID by display name (same normalization as the uniqueness
  /// check, so it's case/whitespace-insensitive). Returns null if no one has
  /// claimed that exact name.
  Future<String?> findUidByDisplayName(String displayName) async {
    final key = normalizeLeaderboardDisplayNameKey(displayName);
    if (key.isEmpty) return null;
    try {
      final doc = await _firestore.collection(_collection).doc(key).get();
      if (!doc.exists) return null;
      final uid = doc.data()?['uid'] as String?;
      return (uid == null || uid.isEmpty) ? null : uid;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isNameAvailable(String displayName, {String? exceptUid}) async {
    final key = normalizeLeaderboardDisplayNameKey(displayName);
    if (key.isEmpty) return false;
    if (isDefaultOrReservedDisplayName(displayName)) return false;

    try {
      final doc = await _firestore.collection(_collection).doc(key).get();
      if (!doc.exists) return true;
      final owner = doc.data()?['uid'] as String?;
      return owner == null || owner.isEmpty || owner == exceptUid;
    } catch (_) {
      return false;
    }
  }

  /// Claims [displayName] for [uid], releasing [previousDisplayName] if owned.
  Future<void> claimDisplayName({
    required String uid,
    required String displayName,
    String? previousDisplayName,
  }) async {
    final trimmed = displayName.trim();
    if (!isLeaderboardEligibleDisplayName(trimmed)) {
      throw DisplayNameTakenException(
        'Choose a unique name — Guest and Player are not allowed on leaderboards',
      );
    }

    final newKey = normalizeLeaderboardDisplayNameKey(trimmed);
    final oldKey = previousDisplayName != null &&
            previousDisplayName.trim().isNotEmpty
        ? normalizeLeaderboardDisplayNameKey(previousDisplayName)
        : null;

    final newRef = _firestore.collection(_collection).doc(newKey);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(newRef);
      if (existing.exists) {
        final owner = existing.data()?['uid'] as String?;
        if (owner != null && owner.isNotEmpty && owner != uid) {
          throw DisplayNameTakenException('That name is already taken');
        }
      }

      if (oldKey != null && oldKey != newKey) {
        final oldRef = _firestore.collection(_collection).doc(oldKey);
        final oldSnap = await tx.get(oldRef);
        if (oldSnap.exists && oldSnap.data()?['uid'] == uid) {
          tx.delete(oldRef);
        }
      }

      tx.set(newRef, {
        'uid': uid,
        'displayName': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Claims [displayName] only when free (used for Google auth bootstrap).
  Future<bool> tryClaimIfAvailable({
    required String uid,
    required String displayName,
  }) async {
    if (!isLeaderboardEligibleDisplayName(displayName)) return false;
    if (!await isNameAvailable(displayName, exceptUid: uid)) return false;
    try {
      await claimDisplayName(uid: uid, displayName: displayName);
      return true;
    } catch (_) {
      return false;
    }
  }
}
