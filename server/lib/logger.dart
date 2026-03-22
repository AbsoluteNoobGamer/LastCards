import 'dart:io';

/// Lightweight logger for the game server.
///
/// Writes prefixed lines to stdout (info/warning) or stderr (error).
class Logger {
  Logger(this._name);

  final String _name;

  void info(String message) {
    stdout.writeln('[$_name] $message');
  }

  void warning(String message) {
    stdout.writeln('[$_name] WARNING: $message');
  }

  void error(String message) {
    stderr.writeln('[$_name] ERROR: $message');
  }
}
