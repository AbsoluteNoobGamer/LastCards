import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/currency_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_data.dart';

/// Coin-pack purchase sheet — one tile per [PurchaseService.coinPackAmounts]
/// entry, each showing the store-localized price (once loaded) and a buy
/// button.
void showBuyCoinsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const BuyCoinsSheet(),
  );
}

class BuyCoinsSheet extends ConsumerWidget {
  const BuyCoinsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final balance = ref.watch(currencyProvider).balance;
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
                purchases.purchaseInProgress,
                purchases.lastError,
              ]),
              builder: (context, _) {
                final busy = purchases.purchaseInProgress.value;
                final error = purchases.lastError.value;
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
                    const SizedBox(height: 4),
                    Text(
                      'Get more coins',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (error != null) ...[
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class CoinPackTile extends StatelessWidget {
  const CoinPackTile({
    super.key,
    required this.productId,
    required this.coins,
    required this.theme,
    required this.busy,
    required this.onTap,
  });

  final String productId;
  final int coins;
  final AppThemeData theme;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = PurchaseService.instance.coinPackProducts[productId];
    return Material(
      color: theme.surfacePanel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: busy || product == null ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.accentPrimary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.monetization_on_rounded,
                  color: AppColors.goldPrimary, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$coins coins',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary,
                  ),
                ),
              ),
              Text(
                product != null
                    ? product.price
                    : (PurchaseService.instance.storeAvailable
                        ? 'Loading…'
                        : 'Unavailable'),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.accentPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
