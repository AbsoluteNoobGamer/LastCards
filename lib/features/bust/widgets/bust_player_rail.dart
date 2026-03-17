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
  });

  final List<BustPlayerViewModel> players;
  final Duration autoScrollDuration;
  final Curve autoScrollCurve;

  /// Optional builder that returns a [GlobalKey] for each player slot.
  /// Used by the dealing animation overlay to locate render targets.
  final GlobalKey? Function(BustPlayerViewModel player)? slotKeyBuilder;

  /// Rail height. Defaults to 96. Use 72 for compact landscape.
  final double? height;

  /// When true, uses compact slots (smaller avatar/name) for landscape.
  final bool compact;

  /// Active quick chat bubble per player id (most recent per player).
  final Map<String, QuickChatBubbleData> quickChatBubblesByPlayer;

  /// Callback to remove a bubble by id.
  final void Function(String id)? onRemoveQuickChatBubble;

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

  /// Extra height when chat bubbles are visible to prevent overflow.
  static const double _chatBubbleExtraHeight = 40;

  @override
  Widget build(BuildContext context) {
    final baseHeight = widget.height ?? 96;
    final hasChatBubbles = widget.quickChatBubblesByPlayer.isNotEmpty;
    final railHeight = hasChatBubbles
        ? baseHeight + _chatBubbleExtraHeight
        : baseHeight;
    final slotPadding = AppDimensions.xs;

    Widget buildSlot(BustPlayerViewModel player) {
      final slotKey = widget.slotKeyBuilder?.call(player);
      final chatBubble = widget.quickChatBubblesByPlayer[player.id];
      Widget slot = BustPlayerSlot(
        player: player,
        compact: widget.compact,
        chatBubble: chatBubble,
        onRemoveQuickChatBubble: widget.onRemoveQuickChatBubble,
      );
      if (slotKey != null) {
        slot = KeyedSubtree(key: slotKey, child: slot);
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: slotPadding),
        child: slot,
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
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
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
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
        itemCount: widget.players.length,
        itemBuilder: (context, index) => buildSlot(widget.players[index]),
      ),
    );
  }
}
