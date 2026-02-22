import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'ui/screens/lobby_screen.dart';
import 'ui/screens/table_screen.dart';
import 'ui/screens/start_screen.dart';

void main() {
  runApp(
    // Riverpod root scope
    const ProviderScope(
      child: StackAndFlowApp(),
    ),
  );
}

class StackAndFlowApp extends StatelessWidget {
  const StackAndFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stack & Flow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const StackFlowStartScreen(),
        '/lobby': (_) => const LobbyScreen(),
        '/game': (_) => const TableScreen(),
      },
    );
  }
}
