import 'package:flutter/material.dart';

import '../../../../core/models/player_model.dart';
import '../../../../core/theme/app_colors.dart';

/// Persistent table-level notice of who has declared Last Cards (non-Bust).
class LastCardsTableStrip extends StatelessWidget {
  const LastCardsTableStrip({
    super.key,
    required this.players,
    required this.lastCardsDeclaredBy,
  });

  final List<PlayerModel> players;
  final Set<String> lastCardsDeclaredBy;

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

    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.31),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.goldDark.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
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
              style: const TextStyle(
                color: AppColors.feltDeep,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
