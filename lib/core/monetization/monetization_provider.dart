import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'monetization_config.dart';

const String _prefsKeyAdsRemoved = 'monetization_ads_removed';

class MonetizationState {
  final bool adsRemoved;
  /// Prefs + IAP bootstrap finished (safe to show ad UI without a one-frame flash).
  final bool ready;
  final ProductDetails? removeAdsProduct;
  final bool purchaseInFlight;
  final String? lastError;

  const MonetizationState({
    required this.adsRemoved,
    required this.ready,
    this.removeAdsProduct,
    this.purchaseInFlight = false,
    this.lastError,
  });

  factory MonetizationState.initial() => const MonetizationState(
        adsRemoved: false,
        ready: false,
      );

  MonetizationState copyWith({
    bool? adsRemoved,
    bool? ready,
    ProductDetails? removeAdsProduct,
    bool? purchaseInFlight,
    String? lastError,
    bool clearRemoveAdsProduct = false,
    bool clearError = false,
  }) {
    return MonetizationState(
      adsRemoved: adsRemoved ?? this.adsRemoved,
      ready: ready ?? this.ready,
      removeAdsProduct:
          clearRemoveAdsProduct ? null : (removeAdsProduct ?? this.removeAdsProduct),
      purchaseInFlight: purchaseInFlight ?? this.purchaseInFlight,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class MonetizationNotifier extends StateNotifier<MonetizationState> {
  MonetizationNotifier() : super(MonetizationState.initial()) {
    _init();
  }

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_prefsKeyAdsRemoved) ?? false;
    state = state.copyWith(adsRemoved: cached, ready: true);

    if (!kSupportsStoreMonetization()) {
      return;
    }

    final iap = InAppPurchase.instance;
    final available = await iap.isAvailable();
    if (!available) {
      if (kDebugMode) {
        debugPrint('Monetization: billing not available on this device.');
      }
      return;
    }

    _purchaseSub = iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Monetization: purchase stream error: $e');
        }
      },
    );

    await _refreshProductDetails();
  }

  Future<void> _refreshProductDetails() async {
    if (!kSupportsStoreMonetization()) return;
    final response = await InAppPurchase.instance
        .queryProductDetails({kRemoveAdsProductId});
    if (response.notFoundIDs.isNotEmpty && kDebugMode) {
      debugPrint('Monetization: product IDs not in store: ${response.notFoundIDs}');
    }
    if (response.productDetails.isEmpty) return;
    state = state.copyWith(removeAdsProduct: response.productDetails.first);
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != kRemoveAdsProductId) {
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(purchaseInFlight: true, clearError: true);
          break;
        case PurchaseStatus.error:
          state = state.copyWith(
            purchaseInFlight: false,
            lastError: purchase.error?.message ?? 'Purchase failed',
          );
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantRemoveAds(purchase);
          break;
        case PurchaseStatus.canceled:
          state = state.copyWith(purchaseInFlight: false);
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
          break;
      }
    }
  }

  Future<void> _grantRemoveAds(PurchaseDetails purchase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAdsRemoved, true);
    state = state.copyWith(
      adsRemoved: true,
      purchaseInFlight: false,
      clearError: true,
    );
    if (purchase.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(purchase);
    }
  }

  Future<void> purchaseRemoveAds() async {
    final product = state.removeAdsProduct;
    if (product == null || state.adsRemoved) return;
    state = state.copyWith(purchaseInFlight: true, clearError: true);
    final param = PurchaseParam(productDetails: product);
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Monetization: buyNonConsumable failed: $e\n$st');
      }
      state = state.copyWith(
        purchaseInFlight: false,
        lastError: e.toString(),
      );
    }
  }

  Future<void> restorePurchases() async {
    if (!kSupportsStoreMonetization()) return;
    state = state.copyWith(clearError: true);
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_purchaseSub?.cancel());
    super.dispose();
  }
}

final monetizationProvider =
    StateNotifierProvider<MonetizationNotifier, MonetizationState>((ref) {
  return MonetizationNotifier();
});
