import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/core/providers/online_rejoin_listener_provider.dart';

/// Safe, deterministic override for [onlineRejoinListenerProvider] in tests
/// that pump [LastCardsApp] — it just wires a websocket reconnect
/// callback, no Firestore/Auth calls, safe to override with `null`.
///
/// NOTE: `reactionWheelProvider` is NOT included here. It's typed as
/// `StateNotifierProvider<ReactionWheelNotifier, List<int>>`, and overriding
/// it requires returning the exact `ReactionWheelNotifier` class — but its
/// Firestore-touching logic lives in a *private* method called
/// unconditionally from its constructor, so there is no clean way to
/// subclass around it. Don't attempt to fully mock Firebase for
/// LastCardsApp-pumping tests without solving that first; a previous
/// attempt caused a real 7+ minute test hang.
List<Override> firebaseSafeLastCardsAppOverrides() => [
      onlineRejoinListenerProvider.overrideWith((ref) => null),
    ];
