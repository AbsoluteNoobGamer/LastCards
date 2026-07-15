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

/// True when [displayName] was never actually chosen — it's exactly the
/// local part of [email] (before the `@`), the fallback
/// `userProfileProvider`/`FirestoreProfileService` use when no real name is
/// available. Most visible with Apple Sign-In: when a player declines to
/// share their name, and especially with a private-relay email (e.g.
/// `abc123xyz@privaterelay.appleid.com`), this fallback produces a
/// random-looking alphanumeric display name with no way for the player to
/// know why, or that anything went wrong.
bool isEmailDerivedFallbackName({
  required String? displayName,
  required String? email,
}) {
  final name = displayName?.trim();
  if (name == null || name.isEmpty) return false;
  final localPart = email?.split('@').first.trim();
  if (localPart == null || localPart.isEmpty) return false;
  return name == localPart;
}
