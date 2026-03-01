import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TournamentWinnerScreen extends StatefulWidget {
  const TournamentWinnerScreen({
    required this.winnerName,
    required this.onPlayAgain,
    required this.onReturnToMenu,
    super.key,
  });

  final String winnerName;
  final VoidCallback onPlayAgain;
  final VoidCallback onReturnToMenu;

  @override
  State<TournamentWinnerScreen> createState() => _TournamentWinnerScreenState();
}

class _TournamentWinnerScreenState extends State<TournamentWinnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _scale,
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700),
                        size: 120,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tournament Winner',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cinzelDecorative(
                        color: const Color(0xFFFFD700),
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.winnerName,
                      style: GoogleFonts.cinzel(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 280,
                      child: ElevatedButton(
                        onPressed: widget.onPlayAgain,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Play Again',
                          style: GoogleFonts.cinzel(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 280,
                      child: OutlinedButton(
                        onPressed: widget.onReturnToMenu,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFFD700)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Return to Menu',
                          style: GoogleFonts.cinzel(
                            color: const Color(0xFFFFD700),
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
