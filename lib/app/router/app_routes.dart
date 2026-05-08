import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../splash_screen.dart';
import '../../features/auth/presentation/widgets/auth_gate.dart';
import '../../features/gameplay/presentation/screens/debug/table_layout_lab_screen.dart';
import '../../features/gameplay/presentation/screens/table_screen.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const start = '/start';
  static const game = '/game';

  /// Debug-only: draggable table HUD mockups. Registered only when [kDebugMode].
  static const tableLayoutLab = '/dev/table-layout-lab';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.splash: (_) => const SplashScreen(),
  AppRoutes.start: (_) => const AuthGate(),
  AppRoutes.game: (_) => const TableScreen(),
  if (kDebugMode)
    AppRoutes.tableLayoutLab: (_) => const TableLayoutLabScreen(),
};
