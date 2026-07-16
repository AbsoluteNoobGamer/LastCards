/// Chat message moderation for lobby / in-game text (client + server).
///
/// Policy:
/// - Racial and homophobic slurs → **reject** the whole message.
/// - `fuck` (and common stems/evasions) → replace with `Fu*k` / `Fu*king` etc.
/// - Milder words such as `shit` are **allowed** unchanged.
///
/// Display names still use the stricter `profanity_filter` package elsewhere.
library;

/// Outcome of [sanitizeChatMessage].
class ChatTextFilterResult {
  const ChatTextFilterResult._({
    required this.rejected,
    this.text,
  });

  /// Message may be shown / broadcast. [text] is the sanitized body.
  factory ChatTextFilterResult.allowed(String text) =>
      ChatTextFilterResult._(rejected: false, text: text);

  /// Message must not be sent (hate speech / slur).
  factory ChatTextFilterResult.rejected() =>
      const ChatTextFilterResult._(rejected: true);

  final bool rejected;
  final String? text;

  bool get isAllowed => !rejected;
}

/// Max length for a single chat line (enforced here so client + server match).
const int kChatMessageMaxLength = 120;

/// Sanitizes [raw] for live chat.
///
/// Trims whitespace, enforces [kChatMessageMaxLength], rejects hate speech,
/// and masks `fuck`-family words. Empty input after trim is rejected.
ChatTextFilterResult sanitizeChatMessage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return ChatTextFilterResult.rejected();
  if (trimmed.length > kChatMessageMaxLength) {
    return ChatTextFilterResult.rejected();
  }

  final normalized = _normalizeForHateMatch(trimmed);
  for (final pattern in _hateSpeechPatterns) {
    if (pattern.hasMatch(normalized)) {
      return ChatTextFilterResult.rejected();
    }
  }

  final masked = _maskFuckFamily(trimmed);
  return ChatTextFilterResult.allowed(masked);
}

/// True when [raw] would be rejected for hate speech (ignores fuck masking).
bool chatMessageContainsHateSpeech(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final normalized = _normalizeForHateMatch(trimmed);
  return _hateSpeechPatterns.any((p) => p.hasMatch(normalized));
}

// ── Fuck masking ─────────────────────────────────────────────────────────────

/// Matches fuck / fucking / fucked / fucker with light evasion (f*ck, f.u.c.k).
/// `u` is optional so spellings like `f*ck` still match.
final RegExp _fuckFamilyPattern = RegExp(
  r'(?<![a-zA-Z])f[\W_]*u?[\W_]*c[\W_]*k+[a-zA-Z]*(?![a-zA-Z])',
  caseSensitive: false,
);

String _maskFuckFamily(String input) {
  return input.replaceAllMapped(_fuckFamilyPattern, (match) {
    final word = match.group(0)!;
    final letters = word.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
    // fck / fuck / fucking → stem after optional "fu"/"f" + "ck"
    String suffix = '';
    if (letters.startsWith('fuck')) {
      suffix = letters.substring(4);
    } else if (letters.startsWith('fck')) {
      suffix = letters.substring(3);
    }
    if (suffix.isEmpty) return 'Fu*k';
    return 'Fu*k$suffix';
  });
}

// ── Hate speech ──────────────────────────────────────────────────────────────

/// Lowercase, strip zero-width chars, map common leetspeak, collapse
/// separators inside tokens so `f.a.g` / `n1gg3r` still match.
String _normalizeForHateMatch(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  s = s
      .replaceAll('@', 'a')
      .replaceAll('4', 'a')
      .replaceAll('0', 'o')
      .replaceAll('1', 'i')
      .replaceAll('3', 'e')
      .replaceAll('5', 's')
      .replaceAll('\$', 's')
      .replaceAll('!', 'i');
  // Collapse punctuation between letters ("f.a.g" → "fag") but keep spaces
  // so multi-word phrases still have word boundaries.
  s = s.replaceAllMapped(
    RegExp(r'([a-z])[^a-z\s]+(?=[a-z])'),
    (m) => m.group(1)!,
  );
  return s;
}

/// Blocked racial / homophobic terms. Kept for moderation matching only.
/// Patterns run against [_normalizeForHateMatch] output.
final List<RegExp> _hateSpeechPatterns = [
  // Racial
  RegExp(r'\bnigg(?:er|a|as)?\b'),
  RegExp(r'\bnegro\b'),
  RegExp(r'\bchink\b'),
  RegExp(r'\bspic\b'),
  RegExp(r'\bkike\b'),
  RegExp(r'\bwetback\b'),
  RegExp(r'\bgook\b'),
  RegExp(r'\bpaki\b'),
  RegExp(r'\bcoon\b'),
  RegExp(r'\braghead\b'),
  RegExp(r'\btowelhead\b'),
  RegExp(r'\bbeaner\b'),
  // Homophobic / transphobic
  RegExp(r'\bfagg?ots?\b'),
  RegExp(r'\bfags?\b'),
  RegExp(r'\bdyke\b'),
  RegExp(r'\btranny\b'),
  RegExp(r'\btrannie\b'),
];
