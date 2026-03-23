import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/services/card_back_service.dart';
import 'core/services/profile_service.dart';
import 'firebase_options.dart';
import 'services/audio_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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

  // Initialise default profile ("Noob 1") on first launch.
  // This is a no-op on all subsequent launches.
  await const ProfileService().initDefaultIfNeeded();
  await CardBackService.instance.init();
  await AudioService.instance.init();

  runApp(
    // Riverpod root scope
    const ProviderScope(
      child: StackAndFlowApp(),
    ),
  );
}

