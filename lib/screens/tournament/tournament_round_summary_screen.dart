import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TournamentRoundSummaryScreen extends StatefulWidget {
  const TournamentRoundSummaryScreen({
    required this.roundNumber,
    required this.advancedPlayerNames,
    required this.eliminatedPlayerName,
    required this.nextRoundPlayerNames,
    required this.onReady,
    this.autoStartSeconds = 30,
    super.key,
  });

  final int roundNumber;
  final List<String> advancedPlayerNames;
  final String eliminatedPlayerName;
  final List<String> nextRoundPlayerNames;
  final VoidCallback onReady;
  final int autoStartSeconds;

  @override
  State<TournamentRoundSummaryScreen> createState() =>
      _TournamentRoundSummaryScreenState();
}

class _TournamentRoundSummaryScreenState
    extends State<TournamentRoundSummaryScreen> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.autoStartSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          widget.onReady();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _remainingSeconds -= 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Round ${widget.roundNumber} Complete',
                    style: GoogleFonts.cinzel(
                      color: const Color(0xFFFFD700),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SummarySection(
                    title: 'Advanced',
                    children: widget.advancedPlayerNames,
                    color: const Color(0xFFFFD700),
                  ),
                  const SizedBox(height: 14),
                  _SummarySection(
                    title: 'Eliminated',
                    children: [widget.eliminatedPlayerName],
                    color: const Color(0xFFE04A4A),
                  ),
                  const SizedBox(height: 14),
                  _SummarySection(
                    title: 'Next Round Matchup',
                    children: widget.nextRoundPlayerNames,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101010),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xAAFFD700)),
                    ),
                    child: Text(
                      'Auto-start in $_remainingSeconds seconds',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFFFFD700),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onReady,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Ready',
                        style: GoogleFonts.cinzel(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
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

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.title,
    required this.children,
    required this.color,
  });

  final String title;
  final List<String> children;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x55FFD700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.cinzel(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in children)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                item,
                style: GoogleFonts.cinzel(color: Colors.white, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }
}
