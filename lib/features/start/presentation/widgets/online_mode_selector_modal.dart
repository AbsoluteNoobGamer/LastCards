import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

enum OnlineMode { Standard, Tournament }

class OnlineModeSelectorModal extends StatefulWidget {
  const OnlineModeSelectorModal({
    required this.onSelected,
    super.key,
  });

  final void Function(OnlineMode mode, int expectedPlayers) onSelected;

  @override
  State<OnlineModeSelectorModal> createState() =>
      _OnlineModeSelectorModalState();
}

class _OnlineModeSelectorModalState extends State<OnlineModeSelectorModal> {
  int _selectedPlayers = 4;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 600;
    final sidePadding = isMobile ? 16.0 : 24.0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              sidePadding,
              24,
              sidePadding,
              16 + media.viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '┌─ Online Mode ─┐',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 24),
                _buildPlayerSelector(),
                const SizedBox(height: 16),
                _ModalButton(
                  label: 'Tournament',
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSelected(OnlineMode.Tournament, _selectedPlayers);
                  },
                ),
                const SizedBox(height: 16),
                _ModalButton(
                  label: 'Continue',
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSelected(OnlineMode.Standard, _selectedPlayers);
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Back',
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSelector() {
    return Container(
      width: double.infinity,
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFF8B6500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30FFD700),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              colors: [Color(0xFF2B1700), Color(0xFF1A0E00)],
              radius: 1.5,
            ),
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Row(
            children: [2, 3, 4].map((count) {
              final isSelected = _selectedPlayers == count;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedPlayers = count);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.0),
                      color: isSelected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                          : Colors.transparent,
                      border: isSelected
                          ? Border.all(
                              color: const Color(0xFFFFD700), width: 1.5)
                          : Border.all(color: Colors.transparent, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count Players',
                      style: GoogleFonts.outfit(
                        fontSize: isSelected ? 16 : 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white60,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ModalButton extends StatefulWidget {
  const _ModalButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_ModalButton> createState() => _ModalButtonState();
}

class _ModalButtonState extends State<_ModalButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(scale, scale),
        transformAlignment: Alignment.center,
        width: double.infinity,
        height: 68.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFF8B6500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30FFD700),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                colors: [Color(0xFF2B1700), Color(0xFF1A0E00)],
                radius: 1.5,
              ),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16.0),
                splashColor: const Color(0xFFFFD700).withValues(alpha: 0.3),
                highlightColor: Colors.transparent,
                onTapDown: (_) {
                  HapticFeedback.lightImpact();
                  setState(() => _isPressed = true);
                },
                onTapCancel: () => setState(() => _isPressed = false),
                onTap: () {
                  widget.onTap();
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) setState(() => _isPressed = false);
                  });
                },
                child: Center(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

