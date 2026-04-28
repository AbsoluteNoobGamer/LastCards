/// Preset emoji reactions shared by client and server (Clash Royale–style).
///
/// Identified by index (0-based) over the wire. The client UI ([QuickChatPanel])
/// and the server ([GameSession.handleQuickChat]) reference this list so they
/// stay in sync automatically.
const List<String> kQuickMessages = [
  '🤞', // good luck
  '👏', // well played
  '😅', // oops
  '🔥', // nice one
  '🙏', // sorry
  '🙌', // good game
  '💪', // too good
  '✌️', // GG
  '🃏', // joker
  '☝️', // pick up
  '😂', // laugh
  '😬', // frustrated
  '😤', // damn
];
