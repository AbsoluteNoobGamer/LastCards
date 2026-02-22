part of 'table_screen.dart';

// ── Table layout ──────────────────────────────────────────────────────────────

class _TableLayout extends StatelessWidget {
  const _TableLayout({
    required this.gameState,
    required this.selectedCardIds,
    required this.isMyTurn,
    required this.secondsLeft,
    required this.penaltyCount,
    required this.connState,
    required this.canEndTurn,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onPlayTap,
    required this.onEndTurnTap,
  });

  final GameState gameState;
  final Set<String> selectedCardIds;
  final bool isMyTurn;
  final int secondsLeft;
  final int penaltyCount;
  final WsConnectionState connState;
  final bool canEndTurn;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final VoidCallback onPlayTap;
  final VoidCallback onEndTurnTap;

  @override
  Widget build(BuildContext context) {
    final players = gameState.players;
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

    return Column(
      children: [
        // ── Top opponent ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: AppDimensions.md),
          child: topOpp != null
              ? PlayerZoneWidget(
                  player: topOpp, isNextTurn: topOpp.id == nextId)
              : const _EmptyOpponentZone(),
        ),

        // ── Centre row: left opp / piles / right opp ───────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left opponent
              Expanded(
                child: Center(
                  child: leftOpp != null
                      ? RotatedBox(
                          quarterTurns: 1,
                          child: PlayerZoneWidget(
                              player: leftOpp,
                              isNextTurn: leftOpp.id == nextId),
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // Centre piles + HUD
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // HUD row
                  HudOverlayWidget(
                    activeSuit: gameState.suitLock,
                    queenSuitLock: gameState.queenSuitLock,
                    penaltyCount: penaltyCount,
                    connectionState: connState,
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Dealer badge — indicates the dealing entity (not a player)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.sm + 2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldDark.withValues(alpha: 0.25),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusButton),
                      border: Border.all(
                        color: AppColors.goldDark.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      'DEALER',
                      style: TextStyle(
                        color: AppColors.goldPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // Draw pile + Discard pile side by side
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DrawPileWidget(
                        cardCount: gameState.drawPileCount,
                        onTap: onDrawTap,
                        enabled: isMyTurn && (selectedCardIds.isEmpty),
                      ),
                      const SizedBox(width: AppDimensions.lg),
                      DiscardPileWidget(
                        topCard: gameState.discardTopCard,
                        secondCard: gameState.discardSecondCard,
                      ),
                    ],
                  ),

                  // End Turn button removed from here, now in Status Bar
                  // We just show a blank space or keep play button only
                  if (selectedCardIds.isNotEmpty && isMyTurn) ...[
                    const SizedBox(height: AppDimensions.md),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldPrimary,
                        foregroundColor: AppColors.feltDeep,
                      ),
                      onPressed: onPlayTap,
                      child: Text(
                          'PLAY CARD${selectedCardIds.length > 1 ? 'S' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),

              // Right opponent
              Expanded(
                child: Center(
                  child: rightOpp != null
                      ? RotatedBox(
                          quarterTurns: 3,
                          child: PlayerZoneWidget(
                              player: rightOpp,
                              isNextTurn: rightOpp.id == nextId),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),

        // ── Local player hand ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.md),
          child: PlayerZoneWidget(
            player: localPlayer,
            isLocalPlayer: true,
            isNextTurn: localPlayer.id == nextId,
            child: PlayerHandWidget(
              cards: localPlayer.hand,
              selectedCardIds: selectedCardIds,
              onCardTap: onCardTap,
              enabled: isMyTurn,
            ),
          ),
        ),
      ],
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
