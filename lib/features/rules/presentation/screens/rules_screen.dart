import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/card_model.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../gameplay/presentation/widgets/card_widget.dart';

/// Section keys, in reading order — also drives the quick-nav chip row.
enum _RuleSection {
  objective('Objective'),
  setup('Setup'),
  yourTurn('Your Turn'),
  multiPlay('Multiple Cards'),
  specialCards('Special Cards'),
  lastCards('Last Cards'),
  gameModes('Game Modes'),
  edgeCases('Edge Cases');

  const _RuleSection(this.label);
  final String label;
}

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  final Map<_RuleSection, GlobalKey> _sectionKeys = {
    for (final s in _RuleSection.values) s: GlobalKey(),
  };

  void _jumpTo(_RuleSection section) {
    final ctx = _sectionKeys[section]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  TextStyle _headingStyle(AppThemeData theme, {required double size}) {
    final style = theme.headingFontFamily == 'cinzel'
        ? GoogleFonts.cinzel(
            fontSize: size,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: theme.accentPrimary,
          )
        : GoogleFonts.playfairDisplay(
            fontSize: size,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: theme.accentPrimary,
          );
    return style;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    const sectionSpacing = SizedBox(height: 22);

    Widget section(_RuleSection key, Widget child) {
      return KeyedSubtree(
        key: _sectionKeys[key],
        child: child,
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundMid,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('RULES', style: _headingStyle(theme, size: 15)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _QuickNavRow(theme: theme, onTap: _jumpTo),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      section(
                        _RuleSection.objective,
                        _SectionHeader('OBJECTIVE', theme: theme),
                      ),
                      _BodyText(
                        'Be the first player to play every card in your hand.',
                        theme: theme,
                      ),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.setup,
                        _SectionHeader('SETUP', theme: theme),
                      ),
                      _BulletPoint('52 cards plus 2 Jokers — 54 cards total', theme: theme),
                      _BulletPoint('2–7 players; everyone starts with 7 cards', theme: theme),
                      _BulletPoint('One card is flipped face-up to start the discard pile', theme: theme),
                      _BulletPoint('The rest form the draw pile', theme: theme),
                      _BulletPoint('If that starting card is a special card, its effect fires immediately', theme: theme),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.yourTurn,
                        _SectionHeader('YOUR TURN', theme: theme),
                      ),
                      _BodyText(
                        "Play a card that matches the top discard card's suit or rank — "
                        'or use a special card\'s power instead (see below).',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "Can't play anything? Draw one card and your turn ends — "
                        "you can't play that card the same turn.",
                        theme: theme,
                      ),
                      _BulletPoint(
                        '60 seconds per turn (30 seconds in Ranked Hardcore). Run out '
                        'the clock and you auto-draw and lose the turn.',
                        theme: theme,
                      ),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.multiPlay,
                        _SectionHeader('PLAYING MULTIPLE CARDS', theme: theme),
                      ),
                      _BulletPoint(
                        'Play several cards of the same rank together — e.g. two 7s at once.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Or build a run: consecutive ranks, same suit, ascending or '
                        'descending — e.g. 4♠ 5♠ 6♠.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'After a run, you can switch suits by matching the rank of your '
                        'last card.',
                        theme: theme,
                      ),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.specialCards,
                        _SectionHeader('SPECIAL CARDS', theme: theme),
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_2', rank: Rank.two, suit: Suit.hearts),
                        name: '2',
                        description:
                            'Next player draws 2. Stack more 2s to pile it higher — once a '
                            'penalty chain is live, any 2 lands on any other penalty card, '
                            'no matching needed.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_bj', rank: Rank.jack, suit: Suit.spades),
                        name: 'Black Jack',
                        description:
                            'Next player draws 5. Stacks the same way as a 2, including on '
                            'top of an active 2-chain.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_rj', rank: Rank.jack, suit: Suit.hearts),
                        name: 'Red Jack',
                        description:
                            'Wipes the entire draw penalty back to zero. The chain stays '
                            'open, so 2s and Jacks can still land on it without matching.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_k', rank: Rank.king, suit: Suit.diamonds),
                        name: 'King',
                        description:
                            'Reverses the direction of play. In a 2-player game that means '
                            "it comes right back to you — but your next card still has to "
                            "match the King normally, it doesn't chain like a numeric run. "
                            'Play a second King right after the first (same turn) and the '
                            'reversal cancels out — direction stays the same, and you can '
                            'follow up with any card matching that second King\'s suit.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_a', rank: Rank.ace, suit: Suit.clubs),
                        name: 'Ace',
                        description: 'Change the active suit to anything you like.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_q', rank: Rank.queen, suit: Suit.spades),
                        name: 'Queen',
                        description:
                            'Locks the suit — the next player must follow it exactly, no '
                            'rank shortcut.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_8', rank: Rank.eight, suit: Suit.hearts),
                        name: '8',
                        description:
                            "Skips the next player's turn. Skips stack — play more than "
                            'one 8 in the same turn and each extra one skips another '
                            'player further round the table, potentially missing several '
                            'players at once.',
                      ),
                      _SpecialCardEntry(
                        theme: theme,
                        card: CardModel(id: 'r_j', rank: Rank.joker, suit: Suit.spades),
                        name: 'Joker',
                        description: 'Full wild — declare it as any rank and suit you want.',
                      ),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.lastCards,
                        _SectionHeader('LAST CARDS', theme: theme),
                      ),
                      _BodyText(
                        'Only matters once your hand is down to something you could clear '
                        'in a single turn.',
                        theme: theme,
                      ),
                      _ImportantCallout(
                        "If that's true for you, tap Last Cards before your turn starts. "
                        "Forget, then clear your hand anyway? You don't win — you draw 1 "
                        'card instead and play continues.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "Declared, but it turns out you couldn't actually clear your hand? "
                        'That\'s a bluff — draw 2 penalty cards.',
                        theme: theme,
                      ),
                      _BulletPoint('Holding a Joker keeps you safe from the bluff penalty.', theme: theme),
                      _BulletPoint(
                        "Declarations are public — everyone at the table can see who's "
                        'declared.',
                        theme: theme,
                      ),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.gameModes,
                        _SectionHeader('GAME MODES', theme: theme),
                      ),
                      _BulletPoint('Play with AI — offline, all core rules above.', theme: theme),
                      _BulletPoint("Practice — same as AI, doesn't affect any leaderboard.", theme: theme),
                      _BulletPoint('Play Online — join a lobby or room, same core rules.', theme: theme),
                      _BulletPoint(
                        'Ranked — signed-in matchmaking, standard rules, 60s turns; '
                        'affects MMR and the Ranked leaderboard.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Ranked (Hardcore) — same matchmaking, stricter finish rules '
                        '(below), 30s turns, its own separate MMR and leaderboard.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "Disconnects: a player who disconnects is removed — no rejoining. "
                        "Their cards shuffle into the draw pile, unless it would drop the "
                        'table to one player, which ends the match.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Casual online wins can still count toward the leaderboard, as '
                        'long as the match is trophy-eligible.',
                        theme: theme,
                      ),
                      const SizedBox(height: 14),

                      _SubHeader('Hardcore Mode', theme: theme),
                      _BodyText('Same core rules, with a tighter finish:', theme: theme),
                      _BulletPoint(
                        "You can't win by playing an Ace as your last card (including a "
                        'Joker declared as one).',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "You can't finish on a Joker at all — you need a non-Joker to go "
                        'out.',
                        theme: theme,
                      ),
                      _BulletPoint('30-second turn timer.', theme: theme),
                      _BulletPoint('Its own separate ranked ladder.', theme: theme),
                      const SizedBox(height: 14),

                      _SubHeader('Tournament Mode', theme: theme),
                      _BulletPoint('All core rules apply within each round.', theme: theme),
                      _BulletPoint('Players finish in the order they empty their hands.', theme: theme),
                      _BulletPoint('Whoever finishes last in the round is eliminated.', theme: theme),
                      _BulletPoint('Everyone else advances to the next round.', theme: theme),
                      _BulletPoint(
                        'Keeps going until one player remains — the tournament winner.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "Offline: once you've qualified, Skip to result fast-forwards the "
                        'rest of the round.',
                        theme: theme,
                      ),
                      const SizedBox(height: 14),

                      _SubHeader('Bust Mode', theme: theme),
                      _BulletPoint('52 cards, no Jokers. 2–10 players.', theme: theme),
                      _BulletPoint('Hand size adjusts to how many are playing.', theme: theme),
                      _BulletPoint('With 3+ players, everyone gets 2 turns per round.', theme: theme),
                      _BulletPoint(
                        "Down to the final 2? No turn cap — it's a straight race to empty "
                        'your hand.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Card totals at round end add to your running penalty score; the '
                        'two highest scores are eliminated each round (in the final 2, '
                        "it's simply empty-hand-wins).",
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Placement pile: once 5 cards are showing on the discard, the '
                        'bottom 4 shuffle back into the draw pile.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        'Online: with 3+ players left, a disconnect just removes that '
                        'player; drop to 2 or fewer and the match ends.',
                        theme: theme,
                      ),
                      _BulletPoint('Last player standing wins.', theme: theme),
                      _SectionDivider(theme: theme),
                      sectionSpacing,

                      section(
                        _RuleSection.edgeCases,
                        _SectionHeader('EDGE CASES', theme: theme),
                      ),
                      _BulletPoint(
                        'Draw pile empty? The discard pile (except the top card) '
                        'reshuffles into a new one.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "You can't win off a forced penalty draw unless a rule "
                        'specifically says you can.',
                        theme: theme,
                      ),
                      _BulletPoint(
                        "Playing a Queen as your last card doesn't win on its own — you "
                        'still need to cover it or draw; if you can\'t cover it, you draw '
                        'and the game continues.',
                        theme: theme,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick nav ──────────────────────────────────────────────────────────────────

class _QuickNavRow extends StatelessWidget {
  const _QuickNavRow({required this.theme, required this.onTap});

  final AppThemeData theme;
  final void Function(_RuleSection section) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.backgroundMid,
        border: Border(
          bottom: BorderSide(color: theme.accentPrimary.withValues(alpha: 0.2)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _RuleSection.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final section = _RuleSection.values[i];
          return _NavChip(
            label: section.label,
            theme: theme,
            onTap: () => onTap(section),
          );
        },
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({required this.label, required this.theme, required this.onTap});

  final String label;
  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfacePanel,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.45)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: theme.accentPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section building blocks (theme-aware) ───────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.theme});

  final String title;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final family = theme.headingFontFamily == 'cinzel' ? 'Cinzel' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: theme.accentPrimary,
          letterSpacing: 2,
          fontFamily: family,
        ),
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.title, {required this.theme});

  final String title;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: theme.textPrimary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text, {required this.theme});

  final String text;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, height: 1.6, color: theme.textPrimary),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text, {required this.theme});

  final String text;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontSize: 13, height: 1.6, color: theme.textPrimary)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.6, color: theme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A special card entry with a real mini card render alongside its rules text.
class _SpecialCardEntry extends StatelessWidget {
  const _SpecialCardEntry({
    required this.theme,
    required this.card,
    required this.name,
    required this.description,
  });

  final AppThemeData theme;
  final CardModel card;
  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardWidget(card: card, width: 40, faceUp: true, animateFlip: false),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: theme.textPrimary, fontSize: 13, height: 1.55),
                  children: [
                    TextSpan(
                      text: name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.accentPrimary,
                      ),
                    ),
                    const TextSpan(text: ' — '),
                    TextSpan(text: description),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportantCallout extends StatelessWidget {
  const _ImportantCallout(this.text, {required this.theme});

  final String text;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0, top: 2.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accentPrimary.withValues(alpha: 0.13),
          border: Border(
            left: BorderSide(color: theme.accentPrimary, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            text,
            style: TextStyle(
              color: theme.textPrimary,
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
  const _SectionDivider({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Divider(
        thickness: 1,
        height: 1,
        color: theme.accentPrimary.withValues(alpha: 0.4),
      ),
    );
  }
}
