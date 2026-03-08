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
  });

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
  /// Empty in tournament mode where players have their own names.
  final Map<String, AiPlayerConfig> aiConfigs;

  @override
  Widget build(BuildContext context) {
    var players = gameState.players;

    // Update player models to accurately reflect `isActiveTurn` BEFORE extracting
    players = players
        .map((p) => p.copyWith(isActiveTurn: p.id == gameState.currentPlayerId))
        .toList();

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppDimensions.breakpointMobile;
        final horizontalPadding =
            isMobile ? AppDimensions.xs : AppDimensions.md;
        final handCardWidth =
            (constraints.maxWidth * (isMobile ? 0.12 : 0.1)).clamp(48.0, 82.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              // ── Top opponents row: P2 left, P3 center, P4 right ─────────
              Padding(
                padding: const EdgeInsets.only(top: 0),
                child: Row(
                  children: [
                    Expanded(
                        child: Align(
                      alignment: Alignment.topLeft,
                      child: leftOpp != null
                          ? PlayerZoneWidget(
                              key: playerZoneKeys[leftOpp.id],
                              player: leftOpp,
                              isTournamentFinished:
                                  tournamentStatusBadges[leftOpp.id] != null,
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
                                isTournamentFinished:
                                    tournamentStatusBadges[topOpp.id] != null,
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
                                isTournamentFinished:
                                    tournamentStatusBadges[rightOpp.id] != null,
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

              // ── Centre board area (unchanged draw/discard/dealer/HUD) ───
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
                                  secondCard: gameState.discardSecondCard,
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
