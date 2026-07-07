import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'package:last_cards_server/app_update_broadcaster.dart';
import 'package:last_cards_server/fcm_sender.dart';
import 'package:last_cards_server/firebase_auth_verifier.dart';
import 'package:last_cards_server/invite_push_handler.dart';
import 'package:last_cards_server/room_manager.dart';
import 'package:last_cards_server/trophy_recorder.dart';

void main() async {
  FirebaseAuthVerifier.setApiKey(Platform.environment['FIREBASE_API_KEY']);
  FcmSender.instance.init();
  await syncOnlineServerPresenceReset();
  logGameServerFirestoreStartupStatus();
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final roomManager = RoomManager();

  // Polls app_config/app_update and broadcasts to the app_updates FCM topic
  // when a new version is published (see AppUpdateBroadcaster doc comment
  // for why it never fires on the first check after a restart).
  AppUpdateBroadcaster().start();

  final wsHandler = webSocketHandler((webSocket, protocol) {
    print('[Server] New WebSocket connection');
    roomManager.handleConnection(webSocket);
  });

  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler((shelf.Request request) {
    if (request.url.path == 'stats') {
      return shelf.Response.ok(
        jsonEncode({'websocketConnections': roomManager.openWebSocketCount}),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }
    if (request.url.path == 'notify-invite' && request.method == 'POST') {
      return handleNotifyInviteRequest(request);
    }
    if (request.url.path == 'game') {
      return wsHandler(request);
    }
    return shelf.Response.ok('Last Cards server running');
  });

  final server = await io.serve(handler, '0.0.0.0', port);
  print('[Server] Listening on 0.0.0.0:${server.port}');
}
