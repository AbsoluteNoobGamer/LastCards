import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'monetization_config.dart';
import 'monetization_provider.dart';

const String _prefsKeyLastInterstitialMs = 'monetization_interstitial_last_ms';

/// Minimum gap between interstitial impressions. Reduces "ads on every return"
/// and aligns with common AdMob guidance for natural break points.
const Duration kInterstitialMinInterval = Duration(minutes: 4);

@immutable
class PostGameInterstitialState {
  const PostGameInterstitialState({this.hasPending = false, this.isLoading = false});

  final bool hasPending;
  final bool isLoading;

  PostGameInterstitialState copyWith({bool? hasPending, bool? isLoading}) {
    return PostGameInterstitialState(
      hasPending: hasPending ?? this.hasPending,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PostGameInterstitialNotifier
    extends StateNotifier<PostGameInterstitialState> {
  PostGameInterstitialNotifier() : super(const PostGameInterstitialState());

  bool _disposed = false;

  void markCompletedPlaySession() {
    if (!kSupportsStoreMonetization()) return;
    if (kDebugMode) {
      debugPrint('Monetization: interstitial will be considered on next start screen.');
    }
    state = state.copyWith(hasPending: true);
  }

  void _setLoading(bool v) {
    if (_disposed) return;
    state = state.copyWith(isLoading: v);
  }

  /// Called when the start menu route becomes visible again (e.g. [RouteAware.didPopNext]).
  Future<void> maybeShowWhenStartVisible(WidgetRef ref, BuildContext context) async {
    if (!kSupportsStoreMonetization() || _disposed) return;
    if (!state.hasPending) return;
    if (!context.mounted) return;

    final mono = ref.read(monetizationProvider);
    if (!mono.ready) return;
    if (mono.adsRemoved) {
      state = state.copyWith(hasPending: false);
      return;
    }

    if (state.isLoading) return;

    final lastMs = (await SharedPreferences.getInstance())
        .getInt(_prefsKeyLastInterstitialMs);
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: false);
      if (DateTime.now().difference(last) < kInterstitialMinInterval) {
        return;
      }
    }

    final adUnit = kInterstitialAdUnitIdForPlatform();
    if (adUnit.isEmpty) {
      if (kDebugMode) {
        debugPrint('Monetization: no interstitial ad unit id; skipping.');
      }
      return;
    }

    _setLoading(true);
    try {
      await InterstitialAd.load(
        adUnitId: adUnit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
              return;
            }
            _setLoading(false);
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (a) {
                a.dispose();
                unawaited(_recordShown());
                if (_disposed) return;
                state = state.copyWith(hasPending: false);
              },
              onAdFailedToShowFullScreenContent: (a, err) {
                a.dispose();
                if (kDebugMode) {
                  debugPrint('Monetization: interstitial failed to show: $err');
                }
                if (_disposed) return;
                _setLoading(false);
              },
            );
            if (!context.mounted) {
              ad.dispose();
              if (!_disposed) {
                state = state.copyWith(isLoading: false);
              }
              return;
            }
            ad.show();
          },
          onAdFailedToLoad: (err) {
            if (kDebugMode) {
              debugPrint('Monetization: interstitial failed to load: $err');
            }
            if (_disposed) return;
            _setLoading(false);
          },
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Monetization: interstitial load error: $e\n$st');
      }
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  Future<void> _recordShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(
        _prefsKeyLastInterstitialMs, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final postGameInterstitialProvider = StateNotifierProvider<PostGameInterstitialNotifier,
    PostGameInterstitialState>((ref) {
  return PostGameInterstitialNotifier();
});
