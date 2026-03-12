import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

import '../lib/room_manager.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final roomManager = RoomManager();

  final wsHandler = webSocketHandler((webSocket, protocol) {
    print('[Server] New WebSocket connection');
    roomManager.handleConnection(webSocket);
  });

  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler((shelf.Request request) {
    if (request.url.path == 'game') {
      return wsHandler(request);
    }
    return shelf.Response.ok('Last Cards server running');
  });

  final server = await io.serve(handler, '0.0.0.0', port);
  print('[Server] Listening on 0.0.0.0:${server.port}');
}
