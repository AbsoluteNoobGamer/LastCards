import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Credentials for [rejoin_session] after a WebSocket reconnect.
class OnlineRejoinState {
  const OnlineRejoinState({this.roomCode, this.playerId});

  final String? roomCode;
  final String? playerId;

  OnlineRejoinState copyWith({
    String? roomCode,
    String? playerId,
    bool clearRoomCode = false,
    bool clearPlayerId = false,
  }) {
    return OnlineRejoinState(
      roomCode: clearRoomCode ? null : (roomCode ?? this.roomCode),
      playerId: clearPlayerId ? null : (playerId ?? this.playerId),
    );
  }
}

class OnlineRejoinNotifier extends StateNotifier<OnlineRejoinState> {
  OnlineRejoinNotifier() : super(const OnlineRejoinState());

  void setRoomCode(String roomCode) {
    state = state.copyWith(roomCode: roomCode);
  }

  void setPlayerId(String playerId) {
    state = state.copyWith(playerId: playerId);
  }

  void clear() => state = const OnlineRejoinState();
}

final onlineRejoinProvider =
    StateNotifierProvider<OnlineRejoinNotifier, OnlineRejoinState>(
  (ref) => OnlineRejoinNotifier(),
);
