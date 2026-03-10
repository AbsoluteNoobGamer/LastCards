import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:last_cards_server/room_manager.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final roomManager = RoomManager();

  final handler = webSocketHandler((webSocket, protocol) {
    roomManager.handleConnection(webSocket);
  });

  final server = await io.serve(handler, '0.0.0.0', port);
  print('Server listening on port ${server.port}');
}
