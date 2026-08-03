import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/currency_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_data.dart';
import '../widgets/buy_coins_sheet.dart';

/// The single home for every in-app purchase: "Remove Ads" and coin packs.
/// Reachable from the start screen's icon row, alongside Leaderboard,
/// Locker, Settings, and Rules.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final balance = ref.watch(currencyProvider).balance;
    final purchases = PurchaseService.instance;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundMid,
        elevation: 0,
        title: Text(
          'Store',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.accentPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            purchases.adsRemoved,
            purchases.purchaseInProgress,
            purchases.lastError,
          ]),
          builder: (context, _) {
            final busy = purchases.purchaseInProgress.value;
            final error = purchases.lastError.value;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel('COINS', theme: theme),
                  const SizedBox(height: 10),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on_rounded,
                            color: AppColors.goldPrimary, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          '$balance coins',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (error != null) ...[
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style:
                          GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final productId in PurchaseService.coinPackAmounts.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CoinPackTile(
                        productId: productId,
                        coins: PurchaseService.coinPackAmounts[productId]!,
                        theme: theme,
                        busy: busy,
                        onTap: () => purchases.buyCoinPack(productId),
                      ),
                    ),
                  const SizedBox(height: 28),
                  _SectionLabel('ADS', theme: theme),
                  const SizedBox(height: 10),
                  if (purchases.adsRemoved.value)
                    _RemoveAdsOwnedCard(theme: theme)
                  else
                    _RemoveAdsOfferCard(theme: theme, purchases: purchases),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: theme.textSecondary,
      ),
    );
  }
}

class _RemoveAdsOwnedCard extends StatelessWidget {
  const _RemoveAdsOwnedCard({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: theme.accentPrimary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ads removed — thanks for supporting Last Cards!',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveAdsOfferCard extends StatelessWidget {
  const _RemoveAdsOfferCard({required this.theme, required this.purchases});

  final AppThemeData theme;
  final PurchaseService purchases;

  @override
  Widget build(BuildContext context) {
    final product = purchases.removeAdsProduct;
    final busy = purchases.purchaseInProgress.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.block_rounded, color: theme.accentPrimary, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Remove All Ads',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'One-time purchase. No more banner, interstitial, or rewarded ads — '
            'tournament/Bust skips and the Locker XP unlock all become free.',
            style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: busy || product == null ? null : purchases.buyRemoveAds,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.backgroundDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    style:
                        GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
          TextButton(
            onPressed: busy ? null : purchases.restorePurchases,
            child: Text(
              'Restore Purchases',
              style: GoogleFonts.inter(fontSize: 13, color: theme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
