part of 'table_screen.dart';

// ── Table layout ──────────────────────────────────────────────────────────────

class _TableLayout extends StatelessWidget {
  const _TableLayout({
    required this.gameState,
    required this.selectedCardId,
    required this.orderedHand,
    required this.isMyTurn,
    required this.penaltyCount,
    required this.connState,
    required this.canEndTurn,
    required this.isDealing,
    required this.visibleCardCounts,
    required this.drawPileKey,
    required this.playerZoneKeys,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onHandReorder,
    required this.onEndTurnTap,
    required this.isOffline,
    this.discardPileCount = 0,
    this.reshuffleNotifier,
    this.timeRemainingStream,
    this.tournamentStatusBadges = const <String, String>{},
    this.finishedPlayerIds = const <String>{},
    this.aiConfigs = const <String, AiPlayerConfig>{},
    this.isRanked = false,
  });

  /// True when this is a ranked online match (from session_config).
  final bool isRanked;

  final GameState gameState;
  final String? selectedCardId;
  final List<CardModel> orderedHand;
  final bool isMyTurn;

  final int penaltyCount;
  final WsConnectionState connState;
  final bool canEndTurn;
  final bool isDealing;
  final Map<String, int> visibleCardCounts;
  final GlobalKey drawPileKey;
  final Map<String, GlobalKey> playerZoneKeys;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final void Function(int oldIndex, int newIndex) onHandReorder;
  final VoidCallback onEndTurnTap;
  final bool isOffline;

  /// Number of cards in the discard pile for dynamic stacking depth.
  final int discardPileCount;

  /// Notifier toggled on every reshuffle — forwarded to [DrawPileWidget].
  final ValueNotifier<bool>? reshuffleNotifier;

  /// The stream to consume for turn timers.
  final Stream<int>? timeRemainingStream;
  final Map<String, String> tournamentStatusBadges;
  final Set<String> finishedPlayerIds;

  /// Per-AI player configurations (name, personality, avatar color).
  /// Populated for all modes — drives avatars, personality scoring, and chat.
  final Map<String, AiPlayerConfig> aiConfigs;

