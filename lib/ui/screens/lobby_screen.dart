import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// Room entry screen — players enter a room code, see the player list,
/// and mark themselves ready before the host starts the game.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
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
    return Scaffold(
      backgroundColor: AppColors.feltDeep,
      body: Stack(
        children: [
          // Felt vignette background
          const _FeltBackground(),

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
                        style: AppTypography.gameTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.xs),
                      Text(
                        'Premium Competitive Card Game',
                        style: AppTypography.labelSmall,
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: AppDimensions.xxl),

                      // Player name
                      _GoldTextField(
                        controller: _nameController,
                        label: 'Your Name',
                        hintText: 'Enter display name',
                      ),

                      const SizedBox(height: AppDimensions.md),

                      // Room code
                      _GoldTextField(
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
                      const _Divider(),
                      const SizedBox(height: AppDimensions.lg),

                      // Lobby player list placeholder
                      _LobbyPlayerList(isReady: _isReady),

                      const SizedBox(height: AppDimensions.lg),

                      // Ready toggle
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _toggleReady,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isReady
                                ? AppColors.redAccent
                                : AppColors.goldPrimary,
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
    Navigator.of(context).pushNamed('/game');
  }

  void _onCreate() {
    // TODO: ws connect + create room action
    Navigator.of(context).pushNamed('/game');
  }

  void _toggleReady() {
    setState(() => _isReady = !_isReady);
    // TODO: send ready action via ws
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _GoldTextField extends StatelessWidget {
  const _GoldTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall),
        const SizedBox(height: AppDimensions.xs),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          style: AppTypography.labelLarge,
          cursorColor: AppColors.goldPrimary,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTypography.labelLarge.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.feltMid,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.md,
              vertical: AppDimensions.sm + 4,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide: const BorderSide(color: AppColors.goldDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide:
                  const BorderSide(color: AppColors.goldPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
            child: Divider(color: AppColors.goldDark, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
          child: Text('LOBBY', style: AppTypography.labelSmall),
        ),
        const Expanded(
            child: Divider(color: AppColors.goldDark, thickness: 0.5)),
      ],
    );
  }
}

class _LobbyPlayerList extends StatelessWidget {
  const _LobbyPlayerList({required this.isReady});
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    // Placeholder entries until ws connection provides real players
    final players = [
      _PlayerEntry(name: 'You', isReady: isReady),
      _PlayerEntry(name: 'Waiting...', isReady: false, isPlaceholder: true),
      _PlayerEntry(name: 'Waiting...', isReady: false, isPlaceholder: true),
    ];

    return Column(
      children: [
        for (int i = 0; i < players.length; i++) ...[
          players[i],
          if (i < players.length - 1)
            const Divider(height: 1, color: AppColors.goldDark, thickness: 0.3),
        ],
      ],
    );
  }
}

// ── Felt table background ─────────────────────────────────────────────────────

class _FeltBackground extends StatelessWidget {
  const _FeltBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _LobbyFeltPainter()),
    );
  }
}

class _LobbyFeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.feltDeep,
    );

    // Subtle dot-grid micro-texture
    final dotPaint = Paint()
      ..color = AppColors.feltMid.withValues(alpha: 0.07)
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
  bool shouldRepaint(_LobbyFeltPainter _) => false;
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    required this.name,
    required this.isReady,
    this.isPlaceholder = false,
  });

  final String name;
  final bool isReady;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaceholder
                  ? AppColors.goldDark
                  : isReady
                      ? const Color(0xFF27AE60)
                      : AppColors.goldPrimary,
            ),
          ),
          const SizedBox(width: AppDimensions.sm),
          Text(
            name,
            style: AppTypography.labelMedium.copyWith(
              color: isPlaceholder
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (!isPlaceholder)
            Text(
              isReady ? 'READY' : 'NOT READY',
              style: AppTypography.labelSmall.copyWith(
                color: isReady ? const Color(0xFF27AE60) : AppColors.redSoft,
              ),
            ),
        ],
      ),
    );
  }
}
