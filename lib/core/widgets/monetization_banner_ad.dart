import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Anchored adaptive banner for the bottom of a screen (e.g. start menu).
///
/// Uses [AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize] (google_mobile_ads 6.x).
/// When upgrading to plugin 8.x+ and Dart 3.10+, you may switch to
/// [AdSize.getLargeAnchoredAdaptiveBannerAdSize] for taller “large” adaptive banners;
/// revisit layout padding (e.g. start screen bottom inset) if the slot height changes.
class MonetizationBannerAd extends StatefulWidget {
  const MonetizationBannerAd({super.key, required this.adUnitId});

  final String adUnitId;

  @override
  State<MonetizationBannerAd> createState() => _MonetizationBannerAdState();
}

class _MonetizationBannerAdState extends State<MonetizationBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width <= 0) return;

    // See class doc: 6.x API; 8.x offers getLargeAnchoredAdaptiveBannerAdSize.
    final size =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    unawaited(
      BannerAd(
        adUnitId: widget.adUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (Ad ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _ad = ad as BannerAd;
              _loaded = true;
            });
          },
          onAdFailedToLoad: (Ad failed, LoadAdError error) {
            failed.dispose();
          },
        ),
      ).load(),
    );
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
