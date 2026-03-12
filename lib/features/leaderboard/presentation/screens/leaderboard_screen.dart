import 'package:flutter/material.dart';

/// Game mode categories for the leaderboard, aligned with main menu entry points.
enum LeaderboardMode {
  singlePlayer('Single Player', Icons.smart_toy),
  online('Online', Icons.people),
  tournamentVsAi('Tournament (vs AI)', Icons.emoji_events),
  tournamentOnline('Tournament (Online)', Icons.public);

  const LeaderboardMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = false;
  LeaderboardMode _selectedMode = LeaderboardMode.singlePlayer;

  final List<Map<String, dynamic>> _mockPlayers = [
    {'name': 'ACE_KILLER_99', 'wins': 1432, 'streak': 12},
    {'name': 'JokerMaster', 'wins': 1204, 'streak': 4},
    {'name': 'StackQueen', 'wins': 987, 'streak': 0},
    {'name': 'FlowStateGamer', 'wins': 945, 'streak': 7},
    {'name': 'CardShark22', 'wins': 812, 'streak': 2},
    {'name': 'DiamondHands', 'wins': 777, 'streak': 0},
    {'name': 'SpadeInvader', 'wins': 650, 'streak': 1},
    {'name': 'HeartBreaker', 'wins': 599, 'streak': 5},
    {'name': 'ClubPenguin99', 'wins': 510, 'streak': 0},
    {'name': 'LuckySeven', 'wins': 488, 'streak': 3},
  ];

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // Mock network delay
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_selectedMode.label} Leaderboard'),
      ),
      body: Column(
        children: [
          // Mode category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: LeaderboardMode.values.map((mode) {
                final isSelected = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mode.icon, size: 16, color: isSelected ? Colors.black : Colors.amber),
                        const SizedBox(width: 6),
                        Text(mode.label),
                      ],
                    ),
                    onSelected: (_) => setState(() => _selectedMode = mode),
                    selectedColor: Colors.amber,
                    checkmarkColor: Colors.black,
                  ),
                );
              }).toList(),
            ),
          ),

          // "Your Rank" Banner
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_selectedMode Leaderboard — Your Rank: #47',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                Text(
                  'Wins: 142 • Streak: 3',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: Colors.amber,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _mockPlayers.length,
                      itemBuilder: (context, index) {
                        final player = _mockPlayers[index];
                        final isTop3 = index < 3;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isTop3
                                ? ['#FFD700', '#C0C0C0', '#CD7F32']
                                    .map((c) => Color(
                                        int.parse(c.replaceFirst('#', '0xFF'))))
                                    .toList()[index]
                                : Colors.grey[800],
                            child: Text(
                              '#${index + 1}',
                              style: TextStyle(
                                color: isTop3 ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            player['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Streak: 🔥 ${player['streak']}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${player['wins']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                              const Text('Wins',
                                  style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
