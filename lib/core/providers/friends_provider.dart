import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/friends_service.dart';

final friendsServiceProvider =
    Provider<FriendsService>((ref) => FriendsService());

/// Friend UIDs for the signed-in user (empty stream when not signed in).
final friendUidListProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(friendsServiceProvider).friendUidStream();
});

final incomingFriendRequestsProvider =
    StreamProvider<List<IncomingFriendRequest>>((ref) {
  return ref.watch(friendsServiceProvider).incomingRequestsStream();
});

final pendingGameInvitesProvider =
    StreamProvider<List<GameInviteEntry>>((ref) {
  return ref.watch(friendsServiceProvider).gameInvitesStream();
});
