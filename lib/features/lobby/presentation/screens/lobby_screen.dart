import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../../screens/tournament_screen.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/theme/app_dimensions.dart';

enum OnlineMode { standard, tournament }

/// Room entry screen — players enter a room code, see the player list,
/// and mark themselves ready before the host starts the game.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    this.onlineMode = OnlineMode.standard,
    super.key,
  });

  final OnlineMode onlineMode;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isReady = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: Stack(
        children: [
          // Theme-aware felt vignette background
          Positioned.fill(child: _FeltBackground(theme: theme)),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo / title
                      Text(
                        'STACK & FLOW',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: theme.accentPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.xs),
                      Text(
                        'Premium Competitive Card Game',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                          color: theme.textSecondary,
                        ),
                      ),

                      const SizedBox(height: AppDimensions.xxl),

                      // Player name
                      _GoldTextField(
                        theme: theme,
                        controller: _nameController,
                        label: 'Your Name',
                        hintText: 'Enter display name',
                      ),

                      const SizedBox(height: AppDimensions.md),

                      // Room code
                      _GoldTextField(
                        theme: theme,
                        controller: _codeController,
                        label: 'Room Code',
                        hintText: 'e.g. XKCD-42',
                        textCapitalization: TextCapitalization.characters,
                      ),

                      const SizedBox(height: AppDimensions.lg),

                      // Join / Create
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _onJoin,
                              child: const Text('JOIN ROOM'),
                            ),
                          ),
                          const SizedBox(width: AppDimensions.md),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _onCreate,
                              child: const Text('CREATE ROOM'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppDimensions.xxl),
                      _Divider(theme: theme),
                      const SizedBox(height: AppDimensions.lg),

                      // Lobby player list placeholder
                      _LobbyPlayerList(isReady: _isReady, theme: theme),

                      const SizedBox(height: AppDimensions.lg),

                      // Ready toggle
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _toggleReady,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isReady
                                ? theme.secondaryAccent
                                : theme.accentPrimary,
                          ),
                          child: Text(_isReady ? 'NOT READY' : 'READY'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onJoin() {
    // TODO: ws connect + join room action
    _enterSelectedMode();
  }

  void _onCreate() {
    // TODO: ws connect + create room action
    _enterSelectedMode();
  }

  void _toggleReady() {
    setState(() => _isReady = !_isReady);
    // TODO: send ready action via ws
  }

  void _enterSelectedMode() {
    final displayName = _nameController.text.trim();
    final effectiveName = displayName.isEmpty ? 'You' : displayName;

    if (widget.onlineMode == OnlineMode.tournament) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TournamentScreen(
            isOnline: true,
            onlineLocalDisplayName: effectiveName,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TableScreen(totalPlayers: 4),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _GoldTextField extends StatelessWidget {
  const _GoldTextField({
    required this.theme,
    required this.controller,
    required this.label,
    required this.hintText,
    this.textCapitalization = TextCapitalization.none,
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: theme.textSecondary,
    );
    final inputStyle = GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: theme.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: AppDimensions.xs),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          style: inputStyle,
          cursorColor: theme.accentPrimary,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: inputStyle.copyWith(
              color: theme.textSecondary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: theme.backgroundMid,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.md,
              vertical: AppDimensions.sm + 4,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide: BorderSide(color: theme.accentDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide: BorderSide(color: theme.accentPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: theme.textSecondary,
    );

    return Row(
      children: [
        Expanded(child: Divider(color: theme.accentDark, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
          child: Text('LOBBY', style: labelStyle),
        ),
        Expanded(child: Divider(color: theme.accentDark, thickness: 0.5)),
      ],
    );
  }
}

class _LobbyPlayerList extends StatelessWidget {
  const _LobbyPlayerList({required this.isReady, required this.theme});

  final bool isReady;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final players = [
      _PlayerEntry(name: 'You', isReady: isReady, theme: theme),
      _PlayerEntry(
          name: 'Waiting...', isReady: false, isPlaceholder: true, theme: theme),
      _PlayerEntry(
          name: 'Waiting...', isReady: false, isPlaceholder: true, theme: theme),
    ];

    return Column(
      children: [
        for (int i = 0; i < players.length; i++) ...[
          players[i],
          if (i < players.length - 1)
            Divider(height: 1, color: theme.accentDark, thickness: 0.3),
        ],
      ],
    );
  }
}

// ── Felt table background ─────────────────────────────────────────────────────

class _FeltBackground extends StatelessWidget {
  const _FeltBackground({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LobbyFeltPainter(
        backgroundDeep: theme.backgroundDeep,
        backgroundMid: theme.backgroundMid,
      ),
    );
  }
}

class _LobbyFeltPainter extends CustomPainter {
  const _LobbyFeltPainter({
    required this.backgroundDeep,
    required this.backgroundMid,
  });

  final Color backgroundDeep;
  final Color backgroundMid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundDeep,
    );

    // Subtle dot-grid micro-texture
    final dotPaint = Paint()
      ..color = backgroundMid.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if (((x ~/ 4) + (y ~/ 4)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
        }
      }
    }

    // Vignette
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
          stops: const [0.4, 1.0],
        ).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );
  }

  @override
  bool shouldRepaint(_LobbyFeltPainter old) =>
      old.backgroundDeep != backgroundDeep ||
      old.backgroundMid != backgroundMid;
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    required this.name,
    required this.isReady,
    required this.theme,
    this.isPlaceholder = false,
  });

  final String name;
  final bool isReady;
  final bool isPlaceholder;
  final AppThemeData theme;

  // Semantic status green — not a brand colour, kept as constant.
  static const Color _readyGreen = Color(0xFF27AE60);

  @override
  Widget build(BuildContext context) {
    final dotColor = isPlaceholder
        ? theme.accentDark
        : isReady
            ? _readyGreen
            : theme.accentPrimary;

    final nameStyle = GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: isPlaceholder ? theme.textSecondary : theme.textPrimary,
    );

    final statusStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: isReady ? _readyGreen : theme.suitRed,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: AppDimensions.sm),
          Text(name, style: nameStyle),
          const Spacer(),
          if (!isPlaceholder)
            Text(
              isReady ? 'READY' : 'NOT READY',
              style: statusStyle,
            ),
        ],
      ),
    );
  }
}
