import 'player_model.dart';

/// Opponent slots around the table for seat indices 1, 2, … (index 0 is always
/// [TablePosition.bottom] for the human / first roster entry).
///
/// Must stay in sync with [tablePositionForSeatIndex] and online
/// [GameSession] seating.
const List<TablePosition> kOpponentTablePositionCycle = [
  TablePosition.left,
  TablePosition.top,
  TablePosition.right,
  TablePosition.bottomLeft,
  TablePosition.topLeft,
  TablePosition.topRight,
  TablePosition.bottomRight,
  TablePosition.farLeft,
  TablePosition.farRight,
];

/// Roster order: index `0` → bottom; indices `1…` cycle through
/// [kOpponentTablePositionCycle].
TablePosition tablePositionForSeatIndex(int index) {
  if (index == 0) return TablePosition.bottom;
  return kOpponentTablePositionCycle[
      (index - 1) % kOpponentTablePositionCycle.length];
}
