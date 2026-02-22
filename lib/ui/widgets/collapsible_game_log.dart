import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/models/card_model.dart';
import '../../core/models/move_log_entry.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_widget.dart';

class GlowContainer extends StatelessWidget {
  const GlowContainer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a2a1e).withValues(alpha: 0.90),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFFFFD700), // gold aura
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset(0, 0),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5), // outer shadow
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: child,
    );
  }
}

class CollapsibleGameLog extends StatefulWidget {
  const CollapsibleGameLog({
    super.key,
    required this.entries,
    required this.activePlayerName,
    required this.onClear,
  });

  final List<MoveLogEntry> entries;
  final String activePlayerName;
  final VoidCallback onClear;

  @override
  State<CollapsibleGameLog> createState() => _CollapsibleGameLogState();
}

class _CollapsibleGameLogState extends State<CollapsibleGameLog> with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(CollapsibleGameLog old) {
    super.didUpdateWidget(old);
    if (widget.entries.length > old.entries.length && _isExpanded) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine responsive dimensions
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;
    final isMobile = size.shortestSide < 600;

    double expectedWidth = size.width * 0.20;
    if (isMobile) {
      expectedWidth = isPortrait ? 300 : math.min(size.width * 0.35, 300);
    } else {
      expectedWidth = size.width * 0.30;
    }
    expectedWidth = expectedWidth.clamp(280.0, 360.0);

    double expectedHeight;
    if (isPortrait && isMobile) {
      expectedHeight = size.height * 0.85;
    } else if (!isPortrait && isMobile) {
      expectedHeight = size.height * 0.85;
    } else {
      expectedHeight = size.height - 72; // Full height minus status bar roughly
    }

    final height = _isExpanded ? expectedHeight : 60.0;

    // Slide-in on mount
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(-expectedWidth * (1 - value), 0),
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        width: expectedWidth,
        height: height,
        child: RepaintBoundary(
          child: GlowContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.goldDark.withValues(alpha: 0.6),
                          AppColors.goldDark.withValues(alpha: 0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topRight: const Radius.circular(16),
                        bottomRight: Radius.circular(_isExpanded ? 0 : 16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📜 GAME LOG',
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.goldLight,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        AnimatedRotation(
                          turns: _isExpanded ? 0 : 0.5,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: AppColors.goldLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Body
                if (_isExpanded)
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _isExpanded ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Current Turn
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC9A84C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.activePlayerName == 'YOUR TURN' 
                                  ? '👑 YOUR TURN' 
                                  : '⏳ ${widget.activePlayerName}\'s turn',
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                          // Log Entries view
                          Expanded(
                            child: Stack(
                              children: [
                                ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(bottom: 60),
                                  itemCount: widget.entries.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: _MoveLogItem(entry: widget.entries[index], key: ValueKey(widget.entries[index].id)),
                                    );
                                  },
                                ),
                                
                                // Fade overlay with dynamic text
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 60,
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            const Color(0xFF1a2a1e).withValues(alpha: 0.95),
                                          ],
                                        ),
                                      ),
                                      alignment: Alignment.bottomCenter,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        widget.entries.length > 8 ? '⋮ ${widget.entries.length - 8} more...' : '',
                                        style: AppTypography.labelSmall.copyWith(color: AppColors.goldLight.withValues(alpha: 0.7)),
                                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveLogItem extends StatelessWidget {
  const _MoveLogItem({required this.entry, super.key});

  final MoveLogEntry entry;

  void _showCardPopup(BuildContext context, List<CardModel> cards) {
    if (cards.isEmpty) return;
    
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: cards.map((c) => CardWidget(card: c, width: AppDimensions.cardWidthLarge, faceUp: true)).toList(),
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    // Slide-in for new entries
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 15 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // ↻ Direction reversed
    if (entry.isGameEvent) {
      return Text(
        '${entry.eventText}',
        style: AppTypography.bodyText.copyWith(color: AppColors.blueAccent, fontStyle: FontStyle.italic, height: 1.4),
      );
    }

    final pName = entry.player ?? 'Unknown';

    if (entry.isDraw) {
      final reason = entry.drawReason != null ? ' ${entry.drawReason}' : '';
      return Text(
        '$pName draws ${entry.drawCount}$reason',
        style: AppTypography.bodyText.copyWith(color: const Color(0xFF9E9E9E), height: 1.4), // Player moves: gray text
      );
    }

    final sparkle = entry.isSpecial ? ' ✨' : '';
    
    List<InlineSpan> spans = [
      TextSpan(text: '$pName plays ', style: AppTypography.bodyText.copyWith(color: const Color(0xFF9E9E9E), height: 1.4)),
    ];

    if (entry.cards.length == 1) {
      spans.add(_cardSpan(entry.cards.first));
    } else if (entry.cards.length > 1) {
      spans.add(_cardSpan(entry.cards.first));
      spans.add(const TextSpan(text: '→...'));
    }

    if (sparkle.isNotEmpty) {
      spans.add(TextSpan(text: sparkle));
    }

    return GestureDetector(
      onLongPress: () => _showCardPopup(context, entry.cards),
      child: RichText(
        text: TextSpan(children: spans),
      ),
    );
  }

  InlineSpan _cardSpan(CardModel card) {
    // small card icons (24x36px inline)
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        width: 24,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: IgnorePointer(
          child: CardWidget(card: card, width: 24, faceUp: true),
        ),
      ),
    );
  }
}
