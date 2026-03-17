import 'package:flutter/material.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const Color _gold = Color(0xFFFFD700);
  static const Color _goldDivider = Color(0x66FFD700);
  static const Color _bodyWhite = Color(0xFFFFFFFF);
  static const Color _background = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    const sectionSpacing = SizedBox(height: 18);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _bodyWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'RULES',
          style: TextStyle(
            color: _gold,
            fontSize: 14,
            letterSpacing: 2,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader('OBJECTIVE'),
                _BodyText('Be the first player to play all cards in your hand.'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('SETUP'),
                _BulletPoint('Standard 52-card deck plus 2 Jokers (54 cards total)'),
                _BulletPoint('Cards are shuffled before each game'),
                _BulletPoint('2–7 players; each receives 7 random cards'),
                _BulletPoint('One card placed face-up starts the discard pile'),
                _BulletPoint('Remaining cards form the draw pile'),
                _BulletPoint(
                    'If the starting face-up card is a special card, its effect triggers immediately'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('TURN STRUCTURE'),
                _BodyText('On your turn, play a card if it matches:'),
                _BulletPoint('The suit of the top discard card, or'),
                _BulletPoint('The rank of the top discard card, or'),
                _BulletPoint('A valid special override (Ace, Joker)'),
                _BodyText(
                    'If you cannot play: draw 1 card and your turn ends immediately. The drawn card cannot be played on that same turn.'),
                _BodyText(
                    'A 60 second turn timer is active at all times. If no card is played or drawn within 60 seconds, the turn ends automatically and you must draw 1 card as a penalty.'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('MULTI-CARD & SEQUENCE PLAY'),
                _BulletPoint('Play multiple cards of the same value in one turn'),
                _BulletPoint(
                    'Build a numerical sequence ascending or descending in the same suit'),
                _BulletPoint(
                    'After a same-suit sequence ends, continue with a cross-suit card of the same value as the final sequence card'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('SPECIAL CARDS'),
                _SpecialCardRow(
                  cardName: '2 (any suit)',
                  description:
                      'Next player draws 2 cards. Stackable with other 2s (penalty accumulates)',
                ),
                _SpecialCardRow(
                  cardName: 'Black Jack (♠/♣)',
                  description:
                      'Next player draws 5 cards. Stackable, and can stack onto an active 2-chain',
                ),
                _SpecialCardRow(
                  cardName: 'Red Jack (♥/♦)',
                  description:
                      'Cancels any active draw penalty (resets draw stack to 0)',
                ),
                _SpecialCardRow(
                  cardName: 'King',
                  description: 'Reverses direction of play',
                ),
                _SpecialCardRow(
                  cardName: 'Ace',
                  description: 'Change the active suit to any suit',
                ),
                _SpecialCardRow(
                  cardName: 'Queen',
                  description: 'Suit lock; next player must follow that suit (no rank bypass)',
                ),
                _SpecialCardRow(
                  cardName: '8',
                  description: 'Next player is skipped',
                ),
                _SpecialCardRow(
                  cardName: 'Joker',
                  description: 'Wild; declare both suit and rank freely',
                ),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('EFFECT RESOLUTION ORDER'),
                _BodyText('When multiple effects are active, resolve in this order:'),
                _BulletPoint('Draw penalties (2 / Black Jack)'),
                _BulletPoint('Skip (8)'),
                _BulletPoint('Reverse (King)'),
                _BulletPoint('Suit lock (Queen)'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('EDGE CASES'),
                _BulletPoint(
                    'If the draw pile is empty, reshuffle the discard pile (except the top card) into a new draw pile'),
                _BulletPoint(
                    'A player cannot win on a forced penalty draw unless a rule explicitly allows it'),
                _BulletPoint(
                    'Playing a Queen as your last card does not win immediately — you must cover the Queen or draw first; if you cannot cover, you draw and do not win'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('GAME MODES'),
                _BodyText(
                    'Play with AI — Offline game against AI opponents using all core rules'),
                _BodyText(
                    'Play Online — Multiplayer using all core rules via lobby/room flow'),
                _BodyText('Tournament Mode'),
                _BulletPoint('All core rules apply within each round'),
                _BulletPoint('Players finish in order by emptying their hand'),
                _BulletPoint(
                    'The last player to empty their hand each round is eliminated'),
                _BulletPoint('Remaining players advance to the next round'),
                _BulletPoint(
                    'Rounds continue until one player remains (Tournament Winner)'),
                _BodyText('Bust Mode'),
                _BulletPoint('52-card deck (no Jokers); 2–10 players'),
                _BulletPoint(
                    'Variable hand size per player count (e.g. 5–10 cards each)'),
                _BulletPoint('2 turns per player per round; round ends when all have played twice'),
                _BulletPoint(
                    'Cards left in hand = penalty points; bottom 2 eliminated each round'),
                _BulletPoint(
                    'Placement pile rule: when discard reaches 5 cards, bottom 4 shuffle back into draw pile'),
                _BulletPoint('Last player standing wins'),
                SizedBox(height: 16),
              ],
            ),
          ),
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
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: RulesScreen._gold,
          letterSpacing: 2,
          fontFamily: 'Cinzel',
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.6,
          color: RulesScreen._bodyWhite,
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: RulesScreen._bodyWhite,
              )),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: RulesScreen._bodyWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialCardRow extends StatelessWidget {
  final String cardName;
  final String description;
  const _SpecialCardRow({required this.cardName, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: RulesScreen._bodyWhite,
            fontSize: 13,
            height: 1.6,
          ),
          children: [
            TextSpan(
              text: cardName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' — '),
            TextSpan(
              text: description,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Divider(
        thickness: 1,
        height: 1,
        color: RulesScreen._goldDivider,
      ),
    );
  }
}
