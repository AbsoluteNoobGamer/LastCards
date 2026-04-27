import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers/theme_provider.dart';
import 'monetization_config.dart';
import 'monetization_provider.dart';

/// Outcome of the rewarded-ad gate for offline tournament "Skip to result".
enum TournamentSkipAdOutcome {
  /// Start the fast-forward / simulation immediately.
  startSimulation,
  /// User closed the offer dialog; no error message.
  userCancelled,
  /// Ad failed to load, failed to show, or closed without a reward.
  adDidNotComplete,
}

/// Shown for offline tournament "Skip to result" when ads are not removed.
Future<TournamentSkipAdOutcome> runTournamentSkipRewardedAdGate({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  if (!kSupportsStoreMonetization()) {
    return TournamentSkipAdOutcome.startSimulation;
  }
  if (ref.read(monetizationProvider).adsRemoved) {
    return TournamentSkipAdOutcome.startSimulation;
  }
  if (!context.mounted) return TournamentSkipAdOutcome.userCancelled;

  final theme = ref.read(themeProvider).theme;
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: theme.surfacePanel,
        title: Text(
          'Fast-forward this round',
          style: TextStyle(
            color: theme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Watch a short video to skip the rest of the round and go straight '
          'to the result. You can remove all ads, including this one, with a '
          'one-time purchase in Settings.',
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Not now',
              style: TextStyle(color: theme.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.backgroundDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Watch video'),
          ),
        ],
      );
    },
  );
  if (go != true) return TournamentSkipAdOutcome.userCancelled;
  if (!context.mounted) return TournamentSkipAdOutcome.userCancelled;

  final ok = await _loadAndShowRewardedTournamentSkip(context);
  if (ok) {
    return TournamentSkipAdOutcome.startSimulation;
  }
  return TournamentSkipAdOutcome.adDidNotComplete;
}

/// Loads and shows a rewarded ad. Completes with `true` if the user earned
/// the reward, `false` otherwise.
Future<bool> _loadAndShowRewardedTournamentSkip(BuildContext context) async {
  final adUnit = kRewardedAdUnitIdForPlatform();
  if (adUnit.isEmpty) {
    if (kDebugMode) {
      debugPrint('Monetization: no rewarded ad unit for tournament skip.');
    }
    return false;
  }

  final completer = Completer<bool>();
  var earned = false;

  void report(bool value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  await RewardedAd.load(
    adUnitId: adUnit,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (RewardedAd ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (AdWithoutView a) {},
          onAdDismissedFullScreenContent: (AdWithoutView a) {
            a.dispose();
            report(earned);
          },
          onAdFailedToShowFullScreenContent: (AdWithoutView a, Object error) {
            a.dispose();
            if (kDebugMode) {
              debugPrint('Monetization: rewarded failed to show: $error');
            }
            report(false);
          },
        );
        if (!context.mounted) {
          ad.dispose();
          report(false);
          return;
        }
        ad.show(
          onUserEarnedReward: (AdWithoutView a, RewardItem r) {
            earned = true;
          },
        );
      },
      onAdFailedToLoad: (Object error) {
        if (kDebugMode) {
          debugPrint('Monetization: rewarded failed to load: $error');
        }
        report(false);
      },
    ),
  );
  return completer.future;
}
