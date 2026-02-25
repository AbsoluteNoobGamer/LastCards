import 'package:flutter/material.dart';

import '../../domain/entities/card.dart';
import '../../domain/entities/move_log_entry.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/player_styles.dart';

class IntegratedGameLog extends StatefulWidget {
  const IntegratedGameLog({
    super.key,
    required this.entries,
    required this.activePlayerName,
    this.width = 220,
  });

  final List<MoveLogEntry> entries;
  final String activePlayerName;
  final double width;

  @override
  State<IntegratedGameLog> createState() => _IntegratedGameLogState();
}

class _IntegratedGameLogState extends State<IntegratedGameLog> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(IntegratedGameLog old) {
    super.didUpdateWidget(old);
    if (widget.entries.length > old.entries.length) {
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
    return Container(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'GAME LOG',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.goldLight.withValues(alpha: 0.7),
                fontWeight: FontWeight.w800,
                fontSize: 12, // slightly smaller header
                letterSpacing: 2.0,
              ),
            ),
          ),

          // Body
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                  .copyWith(bottom: 24),
              itemCount: widget.entries.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _MoveLogItem(
                      entry: widget.entries[index],
                      key: ValueKey(widget.entries[index].id)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveLogItem extends StatelessWidget {
  const _MoveLogItem({required this.entry, super.key});

  final MoveLogEntry entry;

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
    if (entry.isGameEvent) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
        child: Text(
          '${entry.eventText}',
          style: AppTypography.bodyText.copyWith(
              fontSize: 11,
              color: Colors.white54,
              fontStyle: FontStyle.italic,
              height: 1.3),
        ),
      );
    }

    final pName = entry.player ?? 'Unknown';
    final pColor = entry.playerPosition != null
        ? PlayerStyles.getColor(entry.playerPosition!)
        : Colors.white70;

    if (entry.isDraw) {
      final reason = entry.drawReason != null ? ' ${entry.drawReason}' : '';
      return Text.rich(TextSpan(children: [
        if (entry.playerPosition != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Icon(
                PlayerStyles.getIcon(entry.playerPosition!),
                size: 10,
                color: pColor,
              ),
            ),
          ),
        TextSpan(
            text: '$pName ',
            style: AppTypography.bodyText.copyWith(
                fontSize: 12, fontWeight: FontWeight.bold, color: pColor)),
        TextSpan(
            text:
                'drew ${entry.drawCount} card${entry.drawCount > 1 ? 's' : ''}$reason',
            style: AppTypography.bodyText
                .copyWith(fontSize: 12, color: Colors.white54, height: 1.3)),
      ]));
    }

    List<InlineSpan> spans = [
      if (entry.playerPosition != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Icon(
              PlayerStyles.getIcon(entry.playerPosition!),
              size: 10,
              color: pColor,
            ),
          ),
        ),
      TextSpan(
          text: '$pName ',
          style: AppTypography.bodyText.copyWith(
              fontSize: 12, fontWeight: FontWeight.bold, color: pColor)),
      TextSpan(
          text: 'played: ',
          style: AppTypography.bodyText
              .copyWith(fontSize: 12, color: Colors.white54, height: 1.3)),
    ];

    if (entry.cards.length == 1) {
      final card = entry.cards.first;
      spans.add(TextSpan(
          text: _formatCardName(card),
          style: AppTypography.bodyText
              .copyWith(fontSize: 12, color: Colors.white70)));

      if (card.rank == Rank.joker) {
        spans.add(TextSpan(
            text: ' → ${_formatEffectiveCard(card)}',
            style: AppTypography.bodyText.copyWith(
                fontSize: 12,
                color: AppColors.goldLight.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic)));
      }
    } else if (entry.cards.length > 1) {
      final card = entry.cards.first;
      spans.add(TextSpan(
          text: '${_formatCardName(card)}... ',
          style: AppTypography.bodyText
              .copyWith(fontSize: 12, color: Colors.white70)));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(children: spans),
      ),
    );
  }

  String _formatCardName(CardModel card) {
    if (card.rank == Rank.joker) return 'Joker';

    // Using standard suits mapping instead of emoji for cleaner visual matching request
    String suitChar = card.suit.symbol;
    String rankStr = card.rank.displayLabel;

    return '$rankStr$suitChar'; // E.g. "8♥"
  }

  String _formatEffectiveCard(CardModel card) {
    if (card.effectiveRank != null && card.effectiveSuit != null) {
      String rankStr = card.effectiveRank!.name;
      rankStr = rankStr[0].toUpperCase() + rankStr.substring(1);
      String suitStr = card.effectiveSuit!.name;
      suitStr = suitStr[0].toUpperCase() + suitStr.substring(1);
      return '$rankStr of $suitStr';
    }
    // If it's a joker just holding a suit lock
    if (card.effectiveSuit != null && card.effectiveRank == null) {
      String suitStr = card.effectiveSuit!.name;
      suitStr = suitStr[0].toUpperCase() + suitStr.substring(1);
      return 'Any $suitStr';
    }
    return '';
  }
}
