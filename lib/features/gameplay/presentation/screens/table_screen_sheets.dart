part of 'table_screen.dart';

// Ace suit picker: [AceSuitPickerSheet] (imported in table_screen.dart).

// ── Joker specific role picker ────────────────────────────────────────────────

/// Bottom sheet that lets the player choose exactly which card the Joker will represent.
class _JokerSelectionSheet extends ConsumerWidget {
  const _JokerSelectionSheet({
    required this.options,
    required this.playContext,
    this.activeSequenceSuit,
  });

  final List<CardModel> options;
  final JokerPlayContext playContext;
  final Suit? activeSequenceSuit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final media = MediaQuery.of(context);
    final isMobile = math.min(media.size.width, media.size.height) < AppDimensions.breakpointMobile;
    final optionWidth = (media.size.width * 0.12).clamp(44.0, 64.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.accentDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🃏',
                  style: TextStyle(
                    fontSize: 26,
                  )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Joker Played!',
                    style: TextStyle(
                      color: theme.accentPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    playContext == JokerPlayContext.turnStarter
                        ? 'Turn starter: choose suit/value match'
                        : 'Mid-turn: choose adjacent or same-value card',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: isMobile ? 11 : 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (activeSequenceSuit != null) ...[
            Builder(builder: (context) {
              final sequenceOptions = options.where((c) => c.suit == activeSequenceSuit).toList();
              final otherOptions = options.where((c) => c.suit != activeSequenceSuit).toList();

              if (sequenceOptions.isEmpty) {
                 return _buildOptionsWrap(options, optionWidth, context, isMobile);
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Text(
                     'Sequence Continuations',
                     style: TextStyle(
                       color: theme.accentPrimary,
                       fontSize: isMobile ? 13 : 14,
                       fontWeight: FontWeight.w700,
                     ),
                   ),
                   const SizedBox(height: 12),
                   _buildOptionsWrap(sequenceOptions, optionWidth, context, isMobile),
                   if (otherOptions.isNotEmpty) ...[
                     const SizedBox(height: 24),
                     Text(
                       'Other Options',
                       style: TextStyle(
                         color: theme.textSecondary,
                         fontSize: isMobile ? 12 : 13,
                         fontWeight: FontWeight.w600,
                       ),
                     ),
                     const SizedBox(height: 12),
                     _buildOptionsWrap(otherOptions, optionWidth, context, isMobile),
                   ]
                ],
              );
            }),
          ] else
            _buildOptionsWrap(options, optionWidth, context, isMobile),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOptionsWrap(List<CardModel> cardOptions, double optionWidth, BuildContext context, bool isMobile) {
    return Wrap(
      spacing: isMobile ? 8 : 12,
      runSpacing: isMobile ? 10 : 16,
      alignment: WrapAlignment.center,
      children: cardOptions.map((card) {
        return SizedBox(
          width: optionWidth,
          child: CardWidget(
            card: card,
            isSelected: false,
            onTap: () => Navigator.of(context).pop(card),
          ),
        );
      }).toList(),
    );
  }
}
