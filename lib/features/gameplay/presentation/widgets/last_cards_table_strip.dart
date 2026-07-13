import 'package:flutter/material.dart';

import '../../../../core/models/player_model.dart';
import '../../../../core/theme/app_colors.dart';

/// Persistent table-level notice of who has declared Last Cards (non-Bust).
class LastCardsTableStrip extends StatelessWidget {
  const LastCardsTableStrip({
    super.key,
    required this.players,
    required this.lastCardsDeclaredBy,
    this.inline = false,
    this.scale = 1.0,
  });

  final List<PlayerModel> players;
  final Set<String> lastCardsDeclaredBy;

  /// When true, omits screen-fraction [Align] — for key-anchored overlay use.
  final bool inline;

  /// Tablet/desktop scale multiplier (1.0 on phones).
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (lastCardsDeclaredBy.isEmpty) {
      return const SizedBox.shrink();
    }

    final names = <String>[];
    for (final p in players) {
      if (lastCardsDeclaredBy.contains(p.id)) {
        names.add(p.displayName);
      }
    }
    if (names.isEmpty) {
      return const SizedBox.shrink();
    }

    final panel = Container(
      constraints: BoxConstraints(maxWidth: 340 * scale),
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: AppColors.goldDark.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: AppColors.goldLight.withValues(alpha: 0.95),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.goldPrimary.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        'Last cards: ${names.join(' · ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.feltDeep,
          fontSize: 13 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );

    if (inline) {
      return IgnorePointer(child: panel);
    }

    return IgnorePointer(
      child: Transform.translate(
        offset: const Offset(0, 1),
        child: Align(
          alignment: const Alignment(0, 0.31),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: panel,
          ),
        ),
      ),
    );
  }
}
