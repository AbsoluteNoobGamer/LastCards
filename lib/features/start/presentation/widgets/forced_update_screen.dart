import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_update_suggestion.dart';

/// Blocking "you must update to keep playing" screen. Shown from
/// [SplashScreen] instead of the start screen when [ForcedUpdateGate] is
/// non-null — no back button, no way to dismiss except updating.
class ForcedUpdateScreen extends StatelessWidget {
  const ForcedUpdateScreen({super.key, required this.info});

  final ForcedUpdateInfo info;

  static const _gold = Color(0xFFC9A84C);
  static const _bg = Color(0xFF060e08);

  Future<void> _openStore() async {
    final uri = Uri.tryParse(info.storeUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update_rounded, color: _gold, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    'UPDATE REQUIRED',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cinzel(
                      color: _gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A new version of Last Cards is out. Update to keep '
                    'playing online — this build can no longer connect.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (info.remoteVersionLabel != null &&
                      info.remoteVersionLabel!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Latest version: ${info.remoteVersionLabel}',
                      style: GoogleFonts.inter(
                        color: _gold.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openStore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'UPDATE NOW',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
