import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_update_suggestion.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Non-blocking banner: “Update available” with store link and dismiss.
class OptionalUpdateBanner extends StatelessWidget {
  const OptionalUpdateBanner({
    super.key,
    required this.suggestion,
    required this.onDismiss,
    required this.accentColor,
    required this.panelColor,
  });

  final AppUpdateSuggestion suggestion;
  final VoidCallback onDismiss;
  final Color accentColor;
  final Color panelColor;

  Future<void> _openStore() async {
    final uri = Uri.tryParse(suggestion.storeUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: panelColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.system_update_rounded, color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update available',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (suggestion.remoteVersionLabel != null &&
                      suggestion.remoteVersionLabel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Latest version: ${suggestion.remoteVersionLabel}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _openStore,
                      style: TextButton.styleFrom(
                        foregroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'UPDATE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.65),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}
