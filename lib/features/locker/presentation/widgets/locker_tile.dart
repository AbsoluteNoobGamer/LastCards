import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visual state of a single unlockable item in the Locker.
enum LockerTileState {
  /// Owned and currently selected/equipped.
  selected,

  /// Owned but not currently selected.
  owned,

  /// Not yet unlocked — gated by player level.
  lockedByLevel,

  /// Not yet unlocked — reserved for a future purchasable/premium tier.
  ///
  /// The Locker UI supports this state today so the visual language is
  /// ready when monetization (rewarded ads / IAP) ships; there is no
  /// purchase flow wired up yet, so tapping a premium tile currently just
  /// shows an informational message.
  premiumLocked,
}

/// A single square tile in a Locker grid (card back, joker cover, reaction,
/// etc). Presentation-only — callers decide what happens on tap.
class LockerTile extends StatefulWidget {
  const LockerTile({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
    this.preview,
    this.lockCaption,
    this.priceLabel,
  });

  final String label;
  final LockerTileState state;
  final VoidCallback onTap;

  /// Thumbnail content (image, emoji text, icon...). Falls back to a plain
  /// panel if null.
  final Widget? preview;

  /// e.g. "Level 15" shown under a level-locked tile.
  final String? lockCaption;

  /// e.g. "£1.99" shown under a premium-locked tile.
  final String? priceLabel;

  @override
  State<LockerTile> createState() => _LockerTileState();
}

class _LockerTileState extends State<LockerTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLocked = widget.state == LockerTileState.lockedByLevel ||
        widget.state == LockerTileState.premiumLocked;
    final isSelected = widget.state == LockerTileState.selected;
    final isPremium = widget.state == LockerTileState.premiumLocked;

    final borderColor = isSelected
        ? colors.primary
        : isPremium
            ? colors.error
            : colors.primary.withValues(alpha: 0.25);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1,
            ),
            color: colors.surface.withValues(alpha: 0.4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Opacity(
                    opacity: isLocked ? 0.55 : 1.0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: widget.preview ??
                              ColoredBox(color: colors.surfaceContainerHighest),
                        ),
                        if (isLocked)
                          Icon(
                            isPremium ? Icons.workspace_premium_rounded : Icons.lock_rounded,
                            size: 18,
                            color: isPremium
                                ? colors.error
                                : colors.onSurface.withValues(alpha: 0.6),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: colors.onSurface,
                ),
              ),
              if (isSelected)
                Text(
                  'Selected',
                  style: GoogleFonts.dmSans(
                    fontSize: 9.5,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (widget.lockCaption != null)
                Text(
                  widget.lockCaption!,
                  style: GoogleFonts.dmSans(
                    fontSize: 9.5,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                )
              else if (widget.priceLabel != null)
                Text(
                  widget.priceLabel!,
                  style: GoogleFonts.dmSans(
                    fontSize: 9.5,
                    color: colors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small section header used above each grid ("Owned", "Locked"...).
class LockerSectionLabel extends StatelessWidget {
  const LockerSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
          color: colors.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
