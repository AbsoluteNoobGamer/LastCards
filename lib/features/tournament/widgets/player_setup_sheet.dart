import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/tournament_session_provider.dart';
import 'player_count_sheet.dart';
import 'tournament_type_sheet.dart';

/// Bottom Sheet 2b — Player Setup (Local Multiplayer)
class TournamentPlayerSetupSheet extends ConsumerStatefulWidget {
  const TournamentPlayerSetupSheet({super.key});

  @override
  ConsumerState<TournamentPlayerSetupSheet> createState() =>
      _TournamentPlayerSetupSheetState();
}

class _TournamentPlayerSetupSheetState
    extends ConsumerState<TournamentPlayerSetupSheet> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final names = ref.read(tournamentSessionProvider).playerNames;
    for (int i = 0; i < 4; i++) {
      _controllers.add(TextEditingController(text: names[i]));
      _focusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _validateAndContinue() {
    final names = _controllers.map((c) => c.text.trim()).toList();

    for (int i = 0; i < names.length; i++) {
      if (names[i].isEmpty) {
        names[i] = 'Noob ${i + 1}'; // Fallback if cleared
      } else if (names[i].length > 17) {
        setState(() => _errorMessage = 'Names cannot exceed 17 characters');
        return;
      }
    }

    // Check uniqueness
    final uniqueNames = names.toSet();
    if (uniqueNames.length < names.length) {
      setState(() => _errorMessage = 'All player names must be unique');
      return;
    }

    setState(() => _errorMessage = null);

    // Save and proceed
    ref.read(tournamentSessionProvider.notifier).setPlayerNames(names);
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentPlayerCountSheet(),
    );
  }

  void _goBack() {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentTypeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    // Use padding for keyboard
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: theme.accentPrimary,
                        size: 30,
                      ),
                      onPressed: _goBack,
                      tooltip: 'Back',
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        'Local Multiplayer',
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Name Your Players',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: theme.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Text fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  for (int i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlayerTextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        playerNumber: i + 1,
                      ),
                    ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 8),

            // CTA Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ContinueButton(
                onTap: _validateAndContinue,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _PlayerTextField extends ConsumerWidget {
  const _PlayerTextField({
    required this.controller,
    required this.focusNode,
    required this.playerNumber,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int playerNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      cursorColor: theme.accentPrimary,
      style: GoogleFonts.outfit(
        fontSize: 16,
        color: theme.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      maxLength: 17,
      decoration: InputDecoration(
        counterText: '',
        labelText: 'Player $playerNumber',
        labelStyle: GoogleFonts.inter(
          color: theme.textSecondary,
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: theme.accentPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: theme.backgroundMid,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.accentPrimary,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.accentDark.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends ConsumerWidget {
  const _ContinueButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [theme.accentLight, theme.accentPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.backgroundDeep,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: theme.backgroundDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
