part of 'table_screen.dart';

// ── Table layout ──────────────────────────────────────────────────────────────

String _activePlayerDisplayName(
  GameState gameState,
  Set<String> socketDisconnectedPlayerIds,
) {
  final id = gameState.currentPlayerId;
  if (socketDisconnectedPlayerIds.contains(id)) {
    return 'Reconnecting…';
  }
  return gameState.playerById(id)?.displayName ?? '';
}

Widget _localHandRegionSlot({
  required double height,
  required double contentWidth,
  required Widget child,
}) {
  return SizedBox(
    height: height,
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              // Fixed width (a reference 9-card hand, see
              // PlayerHandWidget.referenceFanWidth) — not just a cap — so the
              // zone's footprint (and its active-turn accent tint) stays the
              // same size turn to turn. PlayerHandWidget centers its actual
              // fan within this fixed frame regardless of real card count.
              child: SizedBox(
                width: contentWidth,
                child: child,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TableLayout extends StatelessWidget {
  const _TableLayout({
    required this.gameState,
    required this.socketDisconnectedPlayerIds,
    required this.selectedCardId,
    required this.orderedHand,
    required this.isMyTurn,
    required this.penaltyCount,
    required this.connState,
    required this.canEndTurn,
    required this.isDealing,
    required this.visibleCardCounts,
    required this.drawPileKey,
    required this.discardPileKey,
    required this.hudKey,
    this.thinkingOpponentId,
    required this.playerZoneKeys,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onHandReorder,
    required this.onEndTurnTap,
    required this.isOffline,
    this.discardPileCount = 0,
    this.reshuffleNotifier,
    this.timeRemainingStream,
    this.turnTimerTotalSeconds = GameTurnTimer.defaultDurationSeconds,
    this.tournamentStatusBadges = const <String, String>{},
    this.finishedPlayerIds = const <String>{},
    this.aiConfigs = const <String, AiPlayerConfig>{},
    this.isRanked = false,
    this.quickChatBubblesByPlayer = const {},
    this.onRemoveQuickChatBubble,
    this.nextTurnLabel,
    this.isLocalTurn = false,
    this.hasAlreadyDeclaredLastCards = false,
    this.localHandSize = 0,
    this.handShakeTrigger,
    this.onLastCardsTap,
    this.onPenaltyIncreased,
    this.skipHighlightPlayerIds = const <String>{},
    this.onOpponentProfileTap,
    this.localAvatarFilePath,
    this.tableScale = 1.0,
  });

  /// Multiplier applied to every [TablePortraitGrid] reference size —
  /// 1.0 on phones, grows on tablets/desktop so chrome fills the extra
  /// canvas instead of leaving it as bare felt (see [TableScreen]'s
  /// top-level `tableScale` computation).
  final double tableScale;

  /// Online: tap opponent avatar to open profile / friend actions.
  final void Function(PlayerModel player)? onOpponentProfileTap;

  /// Local disk path for profile photo when not using HTTPS [PlayerModel.avatarUrl].
  final String? localAvatarFilePath;

  /// Called when the pickup penalty count increases (visual feedback).
  final VoidCallback? onPenaltyIncreased;

  /// Seats showing brief Eight-skip dim/pause.
  final Set<String> skipHighlightPlayerIds;

  /// Online: hide opponent seats while server grace reports socket loss.
  final Set<String> socketDisconnectedPlayerIds;

  final bool isLocalTurn;
  final bool hasAlreadyDeclaredLastCards;
  final int localHandSize;
  final VoidCallback? onLastCardsTap;

  /// Drives invalid-play hand shake on the local [PlayerHandWidget].
  final ValueNotifier<int>? handShakeTrigger;

  /// Shown under current turn — who follows (8 / K / direction).
  final String? nextTurnLabel;

  /// True when this is a ranked online match (from session_config).
  final bool isRanked;

  /// Active quick chat bubble per player id (most recent per player).
  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;

  /// Callback to remove a bubble by id.
  final void Function(String id)? onRemoveQuickChatBubble;

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
  final GlobalKey discardPileKey;
  final GlobalKey hudKey;
  final String? thinkingOpponentId;
  final Map<String, GlobalKey> playerZoneKeys;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final void Function(int oldIndex, int newIndex)? onHandReorder;
  final VoidCallback onEndTurnTap;
  final bool isOffline;

  /// Number of cards in the discard pile for dynamic stacking depth.
  final int discardPileCount;

  /// Notifier toggled on every reshuffle — forwarded to [DrawPileWidget].
  final ValueNotifier<bool>? reshuffleNotifier;

  /// The stream to consume for turn timers.
  final Stream<int>? timeRemainingStream;
  /// Denominator for the timer bar (30s hardcore vs 60s default).
  final int turnTimerTotalSeconds;
  final Map<String, String> tournamentStatusBadges;
  final Set<String> finishedPlayerIds;

  /// Per-AI player configurations (name, personality, avatar color).
  /// Populated for all modes — drives avatars, personality scoring, and chat.
  final Map<String, AiPlayerConfig> aiConfigs;

  @override
  Widget build(BuildContext context) {
    var players = gameState.players;
    if (socketDisconnectedPlayerIds.isNotEmpty) {
      players = players
          .where((p) => !socketDisconnectedPlayerIds.contains(p.id))
          .toList();
    }

    final activePlayerDisplayName =
        _activePlayerDisplayName(gameState, socketDisconnectedPlayerIds);

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

    // One slot per opponent actually seated — reclaims the dead centre space
    // 1v1/duo games used to get from always budgeting a 7-player rail.
    final opponentRailSlots = _adaptiveOpponentRailSlots(
      players: players,
      gameState: gameState,
      tournamentStatusBadges: tournamentStatusBadges,
    );

    VoidCallback? opponentAvatarTap(PlayerModel? p) {
      if (p == null || isOffline) return null;
      final uid = p.firebaseUid;
      if (uid == null || uid.isEmpty) return null;
      final cb = onOpponentProfileTap;
      if (cb == null) return null;
      return () => cb(p);
    }

    void onOpponentSlotTap(BustPlayerViewModel viewModel) {
      final player = players.where((p) => p.id == viewModel.id).firstOrNull;
      opponentAvatarTap(player)?.call();
    }

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
            activePlayerDisplayName: activePlayerDisplayName,
            selectedCardId: selectedCardId,
            orderedHand: orderedHand,
            isMyTurn: isMyTurn,
            penaltyCount: penaltyCount,
            canEndTurn: canEndTurn,
            isDealing: isDealing,
            visibleCardCounts: visibleCardCounts,
            drawPileKey: drawPileKey,
            discardPileKey: discardPileKey,
            hudKey: hudKey,
            thinkingOpponentId: thinkingOpponentId,
            nextTurnLabel: nextTurnLabel,
            playerZoneKeys: playerZoneKeys,
            localPlayer: localPlayer,
            opponentRailSlots: opponentRailSlots,
            onCardTap: onCardTap,
            onDrawTap: onDrawTap,
            onHandReorder: onHandReorder,
            onEndTurnTap: onEndTurnTap,
            discardPileCount: discardPileCount,
            reshuffleNotifier: reshuffleNotifier,
            timeRemainingStream: timeRemainingStream,
            turnTimerTotalSeconds: turnTimerTotalSeconds,
            tournamentStatusBadges: tournamentStatusBadges,
            finishedPlayerIds: finishedPlayerIds,
            aiConfigs: aiConfigs,
            quickChatBubblesByPlayer: quickChatBubblesByPlayer,
            onRemoveQuickChatBubble: onRemoveQuickChatBubble,
            isLocalTurn: isLocalTurn,
            hasAlreadyDeclaredLastCards: hasAlreadyDeclaredLastCards,
            localHandSize: localHandSize,
            handShakeTrigger: handShakeTrigger,
            onLastCardsTap: onLastCardsTap,
            onPenaltyIncreased: onPenaltyIncreased,
            skipHighlightPlayerIds: skipHighlightPlayerIds,
            onOpponentSlotTap: onOpponentSlotTap,
            isRanked: isRanked,
            localAvatarFilePath: localAvatarFilePath,
            tableScale: tableScale,
          );
        }

        final horizontalPadding =
            isMobile ? AppDimensions.xs : AppDimensions.md;
        final effectiveWidth = constraints.maxWidth;
        // The width-percentage formula alone doesn't grow proportionally
        // with the screen on tablets (10% of a wider screen isn't 10% *
        // tableScale bigger) — multiply by tableScale too, so actual card
        // size keeps pace with the reserved hand-region frame height
        // below, instead of leaving a growing empty gap under a
        // top-aligned, comparatively small card fan.
        final handCardWidth =
            (effectiveWidth * (isMobile ? 0.12 : 0.1) * (isMobile ? 1.0 : tableScale))
                .clamp(44.0, 82.0 * tableScale);
        // Fixed footprint sized to a reference 9-card hand — the local hand
        // region stays the same size turn to turn regardless of actual hand
        // count, instead of visibly resizing as cards are played/drawn.
        final referenceHandWidth = PlayerHandWidget.referenceFanWidth(
          maxWidth: effectiveWidth,
          cardWidth: handCardWidth,
          isCompact: isMobile,
          scale: tableScale,
        );
        final hasTournamentBadges = tournamentStatusBadges.isNotEmpty;
        final opponentRowHeight = TablePortraitGrid.opponentRowHeight(
          useRail: true,
          hasBadges: hasTournamentBadges,
          scale: tableScale,
        );
        final rankedBand = isRanked ? 34.0 * tableScale : 0.0;
        final bottomPad = isMobile ? 0.0 : AppDimensions.md;
        final scaledActionBarHeight = TablePortraitGrid.actionBarHeight * tableScale;
        final scaledBoardToActionBarGap =
            TablePortraitGrid.boardToActionBarGap * tableScale;
        // Must subtract every other fixed-height sibling in the Column below
        // (region 1 + this gap + region 3 + the trailing bottomPad SizedBox),
        // not just some of them — otherwise, at high tableScale on tablets,
        // the omitted amounts silently exceed the actual leftover space and
        // the hand region (floored at 110 by the clamp below) overflows the
        // Column instead of shrinking to fit.
        final handRegionHeight = math.min(
          TablePortraitGrid.handRegionHeight * tableScale,
          constraints.maxHeight -
              opponentRowHeight -
              scaledActionBarHeight -
              scaledBoardToActionBarGap -
              bottomPad -
              rankedBand,
        ).clamp(110.0, TablePortraitGrid.handRegionHeight * tableScale);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              // ── Region 1: Opponent seats (fixed height) ───────────────────
              if (isRanked)
                Padding(
                  padding: EdgeInsets.only(
                    top: isMobile ? 2 : 4,
                    bottom: isMobile ? 6 : 8,
                  ),
                  child: Center(child: _RankedBadge(isMobile: isMobile)),
                ),
              SizedBox(
                height: opponentRowHeight,
                child: BustPlayerRail(
                  slots: opponentRailSlots,
                  slotKeyBuilder: (player) => playerZoneKeys[player.id],
                  height: hasTournamentBadges
                      ? TablePortraitGrid.opponentRailBaseHeightWithBadge
                      : TablePortraitGrid.opponentRailBaseHeight,
                  scale: tableScale,
                  thinkingPlayerId: thinkingOpponentId,
                  quickChatBubblesByPlayer: quickChatBubblesByPlayer,
                  onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                  skipHighlightPlayerIds: skipHighlightPlayerIds,
                  onSlotTap: onOpponentSlotTap,
                ),
              ),

              // ── Region 2: Board — piles above HUD (Expanded) ──────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, boardConstraints) {
                    final scaledDrawWidth =
                        TablePortraitGrid.drawPileCardWidth * tableScale;
                    final scaledDiscardWidth =
                        TablePortraitGrid.discardPileCardWidth * tableScale;
                    return ClipRect(
                      child: FittedBox(
                        // contain (not scaleDown): on tablets this lets the
                        // whole piles+HUD block grow to fill the Expanded
                        // region instead of staying pinned at its natural
                        // (already tableScale-multiplied) size — a safety
                        // net for any residual slack, now that the
                        // constants themselves are pre-scaled above.
                        fit: BoxFit.contain,
                        // Anchor to the bottom, not the centre: the board's
                        // content (piles+HUD) is much shorter than this
                        // Expanded region, and centering it split the slack
                        // evenly — leaving a dead gap floating between the
                        // HUD and the action bar. Bottom-anchoring puts the
                        // piles flush against the action bar/hand below, and
                        // any leftover space becomes felt above, near the
                        // opponents, which reads as intentional breathing
                        // room rather than a broken void.
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: boardConstraints.maxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: 0,
                                child: Text(
                                  isDealing ? 'DEALING...' : 'DEALER',
                                  key: const ValueKey('dealer-status'),
                                  style: TextStyle(
                                    fontSize: (isMobile ? 8 : 9) * tableScale,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(height: AppDimensions.xs * tableScale),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: TablePortraitGrid
                                        .drawPileFootprintWidth(scaledDrawWidth),
                                    height: TablePortraitGrid
                                        .drawPileFootprintHeight(scaledDrawWidth),
                                    child: DrawPileWidget(
                                      key: drawPileKey,
                                      cardCount: gameState.drawPileCount,
                                      onTap: onDrawTap,
                                      cardWidth: scaledDrawWidth,
                                      enabled: isMyTurn &&
                                          (gameState.actionsThisTurn == 0 ||
                                              gameState.queenSuitLock != null) &&
                                          selectedCardId == null &&
                                          !isDealing,
                                      reshuffleNotifier: reshuffleNotifier,
                                    ),
                                  ),
                                  SizedBox(
                                      width: TablePortraitGrid.pileGap * tableScale),
                                  SizedBox(
                                    width: TablePortraitGrid
                                        .discardPileFootprintWidth(scaledDiscardWidth),
                                    height: TablePortraitGrid
                                        .discardPileFootprintHeight(scaledDiscardWidth),
                                    child: DiscardPileWidget(
                                      key: discardPileKey,
                                      topCard: gameState.discardTopCard,
                                      secondCard: gameState
                                              .discardPileHistory.isNotEmpty
                                          ? gameState.discardPileHistory.first
                                          : null,
                                      discardPileHistory:
                                          gameState.discardPileHistory,
                                      cardWidth: scaledDiscardWidth,
                                      discardPileCount: discardPileCount,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: AppDimensions.sm * tableScale),
                              SizedBox(
                                key: hudKey,
                                width: boardConstraints.maxWidth,
                                child: Center(
                                  child: HudOverlayWidget(
                                    activeSuit: gameState.suitLock,
                                    queenSuitLock: gameState.queenSuitLock,
                                    penaltyCount: penaltyCount,
                                    penaltyTargetPosition: penaltyCount > 0
                                        ? gameState.players
                                            .where((p) =>
                                                p.id ==
                                                nextPlayerId(state: gameState))
                                            .firstOrNull
                                            ?.tablePosition
                                        : null,
                                    compact: isMobile,
                                    onPenaltyIncreased: onPenaltyIncreased,
                                    scale: tableScale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: scaledBoardToActionBarGap),

              // ── Region 3: Action bar (fixed height) ───────────────────────
              SizedBox(
                height: scaledActionBarHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TurnTimerBar(
                      timeRemainingStream: timeRemainingStream,
                      totalDurationSeconds: turnTimerTotalSeconds,
                      isVisible: true,
                    ),
                    SizedBox(height: AppDimensions.sm * tableScale),
                    FloatingActionBarWidget(
                      activePlayerName: activePlayerDisplayName,
                      direction: gameState.direction,
                      canEndTurn: canEndTurn,
                      onEndTurn: onEndTurnTap,
                      pulseLocalTurn: isMyTurn,
                      nextTurnLabel: nextTurnLabel,
                      isLocalTurn: isLocalTurn,
                      hasAlreadyDeclared: hasAlreadyDeclaredLastCards,
                      lastCardsEnabled: true,
                      localHandSize: localHandSize,
                      onLastCards: onLastCardsTap,
                    ),
                  ],
                ),
              ),

              // ── Region 4: Local hand (fixed height) ───────────────────────
              _localHandRegionSlot(
                height: handRegionHeight,
                contentWidth: referenceHandWidth,
                child: PlayerZoneWidget(
                  key: playerZoneKeys[localPlayer.id],
                  player: localPlayer,
                  isLocalPlayer: true,
                  localAvatarFilePath: localAvatarFilePath,
                  isActiveTurn:
                      gameState.currentPlayerId == localPlayer.id,
                  compact: false,
                  scale: tableScale,
                  hasLastCardsDeclared: gameState.lastCardsDeclaredBy
                      .contains(localPlayer.id),
                  skipSeatHighlight:
                      skipHighlightPlayerIds.contains(localPlayer.id),
                  chatBubble: quickChatBubblesByPlayer[localPlayer.id],
                  onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                  child: finishedPlayerIds.contains(localPlayer.id)
                      ? _TournamentLocalStatusBanner(
                          isEliminated: _isEliminatedBadge(
                            tournamentStatusBadges[localPlayer.id],
                          ),
                        )
                      : PlayerHandWidget(
                          cards: isDealing
                              ? orderedHand
                                  .take(visibleCardCounts[
                                          localPlayer.id] ??
                                      0)
                                  .toList()
                              : orderedHand,
                          selectedCardId: selectedCardId,
                          onCardTap: onCardTap,
                          onReorder: onHandReorder,
                          enabled: isMyTurn && !isDealing,
                          cardWidth: handCardWidth,
                          invalidPlayShakeTrigger: handShakeTrigger,
                          scale: tableScale,
                        ),
                ),
              ),
              SizedBox(height: bottomPad),
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
  );

  PlayerModel? _opponentAt(List<PlayerModel> players, TablePosition pos) {
    try {
      return players.firstWhere((p) => p.tablePosition == pos);
    } catch (_) {
      return null;
    }
  }

  /// One rail slot per opponent actually seated — sized to `players.length -
  /// 1`, not a fixed six. Roster seat indices fill [kOpponentTablePositionCycle]
  /// contiguously from the start (see [tablePositionForSeatIndex]), so seat
  /// order stays stable (left, top, right, …) as players join/disconnect;
  /// there just aren't empty trailing slots wasting rail width for smaller
  /// tables.
  List<BustPlayerViewModel?> _adaptiveOpponentRailSlots({
    required List<PlayerModel> players,
    required GameState gameState,
    required Map<String, String> tournamentStatusBadges,
  }) {
    final opponentCount = math.max(0, players.length - 1);
    return List.generate(opponentCount, (slotIndex) {
      final pos = kOpponentTablePositionCycle[slotIndex];
      final player = _opponentAt(players, pos);
      if (player == null) return null;
      return BustPlayerViewModel.fromPlayerModel(
        player,
        currentPlayerId: gameState.currentPlayerId,
        isEliminated: false,
        isLocal: false,
        colorIndex: slotIndex,
        tournamentStatusBadge: tournamentStatusBadges[player.id],
      );
    });
  }

  bool _isEliminatedBadge(String? badgeText) {
    if (badgeText == null) return false;
    return badgeText.contains('Eliminated');
  }
}

// ── Dedicated landscape layout (mobile) ───────────────────────────────────────
//
// Fixed grid: opponent row → board (HUD + piles) → action bar → hand.
// Transient chrome lives in [_LandscapeTransientOverlayLayer].

class _LandscapeTableLayout extends StatelessWidget {
  const _LandscapeTableLayout({
    required this.gameState,
    required this.activePlayerDisplayName,
    required this.selectedCardId,
    required this.orderedHand,
    required this.isMyTurn,
    required this.penaltyCount,
    required this.canEndTurn,
    required this.isDealing,
    required this.visibleCardCounts,
    required this.drawPileKey,
    required this.discardPileKey,
    required this.hudKey,
    this.thinkingOpponentId,
    required this.playerZoneKeys,
    required this.localPlayer,
    required this.opponentRailSlots,
    required this.onCardTap,
    required this.onDrawTap,
    required this.onHandReorder,
    required this.onEndTurnTap,
    required this.discardPileCount,
    required this.reshuffleNotifier,
    required this.timeRemainingStream,
    required this.turnTimerTotalSeconds,
    required this.tournamentStatusBadges,
    required this.finishedPlayerIds,
    required this.aiConfigs,
    this.quickChatBubblesByPlayer = const {},
    this.onRemoveQuickChatBubble,
    this.nextTurnLabel,
    this.isLocalTurn = false,
    this.hasAlreadyDeclaredLastCards = false,
    this.localHandSize = 0,
    this.handShakeTrigger,
    this.onLastCardsTap,
    this.onPenaltyIncreased,
    this.skipHighlightPlayerIds = const <String>{},
    required this.onOpponentSlotTap,
    this.isRanked = false,
    this.localAvatarFilePath,
    this.tableScale = 1.0,
  });

  /// See [_TableLayout.tableScale]. Only ever non-1.0 in practice if this
  /// screen's landscape-mobile heuristic changes — landscape mobile is
  /// mobile by definition today, where tableScale is always 1.0.
  final double tableScale;

  final bool isRanked;

  final String? localAvatarFilePath;

  final VoidCallback? onPenaltyIncreased;

  final Set<String> skipHighlightPlayerIds;

  /// Parent closure: resolves the tapped rail slot back to the real
  /// [PlayerModel] and fires the online + firebase-uid gated tap callback.
  final void Function(BustPlayerViewModel player) onOpponentSlotTap;

  final String? nextTurnLabel;

  final bool isLocalTurn;
  final bool hasAlreadyDeclaredLastCards;
  final int localHandSize;
  final VoidCallback? onLastCardsTap;

  final ValueNotifier<int>? handShakeTrigger;

  final String activePlayerDisplayName;

  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;
  final void Function(String id)? onRemoveQuickChatBubble;

  final GameState gameState;
  final String? selectedCardId;
  final List<CardModel> orderedHand;
  final bool isMyTurn;
  final int penaltyCount;
  final bool canEndTurn;
  final bool isDealing;
  final Map<String, int> visibleCardCounts;
  final GlobalKey drawPileKey;
  final GlobalKey discardPileKey;
  final GlobalKey hudKey;
  final String? thinkingOpponentId;
  final Map<String, GlobalKey> playerZoneKeys;
  final PlayerModel localPlayer;
  final List<BustPlayerViewModel?> opponentRailSlots;
  final ValueChanged<String> onCardTap;
  final VoidCallback onDrawTap;
  final void Function(int oldIndex, int newIndex)? onHandReorder;
  final VoidCallback onEndTurnTap;
  final int discardPileCount;
  final ValueNotifier<bool>? reshuffleNotifier;
  final Stream<int>? timeRemainingStream;
  final int turnTimerTotalSeconds;
  final Map<String, String> tournamentStatusBadges;
  final Set<String> finishedPlayerIds;
  final Map<String, AiPlayerConfig> aiConfigs;

  @override
  Widget build(BuildContext context) {
    const handCardWidth = 40.0;
    const drawCardWidth = TablePortraitGrid.landscapeDrawPileCardWidth;
    const discardCardWidth = TablePortraitGrid.landscapeDiscardPileCardWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed footprint sized to a reference 9-card hand — same rationale
        // as portrait's referenceHandWidth.
        final referenceHandWidth = PlayerHandWidget.referenceFanWidth(
          maxWidth: constraints.maxWidth,
          cardWidth: handCardWidth,
          isCompact: true,
          scale: tableScale,
        );
        final hasTournamentBadges = tournamentStatusBadges.isNotEmpty;
        final opponentRowHeight = TablePortraitGrid.landscapeOpponentRowHeight(
          useRail: true,
          hasBadges: hasTournamentBadges,
        );
        final rankedBand =
            isRanked ? TablePortraitGrid.landscapeRankedBandHeight : 0.0;
        final handRegionHeight = math.min(
          TablePortraitGrid.landscapeHandRegionHeight,
          constraints.maxHeight -
              opponentRowHeight -
              TablePortraitGrid.landscapeActionBarHeight -
              rankedBand,
        ).clamp(80.0, TablePortraitGrid.landscapeHandRegionHeight);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.xs),
          child: Column(
            children: [
              // ── Region 1: Opponent seats (fixed height) ───────────────────
              if (isRanked)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Center(child: _RankedBadge(isMobile: true)),
                ),
              SizedBox(
                height: opponentRowHeight,
                child: BustPlayerRail(
                  slots: opponentRailSlots,
                  slotKeyBuilder: (player) => playerZoneKeys[player.id],
                  height: hasTournamentBadges
                      ? TablePortraitGrid.landscapeOpponentRailBaseHeightWithBadge
                      : TablePortraitGrid.landscapeOpponentRailBaseHeight,
                  compact: true,
                  scale: tableScale,
                  thinkingPlayerId: thinkingOpponentId,
                  quickChatBubblesByPlayer: quickChatBubblesByPlayer,
                  onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                  skipHighlightPlayerIds: skipHighlightPlayerIds,
                  onSlotTap: onOpponentSlotTap,
                ),
              ),

              // ── Region 2: Board — piles above HUD (Expanded) ──────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, boardConstraints) {
                    return ClipRect(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        // Anchor to the bottom, not the centre: the board's
                        // content (piles+HUD) is much shorter than this
                        // Expanded region, and centering it split the slack
                        // evenly — leaving a dead gap floating between the
                        // HUD and the action bar. Bottom-anchoring puts the
                        // piles flush against the action bar/hand below, and
                        // any leftover space becomes felt above, near the
                        // opponents, which reads as intentional breathing
                        // room rather than a broken void.
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: boardConstraints.maxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: 0,
                                child: Text(
                                  isDealing ? 'DEALING...' : 'DEALER',
                                  key: const ValueKey('dealer-status'),
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppDimensions.xs),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: TablePortraitGrid
                                        .drawPileFootprintWidth(drawCardWidth),
                                    height: TablePortraitGrid
                                        .drawPileFootprintHeight(drawCardWidth),
                                    child: DrawPileWidget(
                                      key: drawPileKey,
                                      cardCount: gameState.drawPileCount,
                                      onTap: onDrawTap,
                                      cardWidth: drawCardWidth,
                                      enabled: isMyTurn &&
                                          (gameState.actionsThisTurn == 0 ||
                                              gameState.queenSuitLock != null) &&
                                          selectedCardId == null &&
                                          !isDealing,
                                      reshuffleNotifier: reshuffleNotifier,
                                    ),
                                  ),
                                  const SizedBox(
                                      width: TablePortraitGrid.landscapePileGap),
                                  SizedBox(
                                    width: TablePortraitGrid
                                        .discardPileFootprintWidth(discardCardWidth),
                                    height: TablePortraitGrid
                                        .discardPileFootprintHeight(
                                            discardCardWidth),
                                    child: DiscardPileWidget(
                                      key: discardPileKey,
                                      topCard: gameState.discardTopCard,
                                      secondCard: gameState
                                              .discardPileHistory.isNotEmpty
                                          ? gameState.discardPileHistory.first
                                          : null,
                                      discardPileHistory:
                                          gameState.discardPileHistory,
                                      cardWidth: discardCardWidth,
                                      discardPileCount: discardPileCount,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: AppDimensions.sm * tableScale),
                              SizedBox(
                                key: hudKey,
                                width: boardConstraints.maxWidth,
                                child: Center(
                                  child: HudOverlayWidget(
                                    activeSuit: gameState.suitLock,
                                    queenSuitLock: gameState.queenSuitLock,
                                    penaltyCount: penaltyCount,
                                    penaltyTargetPosition: penaltyCount > 0
                                        ? gameState.players
                                            .where((p) =>
                                                p.id ==
                                                nextPlayerId(state: gameState))
                                            .firstOrNull
                                            ?.tablePosition
                                        : null,
                                    compact: true,
                                    onPenaltyIncreased: onPenaltyIncreased,
                                    scale: tableScale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(
                  height: TablePortraitGrid.landscapeBoardToActionBarGap),

              // ── Region 3: Action bar (fixed height) ───────────────────────
              SizedBox(
                height: TablePortraitGrid.landscapeActionBarHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TurnTimerBar(
                      timeRemainingStream: timeRemainingStream,
                      totalDurationSeconds: turnTimerTotalSeconds,
                      isVisible: true,
                      compact: true,
                    ),
                    const SizedBox(height: AppDimensions.xs),
                    FloatingActionBarWidget(
                      activePlayerName: activePlayerDisplayName,
                      direction: gameState.direction,
                      canEndTurn: canEndTurn,
                      onEndTurn: onEndTurnTap,
                      compact: true,
                      pulseLocalTurn: isMyTurn,
                      nextTurnLabel: nextTurnLabel,
                      isLocalTurn: isLocalTurn,
                      hasAlreadyDeclared: hasAlreadyDeclaredLastCards,
                      lastCardsEnabled: true,
                      localHandSize: localHandSize,
                      onLastCards: onLastCardsTap,
                    ),
                  ],
                ),
              ),

              // ── Region 4: Local hand (fixed height) ───────────────────────
              SizedBox(
                height: handRegionHeight,
                width: double.infinity,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    // Fixed width (reference 9-card hand) — same rationale as
                    // portrait: keeps the zone's footprint stable turn to turn.
                    child: SizedBox(
                      width: referenceHandWidth,
                      child: PlayerZoneWidget(
                        key: playerZoneKeys[localPlayer.id],
                        player: localPlayer,
                        isLocalPlayer: true,
                        localAvatarFilePath: localAvatarFilePath,
                        isActiveTurn:
                            gameState.currentPlayerId == localPlayer.id,
                        hasLastCardsDeclared: gameState.lastCardsDeclaredBy
                            .contains(localPlayer.id),
                        compact: true,
                        scale: tableScale,
                        skipSeatHighlight:
                            skipHighlightPlayerIds.contains(localPlayer.id),
                        chatBubble: quickChatBubblesByPlayer[localPlayer.id],
                        onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                        child: finishedPlayerIds.contains(localPlayer.id)
                            ? _TournamentLocalStatusBanner(
                                isEliminated: _isEliminatedBadge(
                                  tournamentStatusBadges[localPlayer.id],
                                ),
                              )
                            : PlayerHandWidget(
                                cards: isDealing
                                    ? orderedHand
                                        .take(visibleCardCounts[
                                                localPlayer.id] ??
                                            0)
                                        .toList()
                                    : orderedHand,
                                selectedCardId: selectedCardId,
                                onCardTap: onCardTap,
                                onReorder: onHandReorder,
                                enabled: isMyTurn && !isDealing,
                                cardWidth: handCardWidth,
                                invalidPlayShakeTrigger: handShakeTrigger,
                                scale: tableScale,
                              ),
                      ),
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
