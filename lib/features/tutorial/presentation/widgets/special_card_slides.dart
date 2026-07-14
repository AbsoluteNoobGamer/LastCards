import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/card_model.dart';
import '../../../../core/providers/theme_provider.dart';
import 'tutorial_demo_primitives.dart';
import 'tutorial_demo_stage.dart';

/// "2" demo — next seat is targeted and draws 2, shown as a pill.
class TwoCardDemo extends ConsumerWidget {
  const TwoCardDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_2_play', rank: Rank.two, suit: Suit.hearts);
    final draw1 = const CardModel(id: 'tut_2_d1', rank: Rank.eight, suit: Suit.clubs);
    final draw2 = const CardModel(id: 'tut_2_d2', rank: Rank.nine, suit: Suit.spades);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.1, 0.45);
        final grey = phaseProgress(t, 0.45, 0.6);
        final d1 = phaseProgress(t, 0.5, 0.75);
        final d2 = phaseProgress(t, 0.6, 0.85);
        final badge = phaseProgress(t, 0.65, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              SeatGreyOut(at: TutorialDemoStage.p2Seat, t: grey),
              FlightCard(card: draw1, from: TutorialDemoStage.drawAnchor, to: TutorialDemoStage.p2Seat, t: d1, width: 26),
              FlightCard(card: draw2, from: TutorialDemoStage.drawAnchor, to: TutorialDemoStage.p2Seat, t: d2, width: 26),
              PopBadge(
                at: TutorialDemoStage.p2Seat + const Offset(-14, 16),
                t: badge,
                color: theme.secondaryAccent,
                child: Text('+2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.backgroundDeep)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Black Jack" demo — draws 5, and can stack on an active 2-chain.
class BlackJackDemo extends ConsumerWidget {
  const BlackJackDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_bj_play', rank: Rank.jack, suit: Suit.spades);
    return LoopingDemo(
      builder: (context, t) {
        final preBadge = phaseProgress(t, 0.05, 0.2);
        final flight = phaseProgress(t, 0.25, 0.6);
        final stackBadge = phaseProgress(t, 0.65, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              SeatGreyOut(at: TutorialDemoStage.p2Seat, t: preBadge),
              PopBadge(
                at: TutorialDemoStage.p2Seat + const Offset(-14, 16),
                t: preBadge,
                color: theme.secondaryAccent,
                child: Text('+2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.backgroundDeep)),
              ),
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              if (stackBadge > 0)
                PopBadge(
                  at: TutorialDemoStage.p2Seat + const Offset(-14, 16),
                  t: stackBadge,
                  color: theme.accentPrimary,
                  child: Text('+7', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.backgroundDeep)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "Red Jack" demo — wipes an active draw penalty back to zero.
class RedJackDemo extends ConsumerWidget {
  const RedJackDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_rj_play', rank: Rank.jack, suit: Suit.hearts);
    return LoopingDemo(
      builder: (context, t) {
        final preBadge = phaseProgress(t, 0.05, 0.2);
        final flight = phaseProgress(t, 0.25, 0.6);
        final clearedBadge = phaseProgress(t, 0.65, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              SeatGreyOut(at: TutorialDemoStage.p2Seat, t: preBadge * (1 - clearedBadge)),
              if (clearedBadge <= 0)
                PopBadge(
                  at: TutorialDemoStage.p2Seat + const Offset(-14, 16),
                  t: preBadge,
                  color: theme.secondaryAccent,
                  child: Text('+6', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.backgroundDeep)),
                ),
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              if (clearedBadge > 0)
                PopBadge(
                  at: TutorialDemoStage.p2Seat + const Offset(-24, 16),
                  t: clearedBadge,
                  color: theme.accentDark,
                  child: Text('Cleared', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: theme.textPrimary)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "King" demo — reverses the direction of play.
class KingDemo extends ConsumerWidget {
  const KingDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_k_play', rank: Rank.king, suit: Suit.diamonds);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.05, 0.35);
        final reverse = phaseProgress(t, 0.35, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              DirectionArrowRing(
                center: const Offset(TutorialDemoStage.width / 2, TutorialDemoStage.height / 2 - 8),
                t: reverse,
                color: theme.accentPrimary,
              ),
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Ace" demo — changes the active suit.
class AceDemo extends ConsumerWidget {
  const AceDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_a_play', rank: Rank.ace, suit: Suit.clubs);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.1, 0.5);
        final badge = phaseProgress(t, 0.55, 0.8);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              PopBadge(
                at: TutorialDemoStage.discardAnchor + const Offset(16, -34),
                t: badge,
                color: theme.suitRed,
                child: const Text('♦ chosen', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Queen" demo — locks the suit for the next player.
class QueenDemo extends ConsumerWidget {
  const QueenDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_q_play', rank: Rank.queen, suit: Suit.spades);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.1, 0.5);
        final badge = phaseProgress(t, 0.55, 0.8);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              PopBadge(
                at: TutorialDemoStage.discardAnchor + const Offset(16, -34),
                t: badge,
                color: theme.accentDark,
                child: Icon(Icons.lock_rounded, size: 13, color: theme.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "8" demo — skips the next player's turn.
class EightDemo extends ConsumerWidget {
  const EightDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final discardTop = const CardModel(id: 'tut_8_top', rank: Rank.seven, suit: Suit.hearts);
    final played = const CardModel(id: 'tut_8_play', rank: Rank.eight, suit: Suit.hearts);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.1, 0.45);
        final arc = phaseProgress(t, 0.45, 0.8);
        final grey = phaseProgress(t, 0.65, 0.85);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              AnchoredCard(card: discardTop, at: TutorialDemoStage.discardAnchor),
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor + const Offset(6, -6),
                t: flight,
              ),
              SkipArc(at: TutorialDemoStage.p2Seat, t: arc, color: theme.accentPrimary),
              SeatGreyOut(at: TutorialDemoStage.p2Seat, t: grey),
            ],
          ),
        );
      },
    );
  }
}

/// "Joker" demo — full wild, declared as any rank and suit.
class JokerDemo extends ConsumerWidget {
  const JokerDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final played = const CardModel(id: 'tut_j_play', rank: Rank.joker, suit: Suit.spades);
    return LoopingDemo(
      builder: (context, t) {
        final flight = phaseProgress(t, 0.1, 0.5);
        final badge = phaseProgress(t, 0.55, 0.8);
        return TutorialDemoStage(
          theme: theme,
          foreground: Stack(
            clipBehavior: Clip.none,
            children: [
              FlightCard(
                card: played,
                from: TutorialDemoStage.handAnchor,
                to: TutorialDemoStage.discardAnchor,
                t: flight,
              ),
              PopBadge(
                at: TutorialDemoStage.discardAnchor + const Offset(10, -34),
                t: badge,
                color: theme.accentPrimary,
                child: Text('Declared: Q♠', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: theme.backgroundDeep)),
              ),
            ],
          ),
        );
      },
    );
  }
}
