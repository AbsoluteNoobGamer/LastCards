import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router/app_routes.dart';

class StackAndFlowApp extends StatelessWidget {
  const StackAndFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stack & Flow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRoutes.start,
      routes: appRoutes,
    );
  }
}
