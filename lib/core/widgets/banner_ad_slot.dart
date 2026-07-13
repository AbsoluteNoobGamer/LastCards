import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ads_service.dart';
import '../services/purchase_service.dart';

/// Loads and displays a single banner ad, sized to zero height until the ad
/// finishes loading (so it never reserves dead space if AdMob has no fill).
/// Renders nothing at all once the player has purchased "Remove Ads".
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, required this.placement, this.size = AdSize.banner});

  /// Identifies which screen this banner is on, e.g. "start_screen_banner".
  final String placement;

  final AdSize size;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!PurchaseService.instance.adsRemoved.value) {
      _loadAd();
    }
    PurchaseService.instance.adsRemoved.addListener(_onAdsRemovedChanged);
  }

  void _loadAd() {
    _ad = AdsService.instance.createBannerAd(
      placement: widget.placement,
      size: widget.size,
      onLoaded: () {
        if (!mounted) return;
        setState(() => _loaded = true);
      },
      onFailedToLoad: () {
        if (!mounted) return;
        setState(() {
          _ad = null;
          _loaded = false;
        });
      },
    );
  }

  void _onAdsRemovedChanged() {
    if (!mounted) return;
    if (PurchaseService.instance.adsRemoved.value) {
      setState(() {
        _ad?.dispose();
        _ad = null;
        _loaded = false;
      });
    }
  }

  @override
  void dispose() {
    PurchaseService.instance.adsRemoved.removeListener(_onAdsRemovedChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PurchaseService.instance.adsRemoved.value) return const SizedBox.shrink();
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: widget.size.width.toDouble(),
      height: widget.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
