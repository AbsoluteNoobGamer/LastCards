import 'package:flutter/widgets.dart';

import '../splash_screen.dart';
import '../../features/auth/presentation/widgets/auth_gate.dart';
import '../../features/gameplay/presentation/screens/table_screen.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const start = '/start';
  static const game = '/game';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.splash: (_) => const SplashScreen(),
  AppRoutes.start: (_) => const AuthGate(),
  AppRoutes.game: (_) => const TableScreen(),
};
