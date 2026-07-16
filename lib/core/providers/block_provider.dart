import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/block_service.dart';

final blockServiceProvider = Provider<BlockService>((ref) {
  return BlockService();
});

/// Blocked UIDs for the signed-in user (empty stream when not signed in).
final blockedUidSetProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(blockServiceProvider).blockedUidStream();
});
