import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import 'basic_play_slides.dart';
import 'special_card_slides.dart';
import 'tutorial_slide.dart';

class _BookendIcon extends ConsumerWidget {
  const _BookendIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Icon(icon, size: 96, color: theme.accentPrimary.withValues(alpha: 0.85));
  }
}

/// The full ordered slide list — a welcome bookend, the basic-play and
/// special-card demos, and a closing bookend with the "read the full
/// rules" / "start playing" call to action.
final List<TutorialSlide> tutorialSlides = [
  TutorialSlide(
    title: 'How to play',
    captionLines: const ['A quick visual tour of the special cards.'],
    demoBuilder: (context) => const _BookendIcon(Icons.style_rounded),
  ),
  TutorialSlide(
    title: 'Your turn',
    captionLines: const ["Match the top card's suit or rank — or play a special card."],
    demoBuilder: (context) => const YourTurnDemo(),
  ),
  TutorialSlide(
    title: "Can't play?",
    captionLines: const ["Draw one card and your turn ends — you can't play it this turn."],
    demoBuilder: (context) => const DrawCardDemo(),
  ),
  TutorialSlide(
    title: 'Playing multiple cards',
    captionLines: const ['Play same-rank pairs together, or build a same-suit run.'],
    demoBuilder: (context) => const MultiCardDemo(),
  ),
  TutorialSlide(
    title: '2',
    captionLines: const ['Next player draws 2 — stack more 2s to raise the pile.'],
    demoBuilder: (context) => const TwoCardDemo(),
  ),
  TutorialSlide(
    title: 'Black Jack',
    captionLines: const ['Draws 5, and stacks on an active 2-chain too.'],
    demoBuilder: (context) => const BlackJackDemo(),
  ),
  TutorialSlide(
    title: 'Red Jack',
    captionLines: const [
      'Wipes the whole draw penalty back to zero.',
      'The chain stays open — 2s and Jacks can still land on it.',
    ],
    demoBuilder: (context) => const RedJackDemo(),
  ),
  TutorialSlide(
    title: 'King',
    captionLines: const [
      'Reverses the direction of play.',
      'Play two Kings in a row and the reversal cancels out.',
      'You can then play any card matching that King\'s suit — not just an adjacent rank.',
    ],
    demoBuilder: (context) => const KingDemo(),
  ),
  TutorialSlide(
    title: 'Ace',
    captionLines: const ['Change the active suit to anything you like.'],
    demoBuilder: (context) => const AceDemo(),
  ),
  TutorialSlide(
    title: 'Queen',
    captionLines: const [
      'Locks the suit on you, not the next player.',
      'Play another card of that suit (or another Queen) before your turn ends, or draw to end it.',
    ],
    demoBuilder: (context) => const QueenDemo(),
  ),
  TutorialSlide(
    title: '8',
    captionLines: const ['Skips the next player. Stack more 8s to skip further.'],
    demoBuilder: (context) => const EightDemo(),
  ),
  TutorialSlide(
    title: 'Joker',
    captionLines: const ['Full wild — declare it as any rank and suit you like.'],
    demoBuilder: (context) => const JokerDemo(),
  ),
  TutorialSlide(
    title: 'Last Cards',
    captionLines: const [
      'Declare before your turn once you can clear your hand in one play.',
      "Guess wrong and you draw 2 as a bluff penalty — unless you're holding a Joker.",
    ],
    demoBuilder: (context) => const LastCardsDemo(),
  ),
  TutorialSlide(
    title: 'Ready to play',
    captionLines: const ["That's every special card — you're ready for the table."],
    demoBuilder: (context) => const _BookendIcon(Icons.check_circle_rounded),
  ),
];