  @override
  Widget build(BuildContext context) {
    var players = gameState.players;

    // Create new player models masked by visible counts if dealing is active.
    if (isDealing) {
      players = players.map((p) {
        final visible = visibleCardCounts[p.id] ?? 0;
        final clampedVisible = math.min(visible, p.cardCount);
        return p.copyWith(
          cardCount: clampedVisible,
          hand: p.hand.take(clampedVisible).toList(),
        );
      }).toList();
    }

    // Local player is always at TablePosition.bottom (in online mode the server
    // sends each client with themselves at bottom).
    final localPlayer = players.firstWhere(
      (p) => p.tablePosition == TablePosition.bottom,
      orElse: () => players.isNotEmpty ? players.first : _emptyLocal,
    );

    // Classify opponents by table position (2–4 players) or use rail (5+ players)
    final topOpp = _opponentAt(players, TablePosition.top);
    final leftOpp = _opponentAt(players, TablePosition.left);
    final rightOpp = _opponentAt(players, TablePosition.right);

    // For 5+ players, use rail layout; otherwise use 3-slot layout
    final useRail = players.length > 4;
    final opponents = useRail
        ? players
            .where((p) => p.tablePosition != TablePosition.bottom)
            .toList()
        : <PlayerModel>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use shorter dimension: in landscape, maxWidth is the long axis.
        final isMobile = math.min(constraints.maxWidth, constraints.maxHeight) <
            AppDimensions.breakpointMobile;
        final isLandscapeMobile =
            isMobile && constraints.maxWidth > constraints.maxHeight;

        // Dedicated landscape layout — no scroll, HUD inline, distinct structure.
        if (isLandscapeMobile) {
          return _LandscapeTableLayout(
            gameState: gameState,
            selectedCardId: selectedCardId,
            orderedHand: orderedHand,
            isMyTurn: isMyTurn,
            penaltyCount: penaltyCount,
            canEndTurn: canEndTurn,
            isDealing: isDealing,
            visibleCardCounts: visibleCardCounts,
            drawPileKey: drawPileKey,
            playerZoneKeys: playerZoneKeys,
            localPlayer: localPlayer,
            useRail: useRail,
            opponents: opponents,
            leftOpp: leftOpp,
            topOpp: topOpp,
            rightOpp: rightOpp,
            onCardTap: onCardTap,
            onDrawTap: onDrawTap,
            onHandReorder: onHandReorder,
            onEndTurnTap: onEndTurnTap,
            discardPileCount: discardPileCount,
            reshuffleNotifier: reshuffleNotifier,
            timeRemainingStream: timeRemainingStream,
            tournamentStatusBadges: tournamentStatusBadges,
            finishedPlayerIds: finishedPlayerIds,
            aiConfigs: aiConfigs,
          );
        }

        final horizontalPadding =
            isMobile ? AppDimensions.xs : AppDimensions.md;
        final effectiveWidth = constraints.maxWidth;
        final handCardWidth = (effectiveWidth * (isMobile ? 0.12 : 0.1))
            .clamp(44.0, 82.0);

        final body = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              // ── Top opponents: rail (5+ players) or 3-slot (2–4) ─────────
              Padding(
                padding: const EdgeInsets.only(top: 0),
                child: useRail
                    ? BustPlayerRail(
                        players: opponents.asMap().entries.map((e) {
                          return BustPlayerViewModel.fromPlayerModel(
                            e.value,
                            currentPlayerId: gameState.currentPlayerId,
                            isEliminated: false,
                            isLocal: false,
                            colorIndex: e.key,
                            tournamentStatusBadge:
                                tournamentStatusBadges[e.value.id],
                          );
                        }).toList(),
                        slotKeyBuilder: (player) =>
                            playerZoneKeys[player.id],
                        height: tournamentStatusBadges.isNotEmpty ? 112 : 96,
                      )
                    : Row(
                        children: [
                          Expanded(
                              child: Align(
                            alignment: Alignment.topLeft,
                            child: leftOpp != null
                                ? PlayerZoneWidget(
                                    key: playerZoneKeys[leftOpp.id],
                                    player: leftOpp,
                                    isActiveTurn: gameState.currentPlayerId == leftOpp.id,
                                    isTournamentFinished:
                                        tournamentStatusBadges[leftOpp.id] !=
                                            null,
                                    isTournamentEliminated: _isEliminatedBadge(
                                      tournamentStatusBadges[leftOpp.id],
                                    ),
                                    aiConfig: aiConfigs[leftOpp.id],
                                  )
                                : const SizedBox(height: 96),
                          )),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: topOpp != null
                                  ? PlayerZoneWidget(
                                      key: playerZoneKeys[topOpp.id],
                                      player: topOpp,
                                      isActiveTurn: gameState.currentPlayerId == topOpp.id,
                                      isTournamentFinished:
                                          tournamentStatusBadges[topOpp.id] !=
                                              null,
                                      isTournamentEliminated: _isEliminatedBadge(
                                        tournamentStatusBadges[topOpp.id],
                                      ),
                                      aiConfig: aiConfigs[topOpp.id],
                                    )
                                  : const _EmptyOpponentZone(),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: rightOpp != null
                                  ? PlayerZoneWidget(
                                      key: playerZoneKeys[rightOpp.id],
                                      player: rightOpp,
                                      isActiveTurn: gameState.currentPlayerId == rightOpp.id,
                                      isTournamentFinished:
                                          tournamentStatusBadges[rightOpp.id] !=
                                              null,
                                      isTournamentEliminated: _isEliminatedBadge(
                                        tournamentStatusBadges[rightOpp.id],
                                      ),
                                      aiConfig: aiConfigs[rightOpp.id],
                                    )
                                  : const SizedBox(height: 96),
                            ),
                          ),
                        ],
                      ),
              ),

              // ── Centre board area (draw/discard/dealer) ────────────────────────
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // HudOverlayWidget is rendered as a Positioned overlay
                      // in the outer Stack (above the game log). This SizedBox
                      // preserves the vertical spacing for the draw/discard piles.
                      const SizedBox(height: 72),
                      SizedBox(
                          height:
                              isMobile ? AppDimensions.sm : AppDimensions.md),
                      if (isRanked)
                        _RankedBadge(isMobile: isMobile),
                      if (isRanked) const SizedBox(height: AppDimensions.xs),
                      Opacity(
                        opacity: 0.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.sm + 2,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.goldDark.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.radiusButton,
                            ),
                            border: Border.all(
                              color: AppColors.goldDark.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            isDealing ? 'DEALING...' : 'DEALER',
                            key: const ValueKey('dealer-status'),
                            style: TextStyle(
                              color: AppColors.goldPrimary,
                              fontSize: isMobile ? 8 : 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 145,
                              child: OverflowBox(
                                maxWidth: double.infinity,
                                maxHeight: double.infinity,
                                child: DrawPileWidget(
                                  key: drawPileKey,
                                  cardCount: gameState.drawPileCount,
                                  onTap: onDrawTap,
                                  cardWidth: 100,
                                  enabled: isMyTurn &&
                                      (gameState.actionsThisTurn == 0 ||
                                          gameState.queenSuitLock != null) &&
                                      selectedCardId == null &&
                                      !isDealing,
                                  reshuffleNotifier: reshuffleNotifier,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            SizedBox(
                              width: 100,
                              height: 145,
                              child: OverflowBox(
                                maxWidth: double.infinity,
                                maxHeight: double.infinity,
                                child: DiscardPileWidget(
                                  topCard: gameState.discardTopCard,
                                              secondCard: gameState.discardPileHistory.isNotEmpty ? gameState.discardPileHistory.first : null,
                                              discardPileHistory: gameState.discardPileHistory,
                                              cardWidth: 100,
                                              discardPileCount: discardPileCount,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Floating Action Bar (Bottom HUD) ─────────────────────────
              Padding(
                padding: EdgeInsets.only(
                  bottom: isMobile ? AppDimensions.sm : AppDimensions.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TurnTimerBar(
                      timeRemainingStream: timeRemainingStream,
                      isVisible: true,
                    ),
                    const SizedBox(height: 8),
                    FloatingActionBarWidget(
                      activePlayerName: gameState
                              .playerById(gameState.currentPlayerId)
                              ?.displayName ??
                          '',
                      direction: gameState.direction,
                      canEndTurn: canEndTurn,
                      onEndTurn: onEndTurnTap,
                    ),
                  ],
                ),
              ),

              // ── Local player hand ───────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(
                  bottom: isMobile ? AppDimensions.sm : AppDimensions.md,
                ),
                child: SizedBox(
                  width: double.infinity,
              child: PlayerZoneWidget(
                key: playerZoneKeys[localPlayer.id],
                player: localPlayer,
                isLocalPlayer: true,
                isActiveTurn: gameState.currentPlayerId == localPlayer.id,
                compact: false,
                child: finishedPlayerIds.contains(localPlayer.id)
                        ? _TournamentLocalStatusBanner(
                            isEliminated: _isEliminatedBadge(
                              tournamentStatusBadges[localPlayer.id],
                            ),
                          )
                        : PlayerHandWidget(
                            cards: isDealing
                                ? orderedHand
                                    .take(
                                        visibleCardCounts[localPlayer.id] ?? 0)
                                    .toList()
                                : orderedHand,
                            selectedCardId: selectedCardId,
                            onCardTap: onCardTap,
                            onReorder: onHandReorder,
                            enabled: isMyTurn && !isDealing,
                            cardWidth: handCardWidth,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
        return body;
      },
    );
  }

  // Fallback empty local player (should never be needed with demo state)
  static const _emptyLocal = PlayerModel(
    id: 'local',
    displayName: 'You',
    tablePosition: TablePosition.bottom,
    hand: [],
    cardCount: 0,
  );

  PlayerModel? _opponentAt(List<PlayerModel> players, TablePosition pos) {
    try {
      return players.firstWhere((p) => p.tablePosition == pos);
    } catch (_) {
      return null;
    }
  }

  bool _isEliminatedBadge(String? badgeText) {
    if (badgeText == null) return false;
    return badgeText.contains('Eliminated');
  }
}

// ── Dedicated landscape layout (mobile) ───────────────────────────────────────
//
// Purpose-built for landscape: 3 compact bands, HUD inline, no scrolling.
// Opponents rail → Centre (draw/discard/HUD) + turn bar → Hand.

class _LandscapeTableLayout extends StatelessWidget {
  const _LandscapeTableLayout({
    required this.gameState,
    required this.selectedCardId,
    required this.orderedHand,
    required this.isMyTurn,
    required this.penaltyCount,
    required this.canEndTurn,
    required this.isDealing,
    required this.visibleCardCounts,
    required this.drawPileKey,
    required this.playerZoneKeys,
    required this.localPlayer,
    required this.useRail,
    required this.opponents,
    required this.leftOpp,
    required this.topOpp,
    required this.rightOpp,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onHandReorder,
    required this.onEndTurnTap,
    required this.discardPileCount,
    required this.reshuffleNotifier,
    required this.timeRemainingStream,
    required this.tournamentStatusBadges,
    required this.finishedPlayerIds,
    required this.aiConfigs,
  });

  final GameState gameState;
  final String? selectedCardId;
  final List<CardModel> orderedHand;
  final bool isMyTurn;
  final int penaltyCount;
  final bool canEndTurn;
  final bool isDealing;
  final Map<String, int> visibleCardCounts;
  final GlobalKey drawPileKey;
  final Map<String, GlobalKey> playerZoneKeys;
  final PlayerModel localPlayer;
  final bool useRail;
  final List<PlayerModel> opponents;
  final PlayerModel? leftOpp;
  final PlayerModel? topOpp;
  final PlayerModel? rightOpp;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final void Function(int oldIndex, int newIndex) onHandReorder;
  final VoidCallback onEndTurnTap;
  final int discardPileCount;
  final ValueNotifier<bool>? reshuffleNotifier;
  final Stream<int>? timeRemainingStream;
  final Map<String, String> tournamentStatusBadges;
  final Set<String> finishedPlayerIds;
  final Map<String, AiPlayerConfig> aiConfigs;

  @override
  Widget build(BuildContext context) {
    const handCardWidth = 40.0;
    const pileSize = 56.0;
    const pileHeight = 78.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.xs),
      child: Column(
        children: [
          // ── Band 1: Compact opponents rail (taller when tournament badges) ─
          SizedBox(
            height: tournamentStatusBadges.isNotEmpty ? 88 : 72,
            child: useRail
                ? BustPlayerRail(
                    players: opponents.asMap().entries.map((e) {
                      return BustPlayerViewModel.fromPlayerModel(
                        e.value,
                        currentPlayerId: gameState.currentPlayerId,
                        isEliminated: false,
                        isLocal: false,
                        colorIndex: e.key,
                        tournamentStatusBadge:
                            tournamentStatusBadges[e.value.id],
                      );
                    }).toList(),
                    slotKeyBuilder: (player) => playerZoneKeys[player.id],
                    height: tournamentStatusBadges.isNotEmpty ? 88 : 72,
                    compact: true,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: leftOpp != null
                              ? PlayerZoneWidget(
                                  key: playerZoneKeys[leftOpp!.id],
                                  player: leftOpp!,
                                  isActiveTurn: gameState.currentPlayerId == leftOpp!.id,
                                  isTournamentFinished:
                                      tournamentStatusBadges[leftOpp!.id] !=
                                          null,
                                  isTournamentEliminated: _isEliminatedBadge(
                                    tournamentStatusBadges[leftOpp!.id],
                                  ),
                                  aiConfig: aiConfigs[leftOpp!.id],
                                  compact: true,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: topOpp != null
                              ? PlayerZoneWidget(
                                  key: playerZoneKeys[topOpp!.id],
                                  player: topOpp!,
                                  isActiveTurn: gameState.currentPlayerId == topOpp!.id,
                                  isTournamentFinished:
                                      tournamentStatusBadges[topOpp!.id] !=
                                          null,
                                  isTournamentEliminated: _isEliminatedBadge(
                                    tournamentStatusBadges[topOpp!.id],
                                  ),
                                  aiConfig: aiConfigs[topOpp!.id],
                                  compact: true,
                                )
                              : const _EmptyOpponentZone(),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: rightOpp != null
                              ? PlayerZoneWidget(
                                  key: playerZoneKeys[rightOpp!.id],
                                  player: rightOpp!,
                                  isActiveTurn: gameState.currentPlayerId == rightOpp!.id,
                                  isTournamentFinished:
                                      tournamentStatusBadges[rightOpp!.id] !=
                                          null,
                                  isTournamentEliminated: _isEliminatedBadge(
                                    tournamentStatusBadges[rightOpp!.id],
                                  ),
                                  aiConfig: aiConfigs[rightOpp!.id],
                                  compact: true,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
          ),

          // ── Band 2: Centre strip — draw, discard, HUD inline, turn bar ───
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Draw pile
                SizedBox(
                  width: pileSize,
                  height: pileHeight,
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: DrawPileWidget(
                      key: drawPileKey,
                      cardCount: gameState.drawPileCount,
                      onTap: onDrawTap,
                      cardWidth: pileSize,
                      enabled: isMyTurn &&
                          (gameState.actionsThisTurn == 0 ||
                              gameState.queenSuitLock != null) &&
                          selectedCardId == null &&
                          !isDealing,
                      reshuffleNotifier: reshuffleNotifier,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Discard pile
                SizedBox(
                  width: pileSize,
                  height: pileHeight,
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: DiscardPileWidget(
                      topCard: gameState.discardTopCard,
                      secondCard: gameState.discardPileHistory.isNotEmpty ? gameState.discardPileHistory.first : null,
                      discardPileHistory: gameState.discardPileHistory,
                      cardWidth: pileSize,
                      discardPileCount: discardPileCount,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // HUD inline (suit badge, penalty, queen lock)
                HudOverlayWidget(
                  activeSuit: gameState.suitLock,
                  queenSuitLock: gameState.queenSuitLock,
                  penaltyCount: penaltyCount,
                  penaltyTargetPosition: penaltyCount > 0
                      ? gameState.players
                          .where((p) =>
                              p.id == nextPlayerId(state: gameState))
                          .firstOrNull
                          ?.tablePosition
                      : null,
                  compact: true,
                ),
              ],
            ),
          ),

          // Turn timer + action bar (compact for landscape)
          TurnTimerBar(
            timeRemainingStream: timeRemainingStream,
            isVisible: true,
            compact: true,
          ),
          const SizedBox(height: 2),
          FloatingActionBarWidget(
            activePlayerName: gameState
                    .playerById(gameState.currentPlayerId)
                    ?.displayName ??
                '',
            direction: gameState.direction,
            canEndTurn: canEndTurn,
            onEndTurn: onEndTurnTap,
            compact: true,
          ),
          const SizedBox(height: 2),

          // ── Band 3: Local player hand ────────────────────────────────────
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: PlayerZoneWidget(
                key: playerZoneKeys[localPlayer.id],
                player: localPlayer,
                isLocalPlayer: true,
                isActiveTurn: gameState.currentPlayerId == localPlayer.id,
                compact: true,
                child: finishedPlayerIds.contains(localPlayer.id)
                    ? _TournamentLocalStatusBanner(
                        isEliminated: _isEliminatedBadge(
                          tournamentStatusBadges[localPlayer.id],
                        ),
                      )
                    : PlayerHandWidget(
                        cards: isDealing
                            ? orderedHand
                                .take(
                                    visibleCardCounts[localPlayer.id] ?? 0)
                                .toList()
                            : orderedHand,
                        selectedCardId: selectedCardId,
                        onCardTap: onCardTap,
                        onReorder: onHandReorder,
                        enabled: isMyTurn && !isDealing,
                        cardWidth: handCardWidth,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isEliminatedBadge(String? badgeText) {
    if (badgeText == null) return false;
    return badgeText.contains('Eliminated');
  }
}

class _TournamentLocalStatusBanner extends StatelessWidget {
  const _TournamentLocalStatusBanner({required this.isEliminated});

  final bool isEliminated;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isEliminated ? const Color(0xFFFF3333) : const Color(0xFFFFD700);
    final gradientColors = isEliminated
        ? const [
            Color(0xFF1A0000),
            Color(0xFF3A0000),
            Color(0xFF1A0000),
          ]
        : const [
            Color(0xFF0A1A00),
            Color(0xFF1A3A00),
            Color(0xFF0A1A00),
          ];

    return Container(
      width: double.infinity,
      height: 110,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          top: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isEliminated ? Icons.cancel : Icons.emoji_events,
            color: accentColor,
            size: 32,
          ),
          const SizedBox(height: 6),
          Text(
            isEliminated ? '✗  ELIMINATED' : '✓  QUALIFIED',
            style: TextStyle(
              color: accentColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFamily: 'Cinzel',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isEliminated
                ? 'Better luck next time'
                : 'Waiting for next round...',
            style: const TextStyle(
              color: Color(0x70FFFFFF),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── RANKED badge (theme-aware) ────────────────────────────────────────────────

/// Badge shown during ranked online matches. Uses theme.accentPrimary and
/// theme.surfacePanel to match HUD badge patterns.
class _RankedBadge extends ConsumerWidget {
  const _RankedBadge({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimensions.sm + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: theme.surfacePanel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(color: theme.accentPrimary, width: 2),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        'RANKED',
        style: TextStyle(
          color: theme.accentPrimary,
          fontSize: isMobile ? 8 : 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
