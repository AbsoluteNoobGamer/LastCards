import 'package:mockito/annotations.dart';

import 'package:last_cards/core/network/game_event_handler.dart';
import 'package:last_cards/core/network/websocket_client.dart';

@GenerateNiceMocks([
  MockSpec<WebSocketClient>(),
  MockSpec<GameEventHandler>(),
])
void main() {}
