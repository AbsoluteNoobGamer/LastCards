part of 'table_screen.dart';

// ── Ace suit picker ───────────────────────────────────────────────────────────

/// Bottom sheet that lets the player choose which suit to lock after playing an Ace.
class _AceSuitPickerSheet extends StatelessWidget {
  const _AceSuitPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2016),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.6),
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
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.goldDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Ace icon + title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('A',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.goldPrimary,
                  )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ace Played!',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Choose the new active suit',
                    style: TextStyle(
                      color: AppColors.goldDark.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Suit buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SuitPickButton(
                  symbol: '♠',
                  label: 'Spades',
                  suit: Suit.spades,
                  isRed: false),
              _SuitPickButton(
                  symbol: '♣', label: 'Clubs', suit: Suit.clubs, isRed: false),
              _SuitPickButton(
                  symbol: '♥', label: 'Hearts', suit: Suit.hearts, isRed: true),
              _SuitPickButton(
                  symbol: '♦',
                  label: 'Diamonds',
                  suit: Suit.diamonds,
                  isRed: true),
            ],
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SuitPickButton extends StatelessWidget {
  const _SuitPickButton({
    required this.symbol,
    required this.label,
    required this.suit,
    required this.isRed,
  });

  final String symbol;
  final String label;
  final Suit suit;
  final bool isRed;

  @override
  Widget build(BuildContext context) {
    final color = isRed ? AppColors.suitRed : AppColors.suitBlack;
    final borderColor = isRed
        ? AppColors.suitRed.withValues(alpha: 0.6)
        : AppColors.goldDark.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(suit),
      child: Container(
        width: 68,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.cardFace,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              symbol,
              style: TextStyle(fontSize: 32, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.85),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Joker specific role picker ────────────────────────────────────────────────

/// Bottom sheet that lets the player choose exactly which card the Joker will represent.
class _JokerSelectionSheet extends StatelessWidget {
  const _JokerSelectionSheet({required this.options});

  final List<CardModel> options;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2016),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.6),
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
              color: AppColors.goldDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🃏',
                  style: TextStyle(
                    fontSize: 28,
                  )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Joker Played!',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Choose the exact card the Joker will become',
                    style: TextStyle(
                      color: AppColors.goldDark.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Build a wrapping grid of PlayingCard visuals
          Wrap(
            spacing: 12,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: options.map((card) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(card),
                child: SizedBox(
                  width: 50,
                  // Wrap PlayingCard in a container to add a slight border on hover/tap
                  child: CardWidget(
                    card: card,
                    isSelected: false,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
