import 'package:flutter/material.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import '../models/bust_player_view_model.dart';
import 'bust_player_slot.dart';

class BustPlayerRail extends StatefulWidget {
  const BustPlayerRail({
    super.key,
    required this.players,
    this.autoScrollDuration = const Duration(milliseconds: 350),
    this.autoScrollCurve = Curves.easeOutCubic,
    this.slotKeyBuilder,
  });

  final List<BustPlayerViewModel> players;
  final Duration autoScrollDuration;
  final Curve autoScrollCurve;

  /// Optional builder that returns a [GlobalKey] for each player slot.
  /// Used by the dealing animation overlay to locate render targets.
  final GlobalKey? Function(BustPlayerViewModel player)? slotKeyBuilder;

  @override
  State<BustPlayerRail> createState() => _BustPlayerRailState();
}

class _BustPlayerRailState extends State<BustPlayerRail> {
  late final ScrollController _scrollController;
  int? _lastActiveIndex;

  static const double _itemWidth = 88.0;

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
    double target = activeIndex * _itemWidth;
    target -= (viewportWidth / 2) - (_itemWidth / 2);
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
        itemCount: widget.players.length,
        itemBuilder: (context, index) {
          final player = widget.players[index];
          final slotKey = widget.slotKeyBuilder?.call(player);
          Widget slot = BustPlayerSlot(player: player);
          if (slotKey != null) {
            slot = KeyedSubtree(key: slotKey, child: slot);
          }
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimensions.xs),
            child: slot,
          );
        },
      ),
    );
  }
}
