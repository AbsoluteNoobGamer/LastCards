import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/tournament_session_provider.dart';
import '../tournament_splash_launcher.dart';

/// Play-again entry: launches opponents splash then the coordinator.
class TournamentLobbyScreen extends ConsumerStatefulWidget {
  const TournamentLobbyScreen({super.key});

  @override
  ConsumerState<TournamentLobbyScreen> createState() =>
      _TournamentLobbyScreenState();
}

class _TournamentLobbyScreenState extends ConsumerState<TournamentLobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = ref.read(tournamentSessionProvider).playerCount ?? 4;
      pushOfflineTournamentWithSplash(
        navigator: Navigator.of(context),
        ref: ref,
        playerCount: count,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: Center(
        child: Text(
          'Preparing tournament…',
          style: GoogleFonts.inter(
            color: theme.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
