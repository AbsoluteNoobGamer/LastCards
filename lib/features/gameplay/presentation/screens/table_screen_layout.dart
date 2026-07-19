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
    required this.matchModeLabel,
    this.showLiveChip = false,
    this.isHardcore = false,
    required this.eventTicker,
    this.eventTickerFallback,
    this.moveLogEntries = const <MoveLogEntry>[],
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
    this.comboLiveCount = 0,
  });

  /// Multiplier applied to every [TablePortraitGrid] reference size —
  /// 1.0 on phones, grows on tablets/desktop so chrome fills the extra
  /// canvas instead of leaving it as bare felt (see [TableScreen]'s
  /// top-level `tableScale` computation).
  final double tableScale;

  /// Cards played this turn — drives the soft-gold live `×N` chip under the
  /// info band (visible at [kComboLiveChipMinCards]+).
  final int comboLiveCount;

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

  /// Primary mode chip for [MatchBroadcastHeader] (`SOLO`, `CASUAL`, …).
  final String matchModeLabel;

  /// Online sessions show a pulsing LIVE pip in the match header.
  final bool showLiveChip;

  /// Hardcore (30s) urgency chip in the match header.
  final bool isHardcore;

  /// Reserved event ticker lane controller.
  final TableEventTickerController eventTicker;

  /// Idle fallback for the ticker (e.g. Last Cards strip summary).
  final String? eventTickerFallback;

  /// Persistent move log lines for the left FEED dock.
  final List<MoveLogEntry> moveLogEntries;

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
            matchModeLabel: matchModeLabel,
            showLiveChip: showLiveChip,
            isHardcore: isHardcore,
            eventTicker: eventTicker,
            eventTickerFallback: eventTickerFallback,
            moveLogEntries: moveLogEntries,
            localAvatarFilePath: localAvatarFilePath,
            tableScale: tableScale,
            comboLiveCount: comboLiveCount,
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
        // Settings/leave/chat/reactions FABs live above the action bar (see
        // table_screen.dart), not beside the hand — just a small edge margin.
        final chromeInset = AppDimensions.md;
        final handLaneWidth =
            math.max(160.0, effectiveWidth - chromeInset * 2);
        final handCardWidth =
            (handLaneWidth * (isMobile ? 0.12 : 0.1) * (isMobile ? 1.0 : tableScale))
                .clamp(44.0, 82.0 * tableScale);
        // Fixed footprint sized to a reference 9-card hand — the local hand
        // region stays the same size turn to turn regardless of actual hand
        // count, instead of visibly resizing as cards are played/drawn.
        final referenceHandWidth = PlayerHandWidget.referenceFanWidth(
          maxWidth: handLaneWidth,
          cardWidth: handCardWidth,
          isCompact: isMobile,
          scale: tableScale,
        );
        final hasTournamentBadges = tournamentStatusBadges.isNotEmpty;
        // Phones: skip the 96px chat reserve so seats don't steal the board.
        // Quick-chat may clip; moves/piles stay roomy.
        final railChatReserve = isMobile ? 0.0 : 96.0;
        final railBase = hasTournamentBadges
            ? TablePortraitGrid.opponentRailBaseHeightWithBadge
            : TablePortraitGrid.opponentRailBaseHeight;
        final cappedOpponentHeight =
            (railBase + railChatReserve) * tableScale;
        final matchHeaderBand =
            TablePortraitGrid.matchHeaderHeight * tableScale;
        // Capped below tableScale — see TableChromeLayout.chromeScaleFor.
        final chromeScale = TableChromeLayout.chromeScaleFor(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final infoBand =
            ArenaInfoBand.heightFor(compact: isMobile, scale: chromeScale) +
                8 * chromeScale;
        final hudSlot =
            HudOverlayWidget.slotHeight(compact: isMobile, scale: chromeScale);
        final bottomPad = isMobile ? 0.0 : AppDimensions.md;
        final scaledActionBarHeight =
            TablePortraitGrid.actionBarHeight * tableScale;
        // Info band + HUD live inside the board Expanded stack alongside the
        // hero stage (draw/discard piles) — they must be subtracted here too,
        // otherwise this budget only accounts for the chrome *outside* that
        // Expanded and can let handRegionHeight claim space the hero stage
        // actually needs, squeezing it toward 0 (which sends its FittedBox
        // scale to NaN — see _ArenaHeroStage's minHeight guard below).
        final handRegionHeight = math.min(
          TablePortraitGrid.handRegionHeight * tableScale,
          constraints.maxHeight -
              cappedOpponentHeight -
              scaledActionBarHeight -
              bottomPad -
              matchHeaderBand -
              infoBand -
              hudSlot -
              12 * tableScale,
        ).clamp(120.0, TablePortraitGrid.handRegionHeight * tableScale);

        final penaltyTarget = penaltyCount > 0
            ? gameState.players
                .where((p) => p.id == nextPlayerId(state: gameState))
                .firstOrNull
                ?.tablePosition
            : null;

        // Phone-first vertical table — full width board, no side docks.
        // Info band sits in a Stack above the piles so the expanded move log
        // paints over the hero stage (Column siblings would cover it).
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              MatchBroadcastHeader(
                modeLabel: matchModeLabel,
                showLive: showLiveChip,
                isHardcore: isHardcore,
                compact: isMobile,
                scale: tableScale,
              ),
              SizedBox(
                height: cappedOpponentHeight,
                child: BustPlayerRail(
                  slots: opponentRailSlots,
                  slotKeyBuilder: (player) => playerZoneKeys[player.id],
                  height: railBase,
                  scale: tableScale,
                  thinkingPlayerId: thinkingOpponentId,
                  quickChatBubblesByPlayer: quickChatBubblesByPlayer,
                  onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                  skipHighlightPlayerIds: skipHighlightPlayerIds,
                  onSlotTap: onOpponentSlotTap,
                  chatReserveHeight: railChatReserve,
                ),
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      children: [
                        // Reserve collapsed band height; overlay draws on top.
                        SizedBox(height: infoBand),
                        Expanded(
                          // A hard floor so this can never be squeezed to
                          // exactly 0 by a budgeting mistake elsewhere —
                          // _ArenaHeroStage's inner FittedBox divides by this
                          // height, and 0/0 resolves to a NaN scale that
                          // silently makes the draw/discard piles untappable
                          // and breaks card-flight/dealing animations.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48.0),
                            child: _ArenaHeroStage(
                              gameState: gameState,
                              isMyTurn: isMyTurn,
                              isDealing: isDealing,
                              selectedCardId: selectedCardId,
                              discardPileCount: discardPileCount,
                              drawPileKey: drawPileKey,
                              discardPileKey: discardPileKey,
                              onDrawTap: onDrawTap,
                              reshuffleNotifier: reshuffleNotifier,
                              compact: isMobile,
                              scale: tableScale,
                            ),
                          ),
                        ),
                        SizedBox(
                          key: hudKey,
                          height: hudSlot,
                          width: double.infinity,
                          child: Center(
                            child: HudOverlayWidget(
                              activeSuit: gameState.suitLock,
                              queenSuitLock: gameState.queenSuitLock,
                              penaltyCount: penaltyCount,
                              penaltyTargetPosition: penaltyTarget,
                              onPenaltyIncreased: onPenaltyIncreased,
                              compact: isMobile,
                              scale: chromeScale,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ArenaInfoBand(
                        moveLogEntries: moveLogEntries,
                        eventTicker: eventTicker,
                        eventTickerFallback: eventTickerFallback,
                        compact: isMobile,
                        scale: chromeScale,
                      ),
                    ),
                    Positioned(
                      top: ArenaInfoBand.heightFor(
                            compact: isMobile,
                            scale: chromeScale,
                          ) -
                          2 * chromeScale,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ComboLiveChip(
                          count: comboLiveCount,
                          scale: chromeScale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: chromeInset),
                child: _localHandRegionSlot(
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

/// Centre playfield: draw + discard side-by-side, scale-down to fit.
/// Suit/penalty live in the fixed HUD slot under this stage — never here.
class _ArenaHeroStage extends ConsumerWidget {
  const _ArenaHeroStage({
    required this.gameState,
    required this.isMyTurn,
    required this.isDealing,
    required this.selectedCardId,
    required this.discardPileCount,
    required this.drawPileKey,
    required this.discardPileKey,
    required this.onDrawTap,
    required this.reshuffleNotifier,
    required this.compact,
    required this.scale,
  });

  final GameState gameState;
  final bool isMyTurn;
  final bool isDealing;
  final String? selectedCardId;
  final int discardPileCount;
  final GlobalKey drawPileKey;
  final GlobalKey discardPileKey;
  final VoidCallback onDrawTap;
  final ValueNotifier<bool>? reshuffleNotifier;
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    // Prefer classic asymmetric sizes; FittedBox shrinks when the Expanded
    // slot is short so phones never paint a yellow overflow stripe.
    final discardW = (compact ? 104.0 : 120.0) * scale;
    final drawW = (compact ? 72.0 : 84.0) * scale;
    final gap = 20.0 * scale;
    final drawFootW = TablePortraitGrid.drawPileFootprintWidth(drawW);
    final drawFootH = TablePortraitGrid.drawPileFootprintHeight(drawW);
    final discardFootW = TablePortraitGrid.discardPileFootprintWidth(discardW);
    final discardFootH =
        TablePortraitGrid.discardPileFootprintHeight(discardW);
    final rowW = drawFootW + gap + discardFootW;
    final rowH = math.max(drawFootH, discardFootH);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 4 * scale),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18 * scale),
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.9,
            colors: [
              theme.accentPrimary.withValues(alpha: 0.05),
              theme.backgroundDeep.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0,
              child: Text(
                isDealing ? 'DEALING...' : 'DEALER',
                key: const ValueKey('dealer-status'),
              ),
            ),
            ClipRect(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: SizedBox(
                  width: rowW,
                  height: rowH,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: drawFootW,
                        height: drawFootH,
                        child: DrawPileWidget(
                          key: drawPileKey,
                          cardCount: gameState.drawPileCount,
                          onTap: onDrawTap,
                          cardWidth: drawW,
                          enabled: isMyTurn &&
                              (gameState.actionsThisTurn == 0 ||
                                  gameState.queenSuitLock != null) &&
                              selectedCardId == null &&
                              !isDealing,
                          reshuffleNotifier: reshuffleNotifier,
                        ),
                      ),
                      SizedBox(width: gap),
                      SizedBox(
                        width: discardFootW,
                        height: discardFootH,
                        child: DiscardPileWidget(
                          key: discardPileKey,
                          topCard: gameState.discardTopCard,
                          secondCard: gameState.discardPileHistory.isNotEmpty
                              ? gameState.discardPileHistory.first
                              : null,
                          discardPileHistory: gameState.discardPileHistory,
                          cardWidth: discardW,
                          discardPileCount: discardPileCount,
                        ),
                      ),
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

// Fixed grid: header → opponents → [docks + hero] → action → hand.

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
    required this.matchModeLabel,
    this.showLiveChip = false,
    this.isHardcore = false,
    required this.eventTicker,
    this.eventTickerFallback,
    this.moveLogEntries = const <MoveLogEntry>[],
    this.localAvatarFilePath,
    this.tableScale = 1.0,
    this.comboLiveCount = 0,
  });

  /// See [_TableLayout.tableScale]. Only ever non-1.0 in practice if this
  /// screen's landscape-mobile heuristic changes — landscape mobile is
  /// mobile by definition today, where tableScale is always 1.0.
  final double tableScale;

  /// See [_TableLayout.comboLiveCount].
  final int comboLiveCount;

  final bool isRanked;
  final String matchModeLabel;
  final bool showLiveChip;
  final bool isHardcore;
  final TableEventTickerController eventTicker;
  final String? eventTickerFallback;
  final List<MoveLogEntry> moveLogEntries;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Settings/leave/chat/reactions FABs live above the action bar (see
        // table_screen.dart), not beside the hand — just a small edge margin.
        final chromeInset = AppDimensions.md;
        final handLaneWidth =
            math.max(160.0, constraints.maxWidth - chromeInset * 2);
        final referenceHandWidth = PlayerHandWidget.referenceFanWidth(
          maxWidth: handLaneWidth,
          cardWidth: handCardWidth,
          isCompact: true,
          scale: tableScale,
        );
        final hasTournamentBadges = tournamentStatusBadges.isNotEmpty;
        final landscapeRailBase = hasTournamentBadges
            ? TablePortraitGrid.landscapeOpponentRailBaseHeightWithBadge
            : TablePortraitGrid.landscapeOpponentRailBaseHeight;
        final opponentRowHeight = landscapeRailBase * tableScale;
        const matchHeaderBand = TablePortraitGrid.matchHeaderHeight;
        // Capped below tableScale — see TableChromeLayout.chromeScaleFor.
        final chromeScale = TableChromeLayout.chromeScaleFor(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final infoBand =
            ArenaInfoBand.heightFor(compact: true, scale: chromeScale) +
                8 * chromeScale;
        final hudSlot =
            HudOverlayWidget.slotHeight(compact: true, scale: chromeScale);
        // See the portrait _TableLayout counterpart: infoBand/hudSlot live
        // inside the same board Expanded as the hero stage and must be
        // subtracted here too, or handRegionHeight can starve it to 0.
        final handRegionHeight = math.min(
          TablePortraitGrid.landscapeHandRegionHeight,
          constraints.maxHeight -
              opponentRowHeight -
              TablePortraitGrid.landscapeActionBarHeight -
              matchHeaderBand -
              infoBand -
              hudSlot,
        ).clamp(80.0, TablePortraitGrid.landscapeHandRegionHeight);

        final penaltyTarget = penaltyCount > 0
            ? gameState.players
                .where((p) => p.id == nextPlayerId(state: gameState))
                .firstOrNull
                ?.tablePosition
            : null;

        // Landscape mirrors portrait: info band stacked above piles.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.xs),
          child: Column(
            children: [
              MatchBroadcastHeader(
                modeLabel: matchModeLabel,
                showLive: showLiveChip,
                isHardcore: isHardcore,
                compact: true,
                scale: tableScale,
              ),
              SizedBox(
                height: opponentRowHeight,
                child: BustPlayerRail(
                  slots: opponentRailSlots,
                  slotKeyBuilder: (player) => playerZoneKeys[player.id],
                  height: landscapeRailBase,
                  compact: true,
                  scale: tableScale,
                  thinkingPlayerId: thinkingOpponentId,
                  quickChatBubblesByPlayer: quickChatBubblesByPlayer,
                  onRemoveQuickChatBubble: onRemoveQuickChatBubble,
                  skipHighlightPlayerIds: skipHighlightPlayerIds,
                  onSlotTap: onOpponentSlotTap,
                  chatReserveHeight: 0,
                ),
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      children: [
                        SizedBox(height: infoBand),
                        Expanded(
                          // See the portrait _TableLayout counterpart for why
                          // this floor exists.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48.0),
                            child: _ArenaHeroStage(
                              gameState: gameState,
                              isMyTurn: isMyTurn,
                              isDealing: isDealing,
                              selectedCardId: selectedCardId,
                              discardPileCount: discardPileCount,
                              drawPileKey: drawPileKey,
                              discardPileKey: discardPileKey,
                              onDrawTap: onDrawTap,
                              reshuffleNotifier: reshuffleNotifier,
                              compact: true,
                              scale: tableScale,
                            ),
                          ),
                        ),
                        SizedBox(
                          key: hudKey,
                          height: hudSlot,
                          width: double.infinity,
                          child: Center(
                            child: HudOverlayWidget(
                              activeSuit: gameState.suitLock,
                              queenSuitLock: gameState.queenSuitLock,
                              penaltyCount: penaltyCount,
                              penaltyTargetPosition: penaltyTarget,
                              onPenaltyIncreased: onPenaltyIncreased,
                              compact: true,
                              scale: chromeScale,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ArenaInfoBand(
                        moveLogEntries: moveLogEntries,
                        eventTicker: eventTicker,
                        eventTickerFallback: eventTickerFallback,
                        compact: true,
                        scale: chromeScale,
                      ),
                    ),
                    Positioned(
                      top: ArenaInfoBand.heightFor(
                            compact: true,
                            scale: chromeScale,
                          ) -
                          2 * chromeScale,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ComboLiveChip(
                          count: comboLiveCount,
                          scale: chromeScale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: chromeInset),
                child: SizedBox(
                  height: handRegionHeight,
                  width: double.infinity,
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
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

