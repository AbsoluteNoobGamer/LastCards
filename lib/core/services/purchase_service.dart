import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Handles the single "Remove Ads" non-consumable in-app purchase via
/// Apple Pay / Google Play Billing (through the `in_app_purchase` plugin).
///
/// The entitlement is cached locally (SharedPreferences, for instant
/// availability and signed-out/guest play) and mirrored to the signed-in
/// user's `users/{uid}` Firestore doc, so it carries across devices and
/// reinstalls once they sign back in — matching how profile/stats already
/// sync in this app.
///
/// SETUP REQUIRED before this works for real purchases: create a
/// non-consumable in-app purchase product with the exact ID
/// [removeAdsProductId] in both App Store Connect and the Google Play
/// Console (matching price tiers on each). Until that product exists,
/// [removeAdsProduct] stays null and [buyRemoveAds] reports an error.
///
/// The same applies to the consumable coin-pack products — see
/// [coinPackAmounts]. For local iOS Simulator testing without any of that
/// store-side setup, this project ships `ios/Runner/Configuration.storekit`
/// (wired into the Runner scheme's Launch Action) with matching test
/// products, so `flutter run` on a simulator can exercise the full purchase
/// flow via Xcode's StoreKit Testing — no App Store Connect account needed.
/// That config is debug/simulator-only and never ships to production.
class PurchaseService {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  /// Must match the non-consumable product ID configured in App Store
  /// Connect and Google Play Console.
  static const String removeAdsProductId = 'remove_ads';

  /// Consumable coin-pack product IDs, mapped to the coins each grants.
  /// Must match consumable products configured with these exact IDs in App
  /// Store Connect and Google Play Console.
  static const Map<String, int> coinPackAmounts = {
    'coins_small_100': 100,
    'coins_medium_550': 550,
    'coins_large_1200': 1200,
  };

  static const String _prefsKey = 'ads_removed';
  static const String _usersCollection = 'users';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  StreamSubscription<User?>? _authSub;
  bool _initialized = false;
  int _coinPackGrantNonce = 0;

  /// True once the store confirmed it can take payments on this device.
  bool storeAvailable = false;

  /// Localized product (price/title) once loaded from the store. Null until
  /// [init] finishes (or if the product isn't configured in the store yet).
  ProductDetails? removeAdsProduct;

  /// Localized coin-pack products once loaded from the store, keyed by
  /// [coinPackAmounts]'s product IDs. Empty until [init] finishes (or for
  /// any pack not yet configured in the store).
  final Map<String, ProductDetails> coinPackProducts = {};

  /// Fires once per completed coin-pack purchase. [CurrencyNotifier] listens
  /// and credits the wallet — kept as a plain event here (rather than a
  /// direct call) since this service has no Riverpod `ref` to reach it with.
  final ValueNotifier<CoinPackGrant?> lastCoinPackGrant =
      ValueNotifier<CoinPackGrant?>(null);

  /// Current entitlement — [BannerAdSlot], [AdsService], and every
  /// rewarded-ad-gated feature check this before showing an ad.
  final ValueNotifier<bool> adsRemoved = ValueNotifier<bool>(false);

  /// True while a purchase/restore is in flight — drives a loading spinner
  /// on the "Remove Ads" button so it can't be double-tapped.
  final ValueNotifier<bool> purchaseInProgress = ValueNotifier<bool>(false);

  /// User-facing message from the most recent failed purchase/restore, if
  /// any. Cleared at the start of the next attempt.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    adsRemoved.value = prefs.getBool(_prefsKey) ?? false;

