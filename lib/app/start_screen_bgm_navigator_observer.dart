import 'package:flutter/widgets.dart';

import 'router/app_routes.dart';
import '../services/start_screen_bgm.dart';

/// Registered on [MaterialApp.navigatorObservers]. Stops menu BGM when a fullscreen
/// route is pushed **on top of** [/start]; ignores [PopupRoute] (bottom sheets,
/// dialogs) so selectors keep playing menu music.
final StartScreenBgmNavigatorObserver startScreenBgmNavigatorObserver =
    StartScreenBgmNavigatorObserver();

class StartScreenBgmNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) {
      return;
    }
    if (previousRoute?.settings.name != AppRoutes.start) {
      return;
    }
    StartScreenBgm.instance.notifyOpaqueNavigatorRoutePushed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PopupRoute<dynamic>) return;
    if (oldRoute?.settings.name != AppRoutes.start) {
      return;
    }
    StartScreenBgm.instance.notifyOpaqueNavigatorRoutePushed();
  }
}
