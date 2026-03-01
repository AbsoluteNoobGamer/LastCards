import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TournamentWaitingScreen extends StatelessWidget {
  const TournamentWaitingScreen({
    required this.finishingPosition,
    required this.liveCardCounts,
    this.onContinue,
    super.key,
  });

  final int finishingPosition;
  final Map<String, int> liveCardCounts;
  final VoidCallback? onContinue;

  String get _positionLabel {
    return switch (finishingPosition) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${finishingPosition}th',
    };
  }

  @override
  Widget build(BuildContext context) {
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
          Container(color: const Color(0xD9000000)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Round Update',
                    style: GoogleFonts.cinzel(
                      color: const Color(0xFFFFD700),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '$_positionLabel - You\'re through!',
                    style: GoogleFonts.cinzel(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Waiting for remaining players to finish...',
                    style: GoogleFonts.cinzel(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 30),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFD700), width: 1.1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live Card Counts',
                            style: GoogleFonts.cinzel(
                              color: const Color(0xFFFFD700),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final entry in liveCardCounts.entries)
                                  _CountTile(
                                    playerName: entry.key,
                                    cardCount: entry.value,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (onContinue != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Continue',
                          style: GoogleFonts.cinzel(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.playerName,
    required this.cardCount,
  });

  final String playerName;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x55FFD700)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                playerName,
                style: GoogleFonts.cinzel(
                  color: Colors.white,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$cardCount cards',
              style: GoogleFonts.cinzel(
                color: const Color(0xFFFFD700),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
