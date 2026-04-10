import 'package:flutter/material.dart';

/// Game mode categories for the leaderboard, aligned with main menu entry points.
enum LeaderboardMode {
  ranked('Ranked', Icons.emoji_events),
  rankedHardcore('Ranked (Hardcore)', Icons.whatshot),
  singlePlayer('Single Player', Icons.smart_toy),
  online('Online (Quick Match)', Icons.people),
  tournamentVsAi('Tournament (vs AI)', Icons.shield),
  tournamentOnline('Tournament (Online)', Icons.public),
  bustOffline('Bust (Offline)', Icons.auto_awesome_rounded),
  bustOnline('Bust (Online)', Icons.language_rounded);

  const LeaderboardMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

String collectionForMode(LeaderboardMode mode) {
  switch (mode) {
    case LeaderboardMode.singlePlayer:
      return 'leaderboard_single_player';
    case LeaderboardMode.online:
      return 'leaderboard_online';
    case LeaderboardMode.tournamentVsAi:
      return 'leaderboard_tournament_ai';
    case LeaderboardMode.tournamentOnline:
      return 'leaderboard_tournament_online';
    case LeaderboardMode.ranked:
      return 'ranked_stats';
    case LeaderboardMode.rankedHardcore:
      return 'ranked_hardcore_stats';
    case LeaderboardMode.bustOffline:
      return 'leaderboard_bust_offline';
    case LeaderboardMode.bustOnline:
      return 'leaderboard_bust_online';
  }
}
