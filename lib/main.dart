import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/services/ads_service.dart';
import 'core/services/card_back_service.dart';
import 'core/services/profile_service.dart';
import 'core/services/push_notification_service.dart';
import 'firebase_options.dart';
import 'services/audio_service.dart';
import 'services/start_screen_bgm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Align with Android 15+ edge-to-edge (MainActivity also calls enableEdgeToEdge()).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Register before runApp so Android lifecycle reaches BGM pause logic even if
  // playback starts later (singleton self-registration was too late on some devices).
  registerStartScreenBgmAppLifecycleObserver();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    // Persist auth across app restarts (web) and give Firebase time to restore (all platforms).
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped (run flutterfire configure if needed): $e');
    }
  }

  // Lock to portrait on phones (avoids broken landscape layout).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Swallow audio platform errors globally so they can never hard-crash the app.
  // All other Flutter framework errors are forwarded to the default handler.
  FlutterError.onError = (FlutterErrorDetails details) {
    final description = details.toString();
    if (description.contains('AudioError') ||
        description.contains('PlatformException') ||
        description.contains('AndroidAudioError')) {
      if (kDebugMode) {
        debugPrint('Non-fatal audio error (swallowed): ${details.exception}');
      }
      return;
    }
    FlutterError.presentError(details);
  };

  // Initialise default local profile name on first launch.
  // This is a no-op on all subsequent launches.
  await const ProfileService().initDefaultIfNeeded();
  await CardBackService.instance.init();
  await AudioService.instance.init();

  // Ads/push are both optional, network/platform-plugin-heavy services —
  // never let either block startup. A timeout is required in addition to
  // try/catch: a hung (never-completing) platform call isn't an exception,
  // so only the timeout — not the catch — protects runApp() from it.
  const initTimeout = Duration(seconds: 8);
  try {
    await AdsService.instance.init().timeout(initTimeout);
  } catch (e) {
    if (kDebugMode) debugPrint('AdsService init skipped: $e');
  }
  if (firebaseReady) {
    try {
      await PushNotificationService.instance.init().timeout(initTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService init skipped: $e');
    }
  }

  runApp(
    // Riverpod root scope
    const ProviderScope(
      child: LastCardsApp(),
    ),
  );
}

