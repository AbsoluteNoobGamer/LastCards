import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:last_cards_server/room_manager.dart';
import 'package:last_cards_server/trophy_recorder.dart';

void main() async {
  await syncOnlineServerPresenceReset();
  final roomManager = RoomManager();

  final handler = webSocketHandler((webSocket, protocol) {
    roomManager.handleConnection(webSocket);
  });

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('Server listening on ws://${server.address.host}:${server.port}');
}
