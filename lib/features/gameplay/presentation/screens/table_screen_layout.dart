part of 'table_screen.dart';

// ── Table layout ──────────────────────────────────────────────────────────────

class _TableLayout extends StatelessWidget {
  const _TableLayout({
    required this.gameState,
    required this.selectedCardId,
    required this.orderedHand,
    required this.isMyTurn,
    required this.secondsLeft,
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
  });

  final GameState gameState;
  final String? selectedCardId;
  final List<CardModel> orderedHand;
  final bool isMyTurn;
  final int secondsLeft;
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

    // Local player is always at TablePosition.bottom
    final localPlayer = players.firstWhere(
      (p) => p.tablePosition == TablePosition.bottom,
      orElse: () => players.isNotEmpty ? players.first : _emptyLocal,
    );

    // Classify opponents by table position
    final topOpp = _opponentAt(players, TablePosition.top);
    final leftOpp = _opponentAt(players, TablePosition.left);
    final rightOpp = _opponentAt(players, TablePosition.right);

    // Calculate next turn ID for visual indicator
    String nextId = '';
    if (players.isNotEmpty) {
      final int idx =
          players.indexWhere((p) => p.id == gameState.currentPlayerId);
      if (idx != -1) {
        final int dir = gameState.direction == PlayDirection.clockwise ? 1 : -1;
        final int count = players.length;
        int nextIdx = (idx + dir) % count;
        if (nextIdx < 0) nextIdx += count;
        nextId = players[nextIdx].id;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppDimensions.breakpointMobile;
        final horizontalPadding =
            isMobile ? AppDimensions.xs : AppDimensions.md;
        final drawCardWidth = (constraints.maxWidth * (isMobile ? 0.14 : 0.12))
            .clamp(54.0, 120.0);
        final discardCardWidth = (drawCardWidth * 1.1).clamp(60.0, 132.0);
        final handCardWidth =
            (constraints.maxWidth * (isMobile ? 0.12 : 0.1)).clamp(48.0, 82.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              // ── Top opponents row: P2 left, P3 center, P4 right ─────────
              Padding(
                padding: EdgeInsets.only(
                    top: isMobile ? AppDimensions.xs : AppDimensions.md),
                child: Row(
                  children: [
                    Expanded(
                        child: Align(
                      alignment: Alignment.topLeft,
                      child: leftOpp != null
                          ? PlayerZoneWidget(
                              key: playerZoneKeys[leftOpp.id],
                              player: leftOpp,
                              isNextTurn: leftOpp.id == nextId,
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
                                isNextTurn: topOpp.id == nextId,
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
                                isNextTurn: rightOpp.id == nextId,
                              )
                            : const SizedBox(height: 96),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Centre board area (unchanged draw/discard/dealer/HUD) ───
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HudOverlayWidget(
                        activeSuit: gameState.suitLock,
                        queenSuitLock: gameState.queenSuitLock,
                        penaltyCount: penaltyCount,
                      ),
                      SizedBox(
                          height:
                              isMobile ? AppDimensions.sm : AppDimensions.md),
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DrawPileWidget(
                              key: drawPileKey,
                              cardCount: gameState.drawPileCount,
                              onTap: onDrawTap,
                              cardWidth: drawCardWidth,
                              enabled: isMyTurn &&
                                  selectedCardId == null &&
                                  !isDealing,
                            ),
                            const SizedBox(width: AppDimensions.sm),
                            DiscardPileWidget(
                              topCard: gameState.discardTopCard,
                              secondCard: gameState.discardSecondCard,
                              cardWidth: discardCardWidth,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Local player hand ───────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(
                  bottom: isMobile ? AppDimensions.sm : AppDimensions.md,
                ),
                child: PlayerZoneWidget(
                  key: playerZoneKeys[localPlayer.id],
                  player: localPlayer,
                  isLocalPlayer: true,
                  isNextTurn: localPlayer.id == nextId,
                  child: PlayerHandWidget(
                    cards: isDealing
                        ? orderedHand
                            .take(visibleCardCounts[localPlayer.id] ?? 0)
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
            ],
          ),
        );
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
    isConnected: true,
    isActiveTurn: false,
    isSkipped: false,
  );

  PlayerModel? _opponentAt(List<PlayerModel> players, TablePosition pos) {
    try {
      return players.firstWhere((p) => p.tablePosition == pos);
    } catch (_) {
      return null;
    }
  }
}
