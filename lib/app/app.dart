import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme_data.dart';
import '../core/providers/theme_provider.dart';
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
    final themeState = ref.watch(themeProvider);
    return MaterialApp(
      title: 'Last Cards',
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(themeState.theme),
      initialRoute: AppRoutes.start,
      routes: appRoutes,
    );
  }
}
