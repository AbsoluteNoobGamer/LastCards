/// Preset quick chat messages shared by client and server.
///
/// Messages are identified by index (0-based) over the wire. Both the client
/// UI ([QuickChatPanel]) and the server validation ([GameSession.handleQuickChat])
/// reference this list so they stay in sync automatically.
const List<String> kQuickMessages = [
  'Good luck!',
  'Well played',
  'Oops!',
  'Nice one!',
  'Sorry!',
  'Good game',
  'Too good!',
  'GG!',
  'I Have A Joker',
  'Pick up',
  'Ahahaha',
  'Sh*t',
  'Damn',
];
