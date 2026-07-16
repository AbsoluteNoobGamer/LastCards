import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/block_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/analytics_service.dart';

const List<String> kReportReasons = [
  'Harassment',
  'Hate speech / slurs',
  'Spam',
  'Inappropriate name',
  'Other',
];

/// Bottom sheet: report a chat message and/or block its sender.
///
/// [firebaseUid] is null for guest/AI opponents (no Firebase identity) —
/// in that case only reporting is offered, since there's nothing to block.
class ReportBlockSheet extends ConsumerStatefulWidget {
  const ReportBlockSheet({
    super.key,
    required this.firebaseUid,
    required this.displayName,
    this.messageText,
    this.roomCode,
    required this.isBlocked,
  });

  final String? firebaseUid;
  final String displayName;
  final String? messageText;
  final String? roomCode;
  final bool isBlocked;

  @override
  ConsumerState<ReportBlockSheet> createState() => _ReportBlockSheetState();
}

class _ReportBlockSheetState extends ConsumerState<ReportBlockSheet> {
  bool _showReasons = false;
  bool _submitting = false;
  String? _selectedReason;

  Future<void> _submitReport() async {
    final reason = _selectedReason;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(blockServiceProvider).reportUser(
            reportedUid: widget.firebaseUid,
            reportedDisplayName: widget.displayName,
            reason: reason,
            messageText: widget.messageText,
            roomCode: widget.roomCode,
          );
      AnalyticsService.instance.logUserReported(reason);
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Thanks — we’ll review this.')),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not send report: $e')),
        );
      }
    }
  }

  Future<void> _confirmBlock() async {
    final theme = ref.read(themeProvider).theme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.backgroundDeep,
        title: Text(
          widget.isBlocked ? 'Unblock player?' : 'Block player?',
          style: GoogleFonts.inter(
            color: theme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          widget.isBlocked
              ? 'You’ll see chat messages from "${widget.displayName}" again.'
              : 'You won’t see chat messages from "${widget.displayName}" anymore, '
                  'and any existing friendship will be removed.',
          style: GoogleFonts.inter(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.isBlocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = widget.firebaseUid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(blockServiceProvider);
      if (widget.isBlocked) {
        await service.unblockUser(uid);
      } else {
        await service.blockUser(uid);
        AnalyticsService.instance.logUserBlocked();
      }
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.isBlocked
                  ? '"${widget.displayName}" unblocked'
                  : '"${widget.displayName}" blocked',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not update block: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.backgroundDeep,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.35)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.textPrimary,
                  ),
                ),
                if (widget.messageText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"${widget.messageText}"',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!_showReasons) ...[
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showReasons = true),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Report'),
                  ),
                  if (widget.firebaseUid != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _confirmBlock,
                      icon: Icon(
                        widget.isBlocked
                            ? Icons.person_add_alt_1_outlined
                            : Icons.block_outlined,
                      ),
                      label: Text(widget.isBlocked ? 'Unblock' : 'Block'),
                    ),
                  ],
                ] else ...[
                  Text(
                    'Why are you reporting this?',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.textSecondary,
                    ),
                  ),
                  ...kReportReasons.map(
                    (reason) => ListTile(
                      onTap: () => setState(() => _selectedReason = reason),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _selectedReason == reason
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _selectedReason == reason
                            ? theme.accentPrimary
                            : theme.textSecondary,
                      ),
                      title: Text(
                        reason,
                        style: GoogleFonts.inter(color: theme.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed:
                        _selectedReason == null || _submitting ? null : _submitReport,
                    child: Text(_submitting ? 'Sending…' : 'Submit report'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
