import 'package:flutter/material.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Rules'),
      ),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            const _SectionHeader('Objective'),
            const _BodyText(
                'Be the first player to play all cards in your hand.'),
            const SizedBox(height: 24),
            const _SectionHeader('Setup'),
            const _BulletPoint(
                'Standard 52-card deck plus 2 Jokers (54 cards total)'),
            const _BulletPoint('Cards are shuffled before each game'),
            const _BulletPoint('Each player receives 7 random cards'),
            const _BulletPoint(
                'One card is placed face-up to start the discard pile'),
            const _BulletPoint('Remaining cards form the draw pile'),
            const _BulletPoint(
                'Note: The starting face-up card triggers its special ability immediately if applicable',
                isBold: true),
            const SizedBox(height: 24),
            const _SectionHeader('Turn Structure'),
            const _BodyText(
                'On a player\'s turn, they may play a card if it matches:'),
            const _BulletPoint('The suit of the top discard card, OR'),
            const _BulletPoint('The rank/value of the top discard card, OR'),
            const _BulletPoint('A valid special override (Ace, Joker, etc.)'),
            const SizedBox(height: 12),
            const _BodyText('If a player cannot play:'),
            const _BulletPoint('They must draw 1 card'),
            const _BulletPoint('Their turn ends immediately'),
            const _BulletPoint(
                'The drawn card cannot be played on that same turn, even if it would be a valid play'),
            const SizedBox(height: 24),
            const _SectionHeader('Multi-Card Play — Same-Value Stacking'),
            const _BodyText(
                'A player may play multiple cards of the same value in a single turn.'),
            const _BodyText(
                'Example: If 4♣ is on top, the player may play 4♦ + 4♠ + 4♥ all at once.',
                isItalic: true),
            const SizedBox(height: 24),
            const _SectionHeader('Numerical Flow Rule (Core Mechanic)'),
            const _BodyText(
                'Players may build a numerical sequence ascending or descending, but only within the same suit.'),
            const _BodyText(
                'Example: If A♥ is on top, the player may play 2♥ → 3♥ → 4♥.',
                isItalic: true),
            const SizedBox(height: 8),
            const _BodyText(
                'Once the sequence ends, if the final card matches another card in value (regardless of suit), it may be played to continue the turn.'),
            const _BodyText(
                'Example: Sequence ends at 4♥ → player may then play 4♣.',
                isItalic: true),
            const SizedBox(height: 8),
            const _BodyText(
                'After that cross-suit value match, normal matching rules apply.'),
            const SizedBox(height: 24),
            const _SectionHeader('Special Cards'),
            const _CardTable(),
            const SizedBox(height: 24),
            const _SectionHeader('Penalty Resolution Order'),
            const _BodyText(
                'When multiple effects are active simultaneously, they resolve in this order:'),
            const _NumberedPoint('1. Draw penalties (2s / Black Jacks)'),
            const _NumberedPoint('2. Skip (8)'),
            const _NumberedPoint('3. Reverse (King)'),
            const _NumberedPoint('4. Suit lock (Queen)'),
            const SizedBox(height: 24),
            const _SectionHeader('Edge Cases'),
            const _BulletPoint(
                'If the starting card is a special card, its effect triggers immediately'),
            const _BulletPoint(
                'If the draw pile is empty, reshuffle the discard pile (excluding the top card) to form a new draw pile'),
            const _BulletPoint(
                'A player cannot win on a forced penalty draw unless a rule explicitly permits it'),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.amber,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  final bool isItalic;
  const _BodyText(this.text, {this.isItalic = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          color: isItalic ? Colors.white70 : Colors.white,
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  final bool isBold;
  const _BulletPoint(this.text, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(fontSize: 16, height: 1.5, color: Colors.amber)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedPoint extends StatelessWidget {
  final String text;
  const _NumberedPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, height: 1.5),
      ),
    );
  }
}

class _CardTable extends StatelessWidget {
  const _CardTable();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        border: TableBorder.symmetric(
            inside: const BorderSide(color: Colors.white24)),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(2.5),
        },
        children: [
          _buildTableRow('Card', 'Effect', isHeader: true),
          _buildTableRow('2 (All Suits)',
              'Next player draws 2 cards. May be stacked with another 2 to pass the penalty. Penalty accumulates (2 → 4 → 6…).'),
          _buildTableRow('Black Jack (♠/♣)',
              'Next player draws 5 cards. May be stacked with another Black Jack. Can also stack onto an active 2-chain.'),
          _buildTableRow('Red Jack (♥/♦)',
              'Cancels any active draw penalty. Resets the draw stack to 0.'),
          _buildTableRow('King', 'Reverses the direction of play.'),
          _buildTableRow('Ace',
              'Player changes the active suit. Player declares the new suit upon playing.'),
          _buildTableRow('Queen',
              'Next player must follow the same suit. Cannot change suit or match by number. Must be covered with the same suit.'),
          _buildTableRow('8', 'Next player misses their turn (skip).'),
          _buildTableRow('Joker',
              'Wild card. Player declares both the suit and rank. Treated as that card until replaced.'),
        ],
      ),
    );
  }

  TableRow _buildTableRow(String card, String effect, {bool isHeader = false}) {
    final style = TextStyle(
      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
      color: isHeader ? Colors.amber : Colors.white,
      fontSize: 15,
    );

    return TableRow(
      decoration: isHeader
          ? BoxDecoration(color: Colors.white.withOpacity(0.05))
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(card, style: style),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(effect, style: style),
        ),
      ],
    );
  }
}
