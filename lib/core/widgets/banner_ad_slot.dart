import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ads_service.dart';

/// Loads and displays a single banner ad, sized to zero height until the ad
/// finishes loading (so it never reserves dead space if AdMob has no fill).
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, this.size = AdSize.banner});

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
    _ad = AdsService.instance.createBannerAd(
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

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: widget.size.width.toDouble(),
      height: widget.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
