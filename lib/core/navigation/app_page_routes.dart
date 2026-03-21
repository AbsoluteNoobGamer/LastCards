import 'package:flutter/material.dart';

/// Shared forward navigation transitions (fade + subtle slide).
class AppPageRoutes {
  AppPageRoutes._();

  static const Duration transitionDuration = Duration(milliseconds: 300);

  static PageRoute<T> fadeSlide<T extends Object?>(
    Widget Function(BuildContext context) builder, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
    bool maintainState = true,
    bool barrierDismissible = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      maintainState: maintainState,
      barrierDismissible: barrierDismissible,
      transitionDuration: transitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
