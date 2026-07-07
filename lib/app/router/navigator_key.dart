import 'package:flutter/widgets.dart';

/// Root navigator, used by services that need to push a screen from outside
/// the widget tree (e.g. [PushNotificationService] opening the notification
/// inbox when the user taps a push notification).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
