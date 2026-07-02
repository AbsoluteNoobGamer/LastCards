import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/card_back_service.dart';

/// "Effects" tab — cosmetic rendering toggles. This is the single home for
/// `CardBackService.animatedEffectsEnabled`; it no longer has a duplicate
/// switch inside the general Settings sheet.
class LockerEffectsTab extends StatelessWidget {
  const LockerEffectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CardBackService.instance;
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: service.animatedEffectsEnabled,
      builder: (context, enabled, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            SwitchListTile(
              value: enabled,
              onChanged: (value) => service.setAnimatedEffectsEnabled(value),
              title: Text(
                'Animated card effects',
                style: GoogleFonts.dmSans(fontSize: 15, color: colors.onSurface),
              ),
              subtitle: Text(
                'Shimmer, sheen and motion on animated card backs and jokers. '
                'Turn off for a calmer table or to save battery.',
                style: GoogleFonts.dmSans(fontSize: 12.5, color: colors.onSurface.withValues(alpha: 0.6)),
              ),
              activeThumbColor: colors.primary,
            ),
          ],
        );
      },
    );
  }
}
