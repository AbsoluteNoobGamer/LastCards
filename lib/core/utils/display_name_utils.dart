import 'dart:math';

/// Extracts 2-letter initials from a display name for avatar fallbacks.
///
/// - "John Doe" → "JD"
/// - "Alice" → "AL"
/// - Single char → that char uppercased
String initialsFromDisplayName(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final first = parts.first;
    final last = parts.last;
    return '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}'
        .toUpperCase();
  }
  return trimmed.substring(0, min(2, trimmed.length)).toUpperCase();
}
