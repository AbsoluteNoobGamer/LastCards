import 'dart:developer' as developer;

/// Lightweight logger for the game server.
///
/// Wraps `dart:developer` log so messages are routed through the standard
/// logging infrastructure instead of raw `print()`.
class Logger {
  Logger(this._tag);

  final String _tag;

  void info(String message) {
    developer.log(message, name: _tag);
  }

  void warning(String message) {
    developer.log(message, name: _tag, level: 900);
  }

  void error(String message) {
    developer.log(message, name: _tag, level: 1000);
  }
}
