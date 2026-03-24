import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme_data.dart';
import '../core/providers/online_rejoin_listener_provider.dart';
import '../core/providers/theme_provider.dart';
import '../features/settings/presentation/widgets/settings_modal.dart';
import 'router/app_routes.dart';

class StackAndFlowApp extends ConsumerStatefulWidget {
  const StackAndFlowApp({super.key});

  @override
  ConsumerState<StackAndFlowApp> createState() => _StackAndFlowAppState();
}

class _StackAndFlowAppState extends ConsumerState<StackAndFlowApp> {
  @override
  void initState() {
    super.initState();
    // Load the persisted theme index from SharedPreferences on start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(themeProvider.notifier).loadFromPrefs();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(onlineRejoinListenerProvider);
    final themeState = ref.watch(themeProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    return MaterialApp(
      title: 'Last Cards',
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(themeState.theme),
      initialRoute: AppRoutes.splash,
      routes: appRoutes,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: mq.disableAnimations || reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
