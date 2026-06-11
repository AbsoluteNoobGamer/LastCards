import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/leaderboard/display_name_leaderboard_rules.dart';
import 'profile_service.dart';

/// Deletes Firestore / Storage data and local prefs for a Firebase [uid].
///
/// Call while the user is still signed in (before [User.delete]).
class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const _users = 'users';
  static const _incoming = 'incomingFriendRequests';
  static const _friends = 'friends';
  static const _invites = 'gameInvites';
  static const _displayNameRegistry = 'display_name_registry';
  static const _avatarStoragePath = 'avatars';

  static const _clientWritableLeaderboards = [
    'leaderboard_single_player',
    'leaderboard_tournament_ai',
    'leaderboard_bust_offline',
  ];

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection(_users).doc(uid);

  /// Best-effort purge of remote and local account data. Throws on hard failures.
  Future<void> purgeUserData(String uid) async {
    final userRef = _userDoc(uid);
    String? displayName;
    String? displayNameKey;
    try {
      final snap = await userRef.get();
      if (snap.exists) {
        final data = snap.data() ?? {};
        displayName = (data['displayName'] as String?)?.trim();
        displayNameKey = data['displayNameKey'] as String?;
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: profile read failed: $e\n$st');
      }
    }

    await _removeFriendBacklinks(uid);
    await _deleteOutgoingFriendRequests(uid);
    await _deleteOutgoingGameInvites(uid);
    await _deleteSubcollection(userRef.collection(_friends));
    await _deleteSubcollection(userRef.collection(_incoming));
    await _deleteSubcollection(userRef.collection(_invites));
    await _releaseDisplayName(
      uid: uid,
      displayName: displayName,
      displayNameKey: displayNameKey,
    );
    await _deleteLeaderboardEntries(uid);
    await _deleteAvatar(uid);
    await userRef.delete();
  }

  /// Clears device prefs tied to the signed-in account.
  static Future<void> clearLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', ProfileDefaults.name);
    await prefs.remove('profile_avatar_path');
    await prefs.remove('reaction_wheel_slots_v1');
    await prefs.remove('player_total_xp');
  }

  Future<void> _removeFriendBacklinks(String uid) async {
    try {
      final friendsSnap = await _userDoc(uid).collection(_friends).get();
      for (final friendDoc in friendsSnap.docs) {
        final friendUid = friendDoc.id;
        try {
          await _userDoc(friendUid).collection(_friends).doc(uid).delete();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint(
              'AccountDeletion: unlink friend $friendUid failed: $e\n$st',
            );
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: friend backlink read failed: $e\n$st');
      }
    }
  }

  Future<void> _deleteOutgoingFriendRequests(String uid) async {
    try {
      final snap = await _firestore
          .collectionGroup(_incoming)
          .where(FieldPath.documentId, isEqualTo: uid)
          .get();
      await _commitDeletes(snap.docs.map((d) => d.reference));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: outgoing friend requests: $e\n$st');
      }
    }
  }

  Future<void> _deleteOutgoingGameInvites(String uid) async {
    try {
      final snap = await _firestore
          .collectionGroup(_invites)
          .where('fromUid', isEqualTo: uid)
          .get();
      await _commitDeletes(snap.docs.map((d) => d.reference));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: outgoing game invites: $e\n$st');
      }
    }
  }

  Future<void> _releaseDisplayName({
    required String uid,
    required String? displayName,
    required String? displayNameKey,
  }) async {
    final keys = <String>{};
    if (displayNameKey != null && displayNameKey.isNotEmpty) {
      keys.add(displayNameKey);
    }
    if (displayName != null && displayName.isNotEmpty) {
      keys.add(normalizeLeaderboardDisplayNameKey(displayName));
    }
    for (final key in keys) {
      try {
        final ref = _firestore.collection(_displayNameRegistry).doc(key);
        final snap = await ref.get();
        if (snap.exists && snap.data()?['uid'] == uid) {
          await ref.delete();
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AccountDeletion: registry $key: $e\n$st');
        }
      }
    }
  }

  Future<void> _deleteLeaderboardEntries(String uid) async {
    for (final collection in _clientWritableLeaderboards) {
      try {
        await _firestore.collection(collection).doc(uid).delete();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AccountDeletion: $collection/$uid: $e\n$st');
        }
      }
    }
  }

  Future<void> _deleteAvatar(String uid) async {
    try {
      await _storage.ref().child('$_avatarStoragePath/$uid.jpg').delete();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: avatar delete: $e\n$st');
      }
    }
  }

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      while (true) {
        final snap = await collection.limit(100).get();
        if (snap.docs.isEmpty) break;
        await _commitDeletes(snap.docs.map((d) => d.reference));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AccountDeletion: subcollection ${collection.path}: $e\n$st');
      }
    }
  }

  Future<void> _commitDeletes(Iterable<DocumentReference<Map<String, dynamic>>> refs) async {
    final list = refs.toList();
    if (list.isEmpty) return;
    for (var i = 0; i < list.length; i += 450) {
      final batch = _firestore.batch();
      final chunk = list.skip(i).take(450);
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}
