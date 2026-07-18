import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme_data.dart';
import '../../../../shared/moderation/chat_text_filter.dart';

/// One line in the live text transcript.
class LiveChatLine {
  const LiveChatLine({
    required this.playerId,
    required this.displayName,
    required this.text,
    required this.isLocal,
  });

  final String playerId;
  final String displayName;
  final String text;
  final bool isLocal;
}

/// Casino glass + gold free-text chat panel (lobby or in-game sheet).
class LiveTextChatPanel extends StatefulWidget {
  const LiveTextChatPanel({
    required this.theme,
    required this.messages,
    required this.onSend,
    this.tall = false,
    this.enabled = true,
    this.hintText = 'say something…',
    this.onReportOrBlock,
    this.autofocus = false,
    super.key,
  });

  final AppThemeData theme;
  final List<LiveChatLine> messages;
  final void Function(String text) onSend;
  final bool tall;
  final bool enabled;
  final String hintText;

  /// Focus the composer when the panel is first built (e.g. table Chat tab).
  final bool autofocus;

  /// Tapped a remote player's message; opens report/block UI. Local
  /// messages (own) are never tappable for this.
  final void Function(LiveChatLine line)? onReportOrBlock;

  @override
  State<LiveTextChatPanel> createState() => _LiveTextChatPanelState();
}

class _LiveTextChatPanelState extends State<LiveTextChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LiveTextChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.enabled) return;
    final raw = _controller.text;
    final filtered = sanitizeChatMessage(raw);
    if (!filtered.isAllowed || filtered.text == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            raw.trim().isEmpty
                ? 'Type a message first.'
                : 'Message not allowed.',
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }
    widget.onSend(filtered.text!);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final minHeight = widget.tall ? 220.0 : 140.0;
    final maxHeight = widget.tall ? 320.0 : 200.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Table sheet gives a bounded height; lobby scroll views do not.
        // In bounded mode the transcript must flex so the TextField stays
        // inside the hit-testable bounds (overflow paints but is not tappable).
        final expand = constraints.hasBoundedHeight;

        Widget messageBody = widget.messages.isEmpty
            ? Center(
                child: Text(
                  widget.enabled
                      ? 'Say hi — keep it friendly.'
                      : 'Join a room to chat.',
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                itemCount: widget.messages.length,
                itemBuilder: (context, i) {
                  final m = widget.messages[i];
                  final nameColor =
                      m.isLocal ? theme.accentPrimary : theme.textSecondary;
                  final canReport =
                      !m.isLocal && widget.onReportOrBlock != null;
                  final line = Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          color: theme.textPrimary,
                          fontSize: 13,
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(
                            text: '${m.displayName}  ',
                            style: TextStyle(
                              color: nameColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: m.text),
                        ],
                      ),
                    ),
                  );
                  if (!canReport) return line;
                  return InkWell(
                    onTap: () => widget.onReportOrBlock!(m),
                    child: line,
                  );
                },
              );

        final Widget messageArea = expand
            ? Expanded(child: messageBody)
            : ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: minHeight,
                  maxHeight: maxHeight,
                ),
                child: messageBody,
              );

        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.accentDark.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                'CHAT',
                style: GoogleFonts.inter(
                  color: theme.accentPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              messageArea,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      maxLength: kChatMessageMaxLength,
                      textInputAction: TextInputAction.send,
                      keyboardType: TextInputType.text,
                      onSubmitted: (_) => _submit(),
                      style: GoogleFonts.inter(
                        color: theme.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: widget.hintText,
                        hintStyle: GoogleFonts.inter(
                          color: theme.textSecondary.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.35),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.accentDark.withValues(alpha: 0.45),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.accentPrimary),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color:
                                theme.textSecondary.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: widget.enabled
                        ? theme.accentPrimary
                        : theme.textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: widget.enabled ? _submit : null,
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: widget.enabled
                              ? theme.backgroundDeep
                              : theme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
