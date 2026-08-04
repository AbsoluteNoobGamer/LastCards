import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/currency_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/purchase_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Bottom sheet shown when tapping any locked Locker cosmetic — offers a
/// coin unlock and/or a real-money cash unlock, whichever the item supports
/// and the player is currently eligible for. Shared by every tab (themes,
/// card backs, jokers, avatars, reactions).
Future<void> showUnlockCosmeticSheet(
  BuildContext context, {
  required String name,
  required int unlockLevel,
  int? coinCost,
  String? cashProductId,
  bool cashGateSatisfied = true,
  String cashGateMessage =
      'Unlock the one before this first to buy it with real money.',
  required Future<void> Function() onCoinGranted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UnlockCosmeticSheet(
      name: name,
      unlockLevel: unlockLevel,
      coinCost: coinCost,
      cashProductId: cashProductId,
      cashGateSatisfied: cashGateSatisfied,
      cashGateMessage: cashGateMessage,
      onCoinGranted: onCoinGranted,
    ),
  );
}

class _UnlockCosmeticSheet extends ConsumerWidget {
  const _UnlockCosmeticSheet({
    required this.name,
    required this.unlockLevel,
    required this.coinCost,
    required this.cashProductId,
    required this.cashGateSatisfied,
    required this.cashGateMessage,
    required this.onCoinGranted,
  });

  final String name;
  final int unlockLevel;
  final int? coinCost;
  final String? cashProductId;
  final bool cashGateSatisfied;
  final String cashGateMessage;
  final Future<void> Function() onCoinGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTheme = ref.watch(themeProvider).theme;
    final balance = ref.watch(currencyProvider).balance;
    final purchases = PurchaseService.instance;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: appTheme.backgroundDeep,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border:
              Border.all(color: appTheme.accentPrimary.withValues(alpha: 0.35)),
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
                          color: appTheme.textSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: appTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Reach level $unlockLevel to unlock for free, '
                      'or unlock it right now:',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: appTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (error != null) ...[
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (coinCost != null)
                      _UnlockOptionButton(
                        icon: Icons.monetization_on_rounded,
                        iconColor: AppColors.goldPrimary,
                        label: '$coinCost coins',
                        enabled: balance >= coinCost! && !busy,
                        onTap: () async {
                          final spent = await ref
                              .read(currencyProvider.notifier)
                              .spendCoins(coinCost!);
                          if (!spent) return;
                          HapticFeedback.selectionClick();
                          await onCoinGranted();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    if (coinCost != null && cashProductId != null)
                      const SizedBox(height: 10),
                    if (cashProductId != null)
                      if (!cashGateSatisfied)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            cashGateMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: appTheme.textSecondary,
                            ),
                          ),
                        )
                      else
                        _UnlockOptionButton(
                          icon: Icons.shopping_bag_rounded,
                          iconColor: appTheme.accentPrimary,
                          label: purchases.cosmeticUnlockProducts[cashProductId]
                                      ?.price !=
                                  null
                              ? 'Buy for ${purchases.cosmeticUnlockProducts[cashProductId]!.price}'
                              : (purchases.storeAvailable
                                  ? 'Loading price…'
                                  : 'Store unavailable'),
                          enabled: !busy &&
                              purchases.cosmeticUnlockProducts
                                  .containsKey(cashProductId),
                          onTap: () =>
                              purchases.buyCosmeticUnlock(cashProductId!),
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

class _UnlockOptionButton extends StatelessWidget {
  const _UnlockOptionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: iconColor.withValues(alpha: enabled ? 0.5 : 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: iconColor.withValues(alpha: enabled ? 1 : 0.4),
                  size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
