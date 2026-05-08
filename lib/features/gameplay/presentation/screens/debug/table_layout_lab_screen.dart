import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/card.dart';
import '../../../../../core/models/ai_player_config.dart';
import '../../../../../core/models/game_state.dart';
import '../../../../../core/models/offline_game_state.dart';
import '../../../../../core/models/player_model.dart';
import '../../../../../core/providers/theme_provider.dart';
import '../../../../../shared/engine/game_turn_timer.dart';
import '../../../../../widgets/turn_timer_bar.dart';
import '../../widgets/discard_pile_widget.dart';
import '../../widgets/draw_pile_widget.dart';
import '../../widgets/floating_action_bar_widget.dart';
import '../../widgets/hud_overlay_widget.dart';
import '../../widgets/last_cards_table_strip.dart';
import '../../widgets/player_hand_widget.dart';
import '../../widgets/player_zone_widget.dart';

/// Debug-only sandbox: real table widgets on a draggable grid for layout mockups.
///
/// Open from the main menu (debug builds) → "Table lab" chip, or
/// `Navigator.pushNamed(context, AppRoutes.tableLayoutLab)`.
///
/// Drag using the dark **handle** chip above each block (not the inner widgets).
/// Use **Print layout** for normalized coordinates in the debug console.
class TableLayoutLabScreen extends ConsumerStatefulWidget {
  const TableLayoutLabScreen({super.key});

  @override
  ConsumerState<TableLayoutLabScreen> createState() =>
      _TableLayoutLabScreenState();
}

class _TableLayoutLabScreenState extends ConsumerState<TableLayoutLabScreen> {
  late final Stream<int> _timerStream;

  Offset? _opponentsPos;
  Offset? _lastCardsPos;
  Offset? _hudPos;
  Offset? _pilesPos;
  Offset? _timerFabPos;
  Offset? _handPos;

  late final GameState _gameState;
  late final AiPlayerConfig _cfgLeft;
  late final AiPlayerConfig _cfgTop;
  late final AiPlayerConfig _cfgRight;

  PlayerModel get _localPlayer => _gameState.players.firstWhere(
        (p) => p.tablePosition == TablePosition.bottom,
      );

  @override
  void initState() {
    super.initState();
    var t = 52;
    _timerStream =
        Stream<int>.periodic(const Duration(seconds: 1), (_) {
      t -= 1;
      if (t < 10) {
        t = 52;
      }
      return t;
    });

    final seeded = OfflineGameState.buildWithDeck(
      totalPlayers: 4,
      localDisplayName: 'You',
      aiNames: const {
        'player-2': 'Alex',
        'player-3': 'Sam',
        'player-4': 'Jordan',
      },
    );
    _gameState = seeded.$1;
    final cfgs =
        AiPlayerConfig.generateForGame(count: 3, seed: 4242);
    _cfgLeft = cfgs.singleWhere((c) => c.playerId == 'player-2');
    _cfgTop = cfgs.singleWhere((c) => c.playerId == 'player-3');
    _cfgRight = cfgs.singleWhere((c) => c.playerId == 'player-4');
  }

  void _ensureDefaults(Size size, EdgeInsets pad) {
    final w = size.width;
    final h = size.height;
    _opponentsPos ??= Offset(12, pad.top + 4);
    _lastCardsPos ??= Offset(math.max(8, w * 0.5 - 170), h * 0.18);
    _hudPos ??= Offset(math.max(8, w * 0.5 - 100), h * 0.26);
    _pilesPos ??= Offset(math.max(8, w * 0.5 - 120), h * 0.34);
    _timerFabPos ??= Offset(math.max(8, w * 0.5 - 200), h * 0.55);
    _handPos ??= Offset(12, h * 0.72);
  }

  void _printLayout(Size size, EdgeInsets pad) {
    final sw = size.width;
    final sh = size.height;
    void dump(String label, Offset o) {
      final fx = sw > 0 ? o.dx / sw : 0.0;
      final fy = sh > 0 ? o.dy / sh : 0.0;
      debugPrint(
        'TableLab $label: left=${o.dx.toStringAsFixed(1)}, top=${o.dy.toStringAsFixed(1)}, '
        'fx=${fx.toStringAsFixed(4)}, fy=${fy.toStringAsFixed(4)}',
      );
    }

    dump('safePadding', Offset(pad.left, pad.top));
    dump('opponents', _opponentsPos!);
    dump('lastCardsStrip', _lastCardsPos!);
    dump('hud', _hudPos!);
    dump('drawDiscard', _pilesPos!);
    dump('timerFab', _timerFabPos!);
    dump('hand', _handPos!);
    debugPrint('TableLab: copy the lines above — fx/fy are fraction of scaffold body.');
  }

