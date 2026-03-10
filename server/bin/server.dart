import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:last_cards_server/room_manager.dart';

void main() async {
  final roomManager = RoomManager();

  final handler = webSocketHandler((webSocket, protocol) {
    roomManager.handleConnection(webSocket);
  });

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('Server listening on ws://${server.address.host}:${server.port}');
}
