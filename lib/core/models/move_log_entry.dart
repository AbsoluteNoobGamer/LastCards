import 'card_model.dart';

enum MoveLogEntryType {
  play,
  draw,
  timeoutDraw,
  invalidPlayDraw,
  lastCardsDeclared,
  lastCardsBluff,
}

class MoveCardAction {
  const MoveCardAction({
    required this.card,
    this.aceDeclaredSuit,
  });

  final CardModel card;
  final Suit? aceDeclaredSuit;

  MoveCardAction copyWith({
    CardModel? card,
    Suit? aceDeclaredSuit,
    bool clearAceDeclaredSuit = false,
  }) {
    return MoveCardAction(
      card: card ?? this.card,
      aceDeclaredSuit: clearAceDeclaredSuit
          ? null
          : (aceDeclaredSuit ?? this.aceDeclaredSuit),
    );
  }
}

class MoveLogEntry {
  const MoveLogEntry({
    required this.playerId,
    required this.playerName,
    required this.type,
    this.cardActions = const <MoveCardAction>[],
    this.skippedPlayerNames = const <String>[],
    this.drawCount = 0,
    this.turnContinues = false,
  });

  final String playerId;
  final String playerName;
  final MoveLogEntryType type;
  final List<MoveCardAction> cardActions;
  final List<String> skippedPlayerNames;
  final int drawCount;
  final bool turnContinues;

  factory MoveLogEntry.play({
    required String playerId,
    required String playerName,
    required List<MoveCardAction> cardActions,
    required List<String> skippedPlayerNames,
    required bool turnContinues,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.play,
      cardActions: cardActions,
      skippedPlayerNames: skippedPlayerNames,
      turnContinues: turnContinues,
    );
  }

  factory MoveLogEntry.draw({
    required String playerId,
    required String playerName,
    int drawCount = 1,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.draw,
      drawCount: drawCount,
    );
  }

  factory MoveLogEntry.timeoutDraw({
    required String playerId,
    required String playerName,
    int drawCount = 1,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.timeoutDraw,
      drawCount: drawCount,
    );
  }

  factory MoveLogEntry.invalidPlayDraw({
    required String playerId,
    required String playerName,
    int drawCount = 2,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.invalidPlayDraw,
      drawCount: drawCount,
    );
  }

  factory MoveLogEntry.lastCardsDeclared({
    required String playerId,
    required String playerName,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.lastCardsDeclared,
    );
  }

  factory MoveLogEntry.lastCardsBluff({
    required String playerId,
    required String playerName,
    int drawCount = 2,
  }) {
    return MoveLogEntry(
      playerId: playerId,
      playerName: playerName,
      type: MoveLogEntryType.lastCardsBluff,
      drawCount: drawCount,
    );
  }

  MoveLogEntry copyWith({
    String? playerId,
    String? playerName,
    MoveLogEntryType? type,
    List<MoveCardAction>? cardActions,
    List<String>? skippedPlayerNames,
    int? drawCount,
    bool? turnContinues,
  }) {
    return MoveLogEntry(
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      type: type ?? this.type,
      cardActions: cardActions ?? this.cardActions,
      skippedPlayerNames: skippedPlayerNames ?? this.skippedPlayerNames,
      drawCount: drawCount ?? this.drawCount,
      turnContinues: turnContinues ?? this.turnContinues,
    );
  }
}
