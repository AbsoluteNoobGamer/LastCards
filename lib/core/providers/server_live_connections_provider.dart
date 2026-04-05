import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../network/game_server_http.dart';

/// Live WebSocket connection count from the game server ([GET /stats]).
///
/// Polls every 8 seconds. Null if the request fails (wrong host, offline, or
/// server older than `/stats`). Uses the same [WS_URL] host as online play.
final serverLiveConnectionsProvider = StreamProvider<int?>((ref) {
  final controller = StreamController<int?>();
  final client = http.Client();

  Future<void> poll() async {
    try {
      final response = await client
          .get(gameServerStatsUri())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        controller.add(null);
        return;
      }
      final map =
          jsonDecode(response.body) as Map<String, dynamic>? ?? <String, dynamic>{};
      final v = map['websocketConnections'];
      if (v is num) {
        controller.add(v.toInt());
      } else {
        controller.add(null);
      }
    } catch (_) {
      controller.add(null);
    }
  }

  unawaited(poll());
  final timer = Timer.periodic(const Duration(seconds: 8), (_) => poll());
  ref.onDispose(() {
    timer.cancel();
    client.close();
    controller.close();
  });

  return controller.stream;
});
