import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/card_model.dart';
import '../../../../core/providers/theme_provider.dart';
import 'tutorial_demo_primitives.dart';
import 'tutorial_demo_stage.dart';

/// "Your turn" demo — a card flies from hand to discard matching the top
/// card's rank.
class YourTurnDemo extends ConsumerWidget {
  const YourTurnDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final discardTop = const CardModel(id: 'tut_yt_top', rank: Rank.seven, suit: Suit.diamonds);
    final playedCard = const CardModel(id: 'tut_yt_play', rank: Rank.seven, suit: Suit.clubs);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.15, 0.65);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              AnchoredCard(card: discardTop, at: TutorialDemoStage.discardAnchor),
              FlightCard(
                card: playedCard,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor + const Offset(6, -6),
                t: flight,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Can't play → draw" demo — a card flies from the draw pile into hand.
class DrawCardDemo extends ConsumerWidget {
  const DrawCardDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final discardTop = const CardModel(id: 'tut_dr_top', rank: Rank.nine, suit: Suit.hearts);
    final drawnCard = const CardModel(id: 'tut_dr_drawn', rank: Rank.three, suit: Suit.spades);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.15, 0.6);
        final badge = phaseProgress(t, 0.65, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              AnchoredCard(card: discardTop, at: TutorialDemoStage.discardAnchor),
              AnchoredCard(card: drawnCard, at: TutorialDemoStage.drawAnchor, faceUp: false),
              FlightCard(
                card: drawnCard,
                from: TutorialDemoStage.drawAnchor,
                to: TutorialDemoStage.handAnchor,
                t: flight,
                faceUp: false,
              ),
              PopBadge(
                at: TutorialDemoStage.youSeat + const Offset(-30, -34),
                t: badge,
                color: theme.accentDark,
                child: Text(
                  'Turn ends',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: theme.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Multiple cards" demo — two same-rank cards played together.
class MultiCardDemo extends ConsumerWidget {
  const MultiCardDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final discardTop = const CardModel(id: 'tut_mc_top', rank: Rank.four, suit: Suit.spades);
    final cardA = const CardModel(id: 'tut_mc_a', rank: Rank.seven, suit: Suit.hearts);
    final cardB = const CardModel(id: 'tut_mc_b', rank: Rank.seven, suit: Suit.diamonds);
    return LoopingDemo(
      builder: (context, t) {
        final flightA = phaseProgress(t, 0.15, 0.55);
        final flightB = phaseProgress(t, 0.3, 0.7);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              AnchoredCard(card: discardTop, at: TutorialDemoStage.discardAnchor),
              FlightCard(
                card: cardA,
                from: TutorialDemoStage.handAnchor + const Offset(-10, 0),
                to: TutorialDemoStage.discardAnchor + const Offset(-2, -8),
                t: flightA,
              ),
              FlightCard(
                card: cardB,
                from: TutorialDemoStage.handAnchor + const Offset(10, 0),
                to: TutorialDemoStage.discardAnchor + const Offset(10, -10),
                t: flightB,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Last Cards" demo — declaring before your hand empties.
class LastCardsDemo extends ConsumerWidget {
  const LastCardsDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final discardTop = const CardModel(id: 'tut_lc_top', rank: Rank.six, suit: Suit.clubs);
    final finalCard = const CardModel(id: 'tut_lc_final', rank: Rank.six, suit: Suit.hearts);
    return LoopingDemo(
      builder: (context, t) {
        final badge = phaseProgress(t, 0.1, 0.4);
        final flight = phaseProgress(t, 0.45, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              AnchoredCard(card: discardTop, at: TutorialDemoStage.discardAnchor),
              PopBadge(
                at: TutorialDemoStage.youSeat + const Offset(-38, -30),
                t: badge,
                color: theme.accentPrimary,
                child: Text(
                  'Last Cards!',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: theme.backgroundDeep),
                ),
              ),
              FlightCard(
                card: finalCard,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor + const Offset(6, -6),
                t: flight,
              ),
            ],
          ),
        );
      },
    );
  }
}
