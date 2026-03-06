import 'package:flutter/widgets.dart';

import '../../features/gameplay/presentation/screens/table_screen.dart';
import '../../features/start/presentation/screens/start_screen.dart';

abstract final class AppRoutes {
  static const start = '/';
  static const game = '/game';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.start: (_) => const LastCardsStartScreen(),
  AppRoutes.game: (_) => const TableScreen(),
};
