import 'package:flutter/material.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_zone_widget.dart';
import '../models/bust_player_view_model.dart';
import 'bust_player_slot.dart';

class BustPlayerRail extends StatefulWidget {
  const BustPlayerRail({
    super.key,
    required this.players,
    this.autoScrollDuration = const Duration(milliseconds: 350),
    this.autoScrollCurve = Curves.easeOutCubic,
    this.slotKeyBuilder,
    this.height,
    this.compact = false,
    this.quickChatBubblesByPlayer = const {},
    this.onRemoveQuickChatBubble,
    this.thinkingPlayerId,
    this.skipHighlightPlayerIds = const <String>{},
  });

  final List<BustPlayerViewModel> players;

  /// When non-null, that player's slot shows a thinking indicator.
  final String? thinkingPlayerId;
  final Duration autoScrollDuration;
  final Curve autoScrollCurve;

  /// Optional builder that returns a [GlobalKey] for each player slot.
  /// Used by the dealing animation overlay to locate render targets.
  final GlobalKey? Function(BustPlayerViewModel player)? slotKeyBuilder;

  /// Base slot height before reserved quick-chat space. Defaults to 96; use 72
  /// for compact landscape. Final rail height is this + fixed chat reservation.
  final double? height;

  /// When true, uses compact slots (smaller avatar/name) for landscape.
  final bool compact;

  /// Active quick chat bubble per player id (most recent per player).
  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;

  /// Callback to remove a bubble by id.
  final void Function(String id)? onRemoveQuickChatBubble;

  /// Player IDs to show brief skip (Eight) dim/pause on the rail slot.
  final Set<String> skipHighlightPlayerIds;

  @override
  State<BustPlayerRail> createState() => _BustPlayerRailState();
}

class _BustPlayerRailState extends State<BustPlayerRail> {
  late final ScrollController _scrollController;
  int? _lastActiveIndex;

  static const double _itemWidth = 88.0;
  static const double _itemWidthCompact = 56.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(BustPlayerRail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.players.isEmpty) return;
    if (!_scrollController.hasClients) return;

    final activeIndex =
        widget.players.indexWhere((p) => p.isActive);
    if (activeIndex == -1) return;
    if (activeIndex == _lastActiveIndex) return;

    _lastActiveIndex = activeIndex;

    final viewportWidth =
        _scrollController.position.viewportDimension;
    final itemW = widget.compact ? _itemWidthCompact : _itemWidth;
    double target = activeIndex * itemW;
    target -= (viewportWidth / 2) - (itemW / 2);
    target = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      target,
      duration: widget.autoScrollDuration,
      curve: widget.autoScrollCurve,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Reserved **always** so quick-chat bubbles (below names) never change rail
  /// height — move log, piles, and turn bar stay fixed when chat appears/updates.
  /// Must fit avatar + label + [QuickChatBubble] under [ListView] cross-axis max.
  static const double _chatBubbleReservedHeight = 96;

  @override
  Widget build(BuildContext context) {
    final baseHeight = widget.height ?? 96;
    final railHeight = baseHeight + _chatBubbleReservedHeight;
    final slotPadding = AppDimensions.xs;

    Widget buildSlot(BustPlayerViewModel player) {
      final slotKey = widget.slotKeyBuilder?.call(player);
      final chatBubble = widget.quickChatBubblesByPlayer[player.id];
      Widget slot = BustPlayerSlot(
        player: player,
        compact: widget.compact,
        showThinking: widget.thinkingPlayerId == player.id,
        chatBubble: chatBubble,
        onRemoveQuickChatBubble: widget.onRemoveQuickChatBubble,
        skipSeatHighlight: widget.skipHighlightPlayerIds.contains(player.id),
      );
      if (slotKey != null) {
        slot = KeyedSubtree(key: slotKey, child: slot);
      }
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: slotPadding),
          child: slot,
        ),
      );
    }

    // When compact (landscape), center the rail; when content fits, it stays centred.
    if (widget.compact) {
      return SizedBox(
        height: railHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final player in widget.players) buildSlot(player),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: railHeight,
      child: ListView.builder(
        clipBehavior: Clip.none,
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
        itemCount: widget.players.length,
        itemBuilder: (context, index) => buildSlot(widget.players[index]),
      ),
    );
  }
}
