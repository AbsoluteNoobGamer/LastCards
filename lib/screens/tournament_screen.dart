import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background matches start screen
          Stack(
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
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99000000),
                      Color(0xCC000000),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.emoji_events,
                  color: Color(0xFFFFD700),
                  size: 80,
                ),
                const SizedBox(height: 24),
                Text(
                  "Tournament",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cinzel(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFFD700),
                    letterSpacing: 5.0,
                    shadows: const [
                      Shadow(
                        color: Color(0x60FFD700),
                        blurRadius: 24,
                      ),
                      Shadow(
                        color: Color(0x80000000),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Coming Soon",
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    color: Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
          
          // Back arrow
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
