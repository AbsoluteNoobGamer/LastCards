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
                _SectionHeader('LAST CARDS (NOT IN BUST)'),
                _ImportantCallout(
                  'When the rules require you to declare, tapping Last Cards is not optional. '
                  'If your hand could be emptied in one legal turn at the start of your turn and you did not press Last Cards before that turn, playing your last card does not win—you draw 1 and your turn ends. '
                  'False declarations are penalized.',
                ),
                _BulletPoint(
                    'Press Last Cards before your turn when you intend to shed your whole hand in one turn.',
                ),
                _BulletPoint(
                    'The game records at turn start whether your hand was clearable in one turn; you must declare only when that snapshot requires it (you can still win without declaring if you drew into a winning hand).',
                ),
                _BulletPoint(
                    'If you must declare and complete the turn without having declared, you draw 1 instead of winning.',
                ),
                _BulletPoint(
                    'A bluff (hand not actually clearable in one turn): draw 2 penalty cards when your turn starts; declaration clears.',
                ),
                _BulletPoint(
                    'Clearability is from your hand only, independent of the discard top. Must-declare and AI checks use the same rule; Jokers get no AI-only pass.',
                ),
                _BulletPoint(
                    'If you press Last Cards and hold any Joker, you are not flagged as bluffing from the clearability check alone.',
                ),
                _BulletPoint('Declaring is public: everyone sees who declared.'),
                _SectionDivider(),
                sectionSpacing,
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
                _BulletPoint('A valid special override (Ace, Joker, etc.)'),
                _BodyText(
                    'If you cannot play: draw 1 card and your turn ends immediately. The drawn card cannot be played on that same turn.'),
                _BodyText(
                    'Offline / local table: the action bar can show Next: … (who acts after you), accounting for skip, reverse, and 2-player King. Online standard table omits it; Bust uses its own order display.'),
                _BodyText(
                    'Turn timer: in standard games you have 60 seconds per turn. In online Ranked (Hardcore), turns are 30 seconds. If time runs out before you play or draw, the turn ends automatically—you draw (1 card, or the full active penalty count if a draw penalty is stacked).'),
                _SectionDivider(),
                sectionSpacing,
                _SectionHeader('HARDCORE MODE (ONLINE)'),
                _BodyText(
                    'Choose Ranked (Hardcore) in online matchmaking. Same core rules as normal games, plus the restrictions below and a 30 second turn timer. Uses a separate MMR and leaderboard from standard Ranked.',
                ),
                _BulletPoint(
                    'You cannot win on an Ace: your winning play cannot end with an Ace as the last card (including a Joker declared as Ace).',
                ),
                _BulletPoint(
                    'You cannot play a Joker as your last card: if a Joker is the only card left in your hand, you cannot declare it to go out—you must finish with a non-Joker card.',
                ),
                _BulletPoint(
                    '30 second turn timer on the server for each turn (your client shows the same countdown).',
                ),
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
                      'Next player draws 2 cards. Stackable with other 2s (penalty accumulates). While the penalty chain is live, any 2 can be played on another penalty card without matching suit or rank. The chain stays live even after a Red Jack zeros the draw count; it ends when someone draws, a non-penalty play breaks it, or the turn ends after a non-penalty card.',
                ),
                _SpecialCardRow(
                  cardName: 'Black Jack (♠/♣)',
                  description:
                      'Next player draws 5 cards. Stackable, and can stack onto an active 2-chain. While the chain is live, Black Jacks chain with other penalty cards without suit/rank matching; otherwise match the top discard with normal suit or rank rules.',
                ),
                _SpecialCardRow(
                  cardName: 'Red Jack (♥/♦)',
                  description:
                      'Cancels any active draw penalty (resets draw stack to 0). The pick-up chain stays live for matching so you can still play any 2 or Jack on the Red Jack without suit/rank matching until someone draws or a non-penalty card ends the chain.',
                ),
                _BodyText(
                    'Pick-up matching: While the penalty chain is live, 2s and Jacks may chain without suit/rank. The chain stays live after a Red Jack zeros the draw count; it ends when someone draws, a non-penalty play clears it, or the turn advances after a non-penalty card.',
                ),
                _SpecialCardRow(
                  cardName: 'King',
                  description:
                      'Reverses direction. With 2 players the turn returns to you; your next card matches the King with normal suit/rank rules (not forced numerical flow). Ace on that follow-up is not a free suit change—it must match like other cards. With 3+ players, mid-turn flow works as after any non-special card.',
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
                    'Play with AI — Offline vs AI; all core rules above.',
                ),
                _BodyText(
                    'Practice — Same as AI; no leaderboard impact.',
                ),
                _BodyText(
                    'Play Online — Lobby/room flow; same core rules.',
                ),
                _BodyText(
                    'Ranked — Signed-in quick match; MMR and the Ranked leaderboard (standard rules, 60s turns).',
                ),
                _BodyText(
                    'Ranked (Hardcore) — Signed-in quick match in a separate queue; stricter finish rules, 30s turns, separate MMR and leaderboard. See Hardcore Mode (Online) above.',
                ),
                _BulletPoint(
                    'Disconnect: player is removed (no rejoin). With two or more others left, their hand shuffles into the draw pile; if only one player remains, the session ends.',
                ),
                _BulletPoint(
                    'Casual wins can count toward online leaderboards when the match is trophy-eligible (not private); Bust finals similarly for bust leaderboards.',
                ),
                _BodyText('Tournament Mode'),
                _BulletPoint('All core rules apply within each round'),
                _BulletPoint('Players finish in order by emptying their hand'),
                _BulletPoint(
                    'The last finisher in the round is eliminated'),
                _BulletPoint('Remaining players advance to the next round'),
                _BulletPoint(
                    'Continues until one player remains (tournament winner)'),
                _BulletPoint(
                    'Offline: after you qualify (empty hand), Skip to result fast-forwards the rest of the round.',
                ),
                _BodyText('Bust Mode'),
                _BulletPoint('52-card deck (no Jokers); 2–10 players'),
                _BulletPoint(
                    'Hand size depends on player count (adaptive deal).',
                ),
                _BulletPoint(
                    'With 3+ players: each takes 2 turns per round; round ends when everyone has played twice.',
                ),
                _BulletPoint(
                    'Final round (2 players left): race to empty hand—no turn cap; play until someone legally sheds their last card.',
                ),
                _BulletPoint(
                    'Round-end card totals add to cumulative penalty; bottom two by cumulative score are eliminated each round. In the 2-player finale, empty hand wins (not penalty tie-break).',
                ),
                _BulletPoint(
                    'Placement pile: when the discard shows 5 cards, bottom 4 shuffle into the draw pile.',
                ),
                _BulletPoint(
                    'Online: with more than two survivors a disconnect removes that player; if two or fewer survivors would remain, the session ends.',
                ),
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

class _ImportantCallout extends StatelessWidget {
  final String text;
  const _ImportantCallout(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0, top: 2.0),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0x22FFD700),
          border: Border(
            left: BorderSide(color: RulesScreen._gold, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            text,
            style: const TextStyle(
              color: RulesScreen._bodyWhite,
              fontSize: 13,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
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
