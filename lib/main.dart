import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/services/card_back_service.dart';
import 'core/services/profile_service.dart';
import 'services/audio_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