    storeAvailable = await _iap.isAvailable();
    if (storeAvailable) {
      _purchaseSub = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onError: (Object e) {
          if (kDebugMode) debugPrint('PurchaseService: purchase stream error: $e');
        },
      );
      await _loadProduct();
    } else if (kDebugMode) {
      debugPrint('PurchaseService: store unavailable on this device.');
    }

    // Pick up an entitlement purchased on another device once signed in.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) unawaited(_syncFromFirestore(user.uid));
    });
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await _syncFromFirestore(currentUser.uid);
    }
  }

  Future<void> _loadProduct() async {
    final ids = {removeAdsProductId, ...coinPackAmounts.keys};
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null) {
      if (kDebugMode) {
        debugPrint('PurchaseService: product query failed: ${response.error}');
      }
      return;
    }
    if (kDebugMode && response.notFoundIDs.isNotEmpty) {
      debugPrint(
        'PurchaseService: no product found for ${response.notFoundIDs} — '
        'have they been created in App Store Connect / Play Console yet? '
        '(local simulator testing uses ios/Runner/Configuration.storekit '
        'instead, no store setup needed there)',
      );
    }
    for (final product in response.productDetails) {
      if (product.id == removeAdsProductId) {
        removeAdsProduct = product;
      } else if (coinPackAmounts.containsKey(product.id)) {
        coinPackProducts[product.id] = product;
      }
    }
  }

  Future<void> _syncFromFirestore(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(uid)
          .get();
      final remote = snap.data()?['adsRemoved'] as bool?;
      if (remote == true && !adsRemoved.value) {
        await _grantEntitlement(persistRemote: false);
      }
    } catch (_) {
      // Offline or rules rejection — local cache remains source of truth;
      // this retries on the next sign-in / app launch.
    }
  }

  /// Starts the purchase flow. Result arrives asynchronously via
  /// [purchaseStream] → [adsRemoved]; failures surface through [lastError].
  Future<void> buyRemoveAds() async {
    final product = removeAdsProduct;
    if (product == null) {
      lastError.value = 'Store not ready yet — try again in a moment.';
      AnalyticsService.instance.logPurchaseFailed(reason: 'store_not_ready');
      return;
    }
    lastError.value = null;
    purchaseInProgress.value = true;
    AnalyticsService.instance.logPurchaseStarted();
    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        purchaseInProgress.value = false;
        lastError.value = 'Purchase failed — please try again.';
        AnalyticsService.instance
            .logPurchaseFailed(reason: 'buy_call_rejected');
      }
    } catch (_) {
      purchaseInProgress.value = false;
      lastError.value = 'Purchase failed — please try again.';
      AnalyticsService.instance.logPurchaseFailed(reason: 'exception');
    }
  }

  /// Starts a coin-pack purchase flow. [productId] must be a key of
  /// [coinPackAmounts]. Result arrives asynchronously via [purchaseStream] →
  /// [lastCoinPackGrant]; failures surface through [lastError].
  Future<void> buyCoinPack(String productId) async {
    final product = coinPackProducts[productId];
    if (product == null) {
      lastError.value = 'Store not ready yet — try again in a moment.';
      AnalyticsService.instance.logPurchaseFailed(reason: 'store_not_ready');
      return;
    }
    lastError.value = null;
    purchaseInProgress.value = true;
    AnalyticsService.instance.logPurchaseStarted();
    try {
      final started = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        autoConsume: true,
      );
      if (!started) {
        purchaseInProgress.value = false;
        lastError.value = 'Purchase failed — please try again.';
        AnalyticsService.instance
            .logPurchaseFailed(reason: 'buy_call_rejected');
      }
    } catch (_) {
      purchaseInProgress.value = false;
      lastError.value = 'Purchase failed — please try again.';
      AnalyticsService.instance.logPurchaseFailed(reason: 'exception');
    }
  }

  /// Restores a prior purchase — required by App Store guidelines for
  /// non-consumables (e.g. after a reinstall). Same completion path as
  /// [buyRemoveAds].
  Future<void> restorePurchases() async {
    lastError.value = null;
    purchaseInProgress.value = true;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      lastError.value = 'Restore failed — please try again.';
    } finally {
      purchaseInProgress.value = false;
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final coinAmount = coinPackAmounts[purchase.productID];
      final isRemoveAds = purchase.productID == removeAdsProductId;
      if (!isRemoveAds && coinAmount == null) continue;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          purchaseInProgress.value = true;
        case PurchaseStatus.purchased:
          if (isRemoveAds) {
            await _grantEntitlement(completionSource: 'purchase');
          } else {
            _grantCoinPack(coinAmount!, completionSource: 'purchase');
          }
          purchaseInProgress.value = false;
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.restored:
          // Consumables (coin packs) are never restored by Apple/Google —
          // only the non-consumable remove_ads reaches this case in practice.
          if (isRemoveAds) {
            await _grantEntitlement(completionSource: 'restore');
          }
          purchaseInProgress.value = false;
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          purchaseInProgress.value = false;
          lastError.value =
              purchase.error?.message ?? 'Purchase failed — please try again.';
          AnalyticsService.instance.logPurchaseFailed(
            reason: purchase.error?.message ?? 'unknown',
          );
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.canceled:
          purchaseInProgress.value = false;
          AnalyticsService.instance.logPurchaseCancelled();
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
      }
    }
  }

  /// [completionSource] is `'purchase'` or `'restore'` for a user-driven
  /// purchase-flow completion (logs `purchase_completed`), or null for a
  /// passive cross-device sync ([_syncFromFirestore]) — the latter isn't a
  /// funnel event, so it's left unlogged.
  Future<void> _grantEntitlement({
    bool persistRemote = true,
    String? completionSource,
  }) async {
    adsRemoved.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);

    if (completionSource != null) {
      AnalyticsService.instance.logPurchaseCompleted(source: completionSource);
    }

    if (!persistRemote) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(uid)
          .set({'adsRemoved': true}, SetOptions(merge: true));
    } catch (_) {
      // Local entitlement is already granted either way; _syncFromFirestore
      // will retry mirroring it on the next sign-in if this write failed.
    }
  }

  /// Fires [lastCoinPackGrant] so [CurrencyNotifier] can credit the wallet.
  /// Coin packs are consumable and have no persistent "owned" state of their
  /// own — unlike [_grantEntitlement], there's nothing to cache here beyond
  /// the wallet balance itself, which [CurrencyNotifier] already persists.
  void _grantCoinPack(int coins, {required String completionSource}) {
    AnalyticsService.instance.logPurchaseCompleted(source: completionSource);
    _coinPackGrantNonce++;
    lastCoinPackGrant.value =
        CoinPackGrant(coins: coins, nonce: _coinPackGrantNonce);
  }

  /// Never called in production — [instance] lives for the app's lifetime,
  /// same as [AdsService]. Exists so tests can tear down cleanly.
  void dispose() {
    _purchaseSub?.cancel();
    _authSub?.cancel();
  }
}

/// One completed coin-pack purchase. [nonce] is monotonically increasing so
/// [ValueNotifier]'s equality check never suppresses a repeat purchase of
/// the same-sized pack (which would otherwise look like an unchanged value).
class CoinPackGrant {
  const CoinPackGrant({required this.coins, required this.nonce});

  final int coins;
  final int nonce;

  @override
  bool operator ==(Object other) =>
      other is CoinPackGrant && other.coins == coins && other.nonce == nonce;

  @override
  int get hashCode => Object.hash(coins, nonce);
}