  Widget _dragFrame({
    required String label,
    required Offset origin,
    required ValueChanged<Offset> onMoved,
    required Widget child,
  }) {
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onMoved(origin + d.delta),
            child: Material(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_indicator_rounded,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'Table layout lab must only run in debug mode.');
    final appTheme = ref.watch(themeProvider).theme;
    final topCard = _gameState.discardTopCard;
    final discardHistory = _gameState.discardPileHistory;

    PlayerModel opp(TablePosition pos) => _gameState.players
        .firstWhere((p) => p.tablePosition == pos, orElse: () => _localPlayer);

    final leftP = opp(TablePosition.left);
    final topP = opp(TablePosition.top);
    final rightP = opp(TablePosition.right);

    return Scaffold(
      backgroundColor: appTheme.backgroundDeep,
      appBar: AppBar(
        title: const Text('Table layout lab (debug)'),
        backgroundColor: appTheme.backgroundDeep,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip:
                'Log positions (fractions + dp) — see Flutter run / debug console',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () {
              final mq = MediaQuery.of(context);
              final bodySize = mq.size;
              _printLayout(bodySize, mq.padding);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Printed layout bounds to debug console.'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mq = MediaQuery.of(context);
          final bodySize =
              Size(constraints.maxWidth, constraints.maxHeight);
          _ensureDefaults(bodySize, mq.padding);

          final handCardWidth =
              (bodySize.width * 0.12).clamp(44.0, 82.0);

          Widget opponentsRow(double width) {
            return SizedBox(
              width: math.min(width, bodySize.width - 24),
              height: 112,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: PlayerZoneWidget(
                        player: leftP,
                        isActiveTurn: _gameState.currentPlayerId == leftP.id,
                        aiConfig: _cfgLeft,
                        hasLastCardsDeclared: false,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: PlayerZoneWidget(
                        player: topP,
                        isActiveTurn: _gameState.currentPlayerId == topP.id,
                        aiConfig: _cfgTop,
                        hasLastCardsDeclared:
                            _gameState.lastCardsDeclaredBy.contains(topP.id),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: PlayerZoneWidget(
                        player: rightP,
                        isActiveTurn: _gameState.currentPlayerId == rightP.id,
                        aiConfig: _cfgRight,
                        hasLastCardsDeclared: false,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Opacity(
                      opacity: 0.18,
                      child: Text(
                        'Portrait works best • Drag the dark handle above each chunk\n'
                        'Tap the bug icon in the app bar to print layout numbers.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: appTheme.accentPrimary,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              /// Opponents
              _dragFrame(
                label: 'OPPONENTS',
                origin: _opponentsPos!,
                onMoved: (o) => setState(() => _opponentsPos = o),
                child: opponentsRow(bodySize.width - 24),
              ),

              /// Last cards strip (declared seat)
              _dragFrame(
                label: 'LAST CARDS strip',
                origin: _lastCardsPos!,
                onMoved: (o) => setState(() => _lastCardsPos = o),
                child: SizedBox(
                  width: math.min(360.0, bodySize.width - 16),
                  child: LastCardsTableStrip(
                    players: _gameState.players,
                    lastCardsDeclaredBy: {topP.id},
                  ),
                ),
              ),

              /// HUD badges
              _dragFrame(
                label: 'HUD (penalty / suit locks)',
                origin: _hudPos!,
                onMoved: (o) => setState(() => _hudPos = o),
                child: HudOverlayWidget(
                  activeSuit: topCard?.effectiveSuit,
                  queenSuitLock: Suit.diamonds,
                  penaltyCount: 8,
                  penaltyTargetPosition: TablePosition.top,
                ),
              ),

              /// Draw / discard
              _dragFrame(
                label: 'DRAW + DISCARD',
                origin: _pilesPos!,
                onMoved: (o) => setState(() => _pilesPos = o),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 145,
                      child: OverflowBox(
                        maxWidth: double.infinity,
                        maxHeight: double.infinity,
                        alignment: Alignment.center,
                        child: DrawPileWidget(
                          cardCount: _gameState.drawPileCount,
                          enabled: true,
                          cardWidth: 100,
                          onTap: () {},
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
                        alignment: Alignment.center,
                        child: DiscardPileWidget(
                          topCard: topCard,
                          secondCard: discardHistory.isNotEmpty
                              ? discardHistory.first
                              : null,
                          discardPileHistory: discardHistory,
                          cardWidth: 100,
                          discardPileCount:
                              discardHistory.length + (topCard != null ? 1 : 0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// Timer + FAB
              _dragFrame(
                label: 'TIMER + ACTIONS',
                origin: _timerFabPos!,
                onMoved: (o) => setState(() => _timerFabPos = o),
                child: SizedBox(
                  width: math.min(408.0, bodySize.width - 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TurnTimerBar(
                        timeRemainingStream: _timerStream,
                        totalDurationSeconds:
                            GameTurnTimer.defaultDurationSeconds,
                        isVisible: true,
                      ),
                      const SizedBox(height: 8),
                      FloatingActionBarWidget(
                        activePlayerName: 'Sam',
                        direction: PlayDirection.clockwise,
                        canEndTurn: true,
                        onEndTurn: () {},
                        pulseLocalTurn: true,
                        nextTurnLabel: 'After you: Alex ↑',
                        isLocalTurn: true,
                        hasAlreadyDeclared: false,
                        lastCardsEnabled: true,
                        localHandSize: _localPlayer.hand.length,
                        onLastCards: () {},
                      ),
                    ],
                  ),
                ),
              ),

              /// Local hand
              _dragFrame(
                label: 'YOUR HAND',
                origin: _handPos!,
                onMoved: (o) => setState(() => _handPos = o),
                child: SizedBox(
                  width: math.max(280.0, bodySize.width - 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PlayerZoneWidget(
                        player: _localPlayer,
                        isLocalPlayer: true,
                        isActiveTurn: true,
                        hasLastCardsDeclared: _gameState.lastCardsDeclaredBy
                            .contains(_localPlayer.id),
                        chatBubble: null,
                        child: PlayerHandWidget(
                          cards: _localPlayer.hand,
                          selectedCardId: _localPlayer.hand.firstOrNull?.id,
                          onCardTap: (_) {},
                          onReorder: (_, __) {},
                          enabled: true,
                          cardWidth: handCardWidth,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
