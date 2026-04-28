import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/reaction_wheel_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/player_level_service.dart';
import '../../shared/reactions/reaction_catalog.dart';

/// Bottom sheet: swap each starter-row slot to any unlocked catalogue reaction.
void showReactionWheelCustomizeSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const ReactionWheelCustomizeSheet(),
  );
}

class ReactionWheelCustomizeSheet extends ConsumerStatefulWidget {
  const ReactionWheelCustomizeSheet({super.key});

  @override
  ConsumerState<ReactionWheelCustomizeSheet> createState() =>
      _ReactionWheelCustomizeSheetState();
}

class _ReactionWheelCustomizeSheetState
    extends ConsumerState<ReactionWheelCustomizeSheet> {
  int? _selectedSlot;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final wheel = ref.watch(reactionWheelProvider);
    final level = PlayerLevelService.instance.currentLevel.value;
    final media = MediaQuery.of(context);

    final unlocked = unlockedReactionIndicesForLevel(level);

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reaction wheel',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Tap a slot, then tap an unlocked reaction to equip. '
                          'Higher levels unlock extras (shown locked until earned).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (var s = 0; s < wheel.length; s++) ...[
                          if (s > 0) const SizedBox(width: 8),
                          _WheelSlotChip(
                            slotIndex: s,
                            reactionId: wheel[s],
                            selected: _selectedSlot == s,
                            onTap: () =>
                                setState(() => _selectedSlot = _selectedSlot == s ? null : s),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 24, color: Colors.white24),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: kReactionDefinitions.length,
                      itemBuilder: (context, i) {
                        final def = kReactionDefinitions[i];
                        final has = unlocked.contains(i);
                        final selectedSlot = _selectedSlot;
                        final assignSlot = selectedSlot;

                        Widget inner;
                        if (def.kind == ReactionVisualKind.gifAsset &&
                            def.gifAssetPath != null) {
                          inner = ClipOval(
                            child: Image.asset(
                              def.gifAssetPath!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          );
                        } else if (def.unicodeLabel != null) {
                          inner = Center(
                            child: Text(
                              def.unicodeLabel!,
                              style: const TextStyle(fontSize: 32),
                            ),
                          );
                        } else {
                          inner = const SizedBox.expand();
                        }

                        final levelLabel =
                            def.minUnlockLevel <= 1 ? '' : 'Lv ${def.minUnlockLevel}';

                        return Material(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: !has
                                ? null
                                : () {
                                    final slot = assignSlot;
                                    if (slot == null) return;
                                    ref.read(reactionWheelProvider.notifier).setSlot(slot, i);
                                    setState(() {});
                                  },
                            child: Stack(
                              children: [
                                Opacity(opacity: has ? 1 : 0.35, child: inner),
                                if (!has)
                                  const Positioned.fill(
                                    child: Icon(Icons.lock, color: Colors.white54),
                                  ),
                                if (levelLabel.isNotEmpty)
                                  Positioned(
                                    bottom: 4,
                                    right: 6,
                                    child: Text(
                                      levelLabel,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: theme.accentPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          ref.read(reactionWheelProvider.notifier).restoreDefaults();
                          setState(() {});
                        },
                        child: Text(
                          'Reset to defaults',
                          style: TextStyle(color: theme.accentPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WheelSlotChip extends ConsumerWidget {
  const _WheelSlotChip({
    required this.slotIndex,
    required this.reactionId,
    required this.selected,
    required this.onTap,
  });

  final int slotIndex;
  final int reactionId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = kReactionDefinitions[reactionId.clamp(0, kReactionCatalogLength - 1)];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 58,
        height: 56,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? ref.watch(themeProvider).theme.accentPrimary
                : Colors.white38,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '#${slotIndex + 1}',
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
            Expanded(
              child: def.kind == ReactionVisualKind.gifAsset &&
                      def.gifAssetPath != null
                  ? ClipOval(child: Image.asset(def.gifAssetPath!, fit: BoxFit.cover))
                  : Text(
                      def.unicodeLabel ?? '',
                      style: const TextStyle(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
