import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'card_model.dart';
import 'player_model.dart';

/// Represents a single event or turn action logged in the minimalist UI.
@immutable
class MoveLogEntry {
  final String id;
  final String? player;
  final TablePosition? playerPosition;
  final List<CardModel> cards;
  final bool isDraw;
  final int drawCount;
  final String? drawReason; // e.g. "(penalty)"
  final bool isSpecial;
  final bool isGameEvent;
  final String? eventText; // e.g. "↻ Direction reversed"

  MoveLogEntry({
    String? id,
    this.player,
    this.playerPosition,
    this.cards = const [],
    this.isDraw = false,
    this.drawCount = 0,
    this.drawReason,
    this.isSpecial = false,
    this.isGameEvent = false,
    this.eventText,
  }) : id = id ??
            'log_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(10000)}';
}
