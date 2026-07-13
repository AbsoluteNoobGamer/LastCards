import 'dart:convert';
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

  /// Emits a single structured JSON line — `{"event": name, "ts": ...,
  /// "logger": _name, ...fields}` — for telemetry destined for a log sink
  /// (Cloud Logging → BigQuery; see docs/analytics-plan.md §2 Phase 0),
  /// kept separate from the human-readable [info]/[warning]/[error] lines.
  void event(String name, Map<String, Object?> fields) {
    stdout.writeln(jsonEncode({
      'event': name,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'logger': _name,
      ...fields,
    }));
  }
}
