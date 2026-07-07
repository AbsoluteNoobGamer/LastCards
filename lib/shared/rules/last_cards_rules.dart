import '../models/card_model.dart';
import 'pickup_chain_rules.dart';

/// Max hand size for showing the Last Cards button without Joker / pick-up cards.
const int lastCardsMaxHandSize = 4;

/// Hand-only chain check (no [validatePlay]). Used as a fallback when the
/// hand contains Jokers (mixed plays go through `declare_joker` online).
///
/// Explores single-card orderings; mid-turn flow mirrors [validatePlay].
/// Jokers are explored by trying every rank/suit they could legally declare
/// at that position (mirroring [getValidJokerOptions] in `game_engine.dart`)
/// rather than assumed to bridge to anything — a Joker's declared identity
/// constrains what can legally follow it exactly like a real card would.
/// Without this, e.g. Queen♣ → Joker → Heart-suit-run was wrongly treated as
/// chainable: the Joker can only satisfy a Queen's suit-lock by declaring
/// clubs or another Queen, so whatever comes after it must chain from *that*
/// declared identity, not from an unconstrained wildcard.
///
/// When [discardTop] is provided, the **first** card of the chain is also
/// checked against it (plus [suitLock] / [queenSuitLock] /
/// [isPenaltyChainActive]) — without this, the DFS would report a hand
/// "clearable" as long as its cards chain amongst *themselves*, even if none
/// of them could actually be legally played first against the real discard
/// pile (e.g. a "Guest declared Last Cards" seed firing on turn one for a
/// hand that only chains internally but can't legally open). Pass `null` to
/// skip this (matches the old, unconstrained behaviour).
bool canHandClearInOneTurnHandOnly(
  List<CardModel> hand, {
  CardModel? discardTop,
  Suit? suitLock,
  Suit? queenSuitLock,
  bool isPenaltyChainActive = false,
}) {
  if (hand.isEmpty) return true;
  final cards = List<CardModel>.from(hand);
  return _dfsChain(
    cards,
    null,
    discardTop: discardTop,
    suitLock: suitLock,
    queenSuitLock: queenSuitLock,
    isPenaltyChainActive: isPenaltyChainActive,
  );
}

bool _dfsChain(
  List<CardModel> remaining,
  CardModel? lastPlayed, {
  required CardModel? discardTop,
  required Suit? suitLock,
  required Suit? queenSuitLock,
  required bool isPenaltyChainActive,
}) {
  if (remaining.isEmpty) {
    if (lastPlayed == null) return true;
    return lastPlayed.effectiveRank != Rank.queen;
  }

  for (var i = 0; i < remaining.length; i++) {
    final next = remaining[i];
    final rest = List<CardModel>.from(remaining)..removeAt(i);

    if (next.isJoker) {
      // Try every identity the Joker could legally declare here; recurse as
      // if that declared card were played, so subsequent steps are governed
      // by the declaration, not by an unconstrained "anything goes" wildcard.
      for (final declared in _jokerDeclarationCandidates) {
        final canDeclareHere = lastPlayed == null
            ? _canOpenChain(
                declared,
                discardTop: discardTop,
                suitLock: suitLock,
                queenSuitLock: queenSuitLock,
                isPenaltyChainActive: isPenaltyChainActive,
              )
            : _validChainStep(lastPlayed, declared);
        if (!canDeclareHere) continue;
        if (_dfsChain(rest, declared,
            discardTop: discardTop,
            suitLock: suitLock,
            queenSuitLock: queenSuitLock,
            isPenaltyChainActive: isPenaltyChainActive)) {
          return true;
        }
      }
      continue;
    }

    if (lastPlayed == null) {
      if (!_canOpenChain(
        next,
        discardTop: discardTop,
        suitLock: suitLock,
        queenSuitLock: queenSuitLock,
        isPenaltyChainActive: isPenaltyChainActive,
      )) {
        continue;
      }
      if (_dfsChain(rest, next,
          discardTop: discardTop,
          suitLock: suitLock,
          queenSuitLock: queenSuitLock,
          isPenaltyChainActive: isPenaltyChainActive)) {
        return true;
      }
    } else if (_validChainStep(lastPlayed, next)) {
      if (_dfsChain(rest, next,
          discardTop: discardTop,
          suitLock: suitLock,
          queenSuitLock: queenSuitLock,
          isPenaltyChainActive: isPenaltyChainActive)) {
        return true;
      }
    }
  }
  return false;
}

