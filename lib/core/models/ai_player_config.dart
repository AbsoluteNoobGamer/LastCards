import 'dart:math';

import 'package:flutter/material.dart';

enum AiPersonality { aggressive, safe, tricky }

extension AiPersonalityX on AiPersonality {
  String get label => switch (this) {
        AiPersonality.aggressive => 'AGG',
        AiPersonality.safe => 'SAFE',
        AiPersonality.tricky => 'TRKY',
      };
}

/// Immutable configuration for a single AI opponent generated at game start.
///
/// Holds the random name, avatar color, personality, and chat lines used
/// throughout one game session.
class AiPlayerConfig {
  const AiPlayerConfig({
    required this.playerId,
    required this.name,
    required this.personality,
    required this.nameColor,
    required this.avatarColor,
    required this.chatLines,
  });

  final String playerId;
  final String name;
  final AiPersonality personality;

  /// Color used for the name label when this player is active.
  final Color nameColor;

  /// Background color for the avatar circle.
  final Color avatarColor;

  final List<String> chatLines;

  /// Two-letter initials derived from the player's name.
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, min(2, name.length)).toUpperCase();
  }

  String randomChatLine(Random rng) => chatLines[rng.nextInt(chatLines.length)];

  // ── Name & color pools ──────────────────────────────────────────────────────

  static const List<String> _namePool = [
    'Alex Rivera',
    'Mia Chen',
    'Liam Patel',
    'Zoe Adeyemi',
    'Noah Tanaka',
    'Aisha Okonkwo',
    'Kai Yamamoto',
    'Sofia Reyes',
    'Marcus Webb',
    'Priya Singh',
    'Jordan Kim',
    'Nadia Hassan',
    'Lucas Ferreira',
    'Yuki Nakamura',
    'Amara Diallo',
    'Ben Kowalski',
    'Rosa Castillo',
    'Omar Al-Rashid',
    'Ella Johansson',
    'Dev Kapoor',
  ];

  static const List<Color> _avatarColors = [
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFF1E88E5),
    Color(0xFF00897B),
    Color(0xFFE65100),
    Color(0xFF3949AB),
    Color(0xFF43A047),
    Color(0xFF6D4C41),
    Color(0xFFF4511E),
    Color(0xFF039BE5),
    Color(0xFF7B1FA2),
    Color(0xFF00838F),
  ];

  // ── Factory ─────────────────────────────────────────────────────────────────

  /// Generates [count] unique AI player configs for one game session.
  ///
  /// Pass a [seed] (e.g. `DateTime.now().millisecondsSinceEpoch`) to get a
  /// fresh set each game while keeping them stable for the whole session.
  static List<AiPlayerConfig> generateForGame({int count = 3, int? seed}) {
    assert(count >= 1 && count <= 3);
    final rng = Random(seed);
    final shuffledNames = List<String>.from(_namePool)..shuffle(rng);
    final shuffledColors = List<Color>.from(_avatarColors)..shuffle(rng);

    return List.generate(count, (i) {
      final personality =
          AiPersonality.values[rng.nextInt(AiPersonality.values.length)];
      return AiPlayerConfig(
        playerId: 'player-${i + 2}',
        name: shuffledNames[i],
        personality: personality,
        nameColor: _nameColorFor(personality),
        avatarColor: shuffledColors[i],
        chatLines: _chatLinesFor(personality),
      );
    });
  }

  static Color _nameColorFor(AiPersonality p) => switch (p) {
        AiPersonality.aggressive => const Color(0xFFFF5252),
        AiPersonality.safe => const Color(0xFF64B5F6),
        AiPersonality.tricky => const Color(0xFF69F0AE),
      };

  static List<String> _chatLinesFor(AiPersonality p) => switch (p) {
        AiPersonality.aggressive => [
            'All in!',
            'Last card!',
            'Gotcha!',
            "You're done!",
          ],
        AiPersonality.safe => [
            'Playing it safe',
            'Steady now',
            'Not today',
            'Careful...',
          ],
        AiPersonality.tricky => [
            'Surprise!',
            'Missed me?',
            'Draw time!',
            'Heh!',
          ],
      };
}
