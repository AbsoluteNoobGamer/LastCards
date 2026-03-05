import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:deck_drop/tournament/tournament_engine.dart';

class TournamentLobbyScreen extends StatelessWidget {
  const TournamentLobbyScreen({
    required this.players,
    required this.isOnline,
    required this.isHost,
    required this.onStartTournament,
    super.key,
  });

  final List<TournamentPlayer> players;
  final bool isOnline;
  final bool isHost;
  final VoidCallback onStartTournament;

  @override
  Widget build(BuildContext context) {
    final slots = List<TournamentPlayer?>.filled(4, null);
    for (var i = 0; i < players.length && i < slots.length; i++) {
      slots[i] = players[i];
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/StackandFlowBackground.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: const Color(0xCC000000)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Tournament Lobby',
                    style: GoogleFonts.cinzel(
                      color: const Color(0xFFFFD700),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isOnline ? 'Online Bracket' : 'Offline Bracket',
                    style: GoogleFonts.cinzel(
                      color: Colors.white70,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _PlayerSlot(player: slots[0], slotNumber: 1),
                              const SizedBox(height: 20),
                              _PlayerSlot(player: slots[1], slotNumber: 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        const _BracketColumn(),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _PlayerSlot(player: slots[2], slotNumber: 3),
                              const SizedBox(height: 20),
                              _PlayerSlot(player: slots[3], slotNumber: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!isOnline || isHost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: players.length >= 2 ? onStartTournament : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: GoogleFonts.cinzel(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            fontSize: 16,
                          ),
                        ),
                        child: const Text('Start Tournament'),
                      ),
                    )
                  else
                    Text(
                      'Waiting for host to start...',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFFFFD700),
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  const _PlayerSlot({
    required this.player,
    required this.slotNumber,
  });

  final TournamentPlayer? player;
  final int slotNumber;

  @override
  Widget build(BuildContext context) {
    final currentPlayer = player;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF1A1A1A),
            child: Text(
              '$slotNumber',
              style: GoogleFonts.cinzel(
                color: const Color(0xFFFFD700),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentPlayer == null
                  ? 'Waiting...'
                  : '${currentPlayer.displayName}${currentPlayer.isAi ? ' (AI)' : ''}',
              style: GoogleFonts.cinzel(
                color: currentPlayer == null ? Colors.white54 : Colors.white,
                fontSize: 16,
                letterSpacing: 0.8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BracketColumn extends StatelessWidget {
  const _BracketColumn();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(height: 1.4, color: const Color(0xFFFFD700)),
            const SizedBox(height: 36),
            Icon(
              Icons.emoji_events_rounded,
              color: const Color(0xFFFFD700).withValues(alpha: 0.85),
              size: 28,
            ),
            const SizedBox(height: 36),
            Container(height: 1.4, color: const Color(0xFFFFD700)),
          ],
        ),
      ),
    );
  }
}
