import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_theme_data.dart';

/// "Remove Ads" purchase sheet — shows the store-localized price (once
/// loaded), a purchase button, and a restore-purchases link (required by App
/// Store guidelines for non-consumables).
void showRemoveAdsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const RemoveAdsSheet(),
  );
}

class RemoveAdsSheet extends ConsumerWidget {
  const RemoveAdsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final purchases = PurchaseService.instance;

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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                purchases.adsRemoved,
                purchases.purchaseInProgress,
                purchases.lastError,
              ]),
              builder: (context, _) {
                return Column(
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
                    const SizedBox(height: 20),
                    if (purchases.adsRemoved.value)
                      ..._ownedContent(theme)
                    else
                      ..._offerContent(context, theme, purchases),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _ownedContent(AppThemeData theme) {
    return [
      Center(
        child: Icon(Icons.check_circle_rounded, color: theme.accentPrimary, size: 48),
      ),
      const SizedBox(height: 12),
      Text(
        'Ads removed',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: theme.textPrimary,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Thanks for supporting Last Cards! No more banner, interstitial, '
        'or rewarded ads — skips and unlocks that used to need one are free.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
      ),
    ];
  }

  List<Widget> _offerContent(
    BuildContext context,
    AppThemeData theme,
    PurchaseService purchases,
  ) {
    final product = purchases.removeAdsProduct;
    final busy = purchases.purchaseInProgress.value;
    final error = purchases.lastError.value;

    return [
      Center(
        child: Icon(Icons.block_rounded, color: theme.accentPrimary, size: 40),
      ),
      const SizedBox(height: 12),
      Text(
        'Remove All Ads',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: theme.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'One-time purchase. No more banner, interstitial, or rewarded ads — '
        'tournament/Bust skips and the Locker XP unlock all become free.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
      ),
      const SizedBox(height: 20),
      if (error != null) ...[
        Text(
          error,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
        ),
        const SizedBox(height: 12),
      ],
      ElevatedButton(
        onPressed: busy || product == null ? null : purchases.buyRemoveAds,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentPrimary,
          foregroundColor: theme.backgroundDeep,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.backgroundDeep,
                ),
              )
            : Text(
                product != null
                    ? 'Buy for ${product.price}'
                    : (purchases.storeAvailable
                        ? 'Loading price…'
                        : 'Store unavailable'),
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: busy ? null : purchases.restorePurchases,
        child: Text(
          'Restore Purchases',
          style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
        ),
      ),
    ];
  }
}