/// Every (suit, rank) identity a Joker could be declared as, precomputed
/// once — used to test each candidate against [_canOpenChain] /
/// [_validChainStep] instead of assuming a Joker connects to anything.
final List<CardModel> _jokerDeclarationCandidates = [
  for (final suit in Suit.values)
    for (final rank in Rank.values)
      if (rank != Rank.joker)
        CardModel(id: 'joker_probe_${suit.name}_${rank.name}', suit: suit, rank: rank),
];

/// Whether [card] could legally be the very first card played this turn,
/// mirroring the engine's `_validateSingle` first-card rules. Returns `true`
/// unconstrained when [discardTop] is null (no context available).
///
/// [card] is never an actual Joker here — [_dfsChain] resolves Jokers to a
/// candidate declared identity (see [_jokerDeclarationCandidates]) before
/// calling this.
bool _canOpenChain(
  CardModel card, {
  required CardModel? discardTop,
  required Suit? suitLock,
  required Suit? queenSuitLock,
  required bool isPenaltyChainActive,
}) {
  if (discardTop == null) return true;
  if (card.effectiveRank == Rank.ace) return true; // wild ace opener
  if (isPenaltyChainActive &&
      card.effectiveRank == Rank.jack &&
      !card.isBlackJack) {
    return true;
  }
  final discardIsPenalty =
      discardTop.effectiveRank == Rank.two || discardTop.effectiveRank == Rank.jack;
  final cardIsPenalty =
      card.effectiveRank == Rank.two || card.effectiveRank == Rank.jack;
  if (isPenaltyChainActive && discardIsPenalty && cardIsPenalty) return true;
  if (queenSuitLock != null) {
    return card.effectiveSuit == queenSuitLock || card.effectiveRank == Rank.queen;
  }
  final requiredSuit = suitLock ?? discardTop.effectiveSuit;
  if (card.effectiveSuit == requiredSuit) return true;
  if (card.effectiveRank == discardTop.effectiveRank) return true;
  return false;
}

/// Step validity mirroring [validatePlay] mid-turn flow (no discard).
///
/// Neither argument is ever an actual Joker here — [_dfsChain] resolves
/// Jokers to a candidate declared identity (see [_jokerDeclarationCandidates])
/// before calling this. Queens are **not** wild: a Queen played mid-chain
/// must still match [prev] by normal suit/rank continuity (below) unless
/// [prev] is itself a Queen, in which case its suit-lock governs instead.
bool _validChainStep(CardModel prev, CardModel next) {
  if (prev.effectiveRank == Rank.queen) {
    return next.effectiveSuit == prev.effectiveSuit ||
        next.effectiveRank == Rank.queen;
  }

  // No [GameState] here: this DFS only chains cards within one hypothetical turn.
  // After any penalty card, the next card in that turn is always "chain live"
  // for purposes of this hand-only simulation — gate with
  // [GameState.isPenaltyChainActive] when validating against real game state.
  if (isPenaltyChain(prev, next)) return true;

  if (prev.effectiveRank == next.effectiveRank) return true;

  final sameSuit = next.effectiveSuit == prev.effectiveSuit;
  final rankDiff =
      (next.effectiveRank.numericValue - prev.effectiveRank.numericValue).abs();
  final isTwoAndAce = (prev.effectiveRank == Rank.two &&
          next.effectiveRank == Rank.ace) ||
      (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.two);
  final isAceAndKing = (prev.effectiveRank == Rank.king &&
          next.effectiveRank == Rank.ace) ||
      (prev.effectiveRank == Rank.ace && next.effectiveRank == Rank.king);
  final isConsecutiveSameSuit =
      sameSuit && (rankDiff == 1 || isTwoAndAce || isAceAndKing);
  return isConsecutiveSameSuit;
}

/// Whether a player may declare Last Cards given whose turn it is.
/// You must declare when it is **not** your turn (before play returns to you).
bool mayDeclareLastCards({
  required String currentPlayerId,
  required String playerId,
}) =>
    currentPlayerId != playerId;

/// Whether the Last Cards **control** is shown (not bust, not already declared).
/// Turn-order for actually declaring is enforced by [mayDeclareLastCards] and
/// the server session.
bool shouldShowLastCardsButton({
  required bool isBustMode,
  required bool alreadyDeclared,
}) {
  if (isBustMode) return false;
  if (alreadyDeclared) return false;
  return true;
}
