import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TournamentEliminationScreen extends StatelessWidget {
  const TournamentEliminationScreen({
    required this.roundNumber,
    required this.onSpectate,
    required this.onReturnToMenu,
    super.key,
  });

  final int roundNumber;
  final VoidCallback onSpectate;
  final VoidCallback onReturnToMenu;

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
          Container(color: const Color(0xE6000000)),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cancel_rounded,
                      size: 80,
                      color: Color(0xFFE04A4A),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Eliminated',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFFE04A4A),
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Round $roundNumber',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFFFFD700),
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'You finished last this round.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cinzel(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 280,
                      child: OutlinedButton(
                        onPressed: onSpectate,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFFD700)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Spectate',
                          style: GoogleFonts.cinzel(
                            color: const Color(0xFFFFD700),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 280,
                      child: ElevatedButton(
                        onPressed: onReturnToMenu,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Return to Menu',
                          style: GoogleFonts.cinzel(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
