import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/navigator_key.dart';
import '../../features/notifications/presentation/screens/notification_inbox_screen.dart';
import '../../features/online/providers/online_session_provider.dart';
import '../../features/online/screens/matchmaking_screen.dart';
import '../../features/tournament/providers/tournament_session_provider.dart';
import 'firestore_profile_service.dart';

/// Background message isolate entry point — must be a top-level function,
/// registered before `runApp()`. No UI work happens here: for
/// notification-type FCM messages the OS shows the tray entry itself; the
/// in-app inbox list is populated separately from Firestore (source of
/// truth), not from this handler.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Wraps Firebase Cloud Messaging: permission request, device token
/// registration (synced to `users/{uid}.fcmTokens`, see
/// [FirestoreProfileService.addFcmToken]), and foreground/tap message
/// handling. Singleton initialized once from `main()`, mirroring
/// [AudioService]/[CardBackService]/[AdsService] — no reactive Riverpod state
/// to expose.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'default_channel',
    'Notifications',
    description: 'Match invites, turn reminders, and app announcements.',
    importance: Importance.high,
  );

  /// Broadcast topics every install subscribes to — no per-user targeting,
  /// used for announcements that apply to everyone regardless of sign-in
  /// state. Sent from `AppUpdateBroadcaster`/`RoomManager` on the server
  /// (see `server/lib/fcm_sender.dart`'s `notifyTopic`).
  static const _broadcastTopics = ['app_updates', 'matchmaking_open'];

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirestoreProfileService _profileService = FirestoreProfileService();

  bool _initialized = false;
  String? _registeredToken;

  /// Platform push plumbing (APNs handshake, permission dialogs, local-notif
  /// registration) is known to stall indefinitely on iOS Simulators — a
  /// `try/catch` alone doesn't help a call that never completes, only one
  /// that throws. Every potentially-blocking await below is wrapped with
  /// this so a stuck call degrades to "push disabled" instead of hanging
  /// `main()` (and therefore `runApp()`) forever.
  static const _stepTimeout = Duration(seconds: 5);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(_stepTimeout);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(_stepTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService: permission request failed: $e');
    }

    try {
      await _local
          .initialize(
            // Permission already requested above via FirebaseMessaging;
            // asking again here (the Darwin defaults) risks a
            // second/conflicting platform-channel prompt, which has been
            // observed to hang app startup on iOS Simulators.
            const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final payload = response.payload;
              if (payload == null) {
                _openInbox();
                return;
              }
              try {
                _handleNotificationData(
                    jsonDecode(payload) as Map<String, dynamic>);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('PushNotificationService: bad notification payload: $e');
                }
                _openInbox();
              }
            },
          )
          .timeout(_stepTimeout);
      if (Platform.isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_androidChannel)
            .timeout(_stepTimeout);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService: local notifications init failed: $e');
    }

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp
        .listen((message) => _handleNotificationData(message.data));
    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage().timeout(_stepTimeout);
      if (initialMessage != null) _handleNotificationData(initialMessage.data);
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService: getInitialMessage failed: $e');
    }

    for (final topic in _broadcastTopics) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic).timeout(_stepTimeout);
      } catch (e) {
        if (kDebugMode) debugPrint('PushNotificationService: subscribeToTopic($topic) failed: $e');
      }
    }

    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

    // (Re)register the token whenever the signed-in user changes — offline
    // and guest sessions have no `uid` to attach a token to, so this is a
    // no-op until the player signs in. Runs fully async (not awaited by
    // init()), so a stuck getToken() here can't block startup either way,
    // but the timeout keeps it from leaking a hung future.
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await FirebaseMessaging.instance.getToken().timeout(_stepTimeout);
        if (token != null) await _registerToken(token);
      } catch (e) {
        if (kDebugMode) debugPrint('PushNotificationService: getToken failed: $e');
      }
    });
  }

  Future<void> _registerToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _registeredToken = token;
    try {
      await _profileService.addFcmToken(uid, token);
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService: failed to register token: $e');
    }
  }

  /// Call from the sign-out flow so a shared/reset device stops receiving
  /// pushes meant for the account that just signed out.
  Future<void> unregisterCurrentToken(String uid) async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      await _profileService.removeFcmToken(uid, token);
    } catch (e) {
      if (kDebugMode) debugPrint('PushNotificationService: failed to unregister token: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  void _openInbox() {
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationInboxScreen()),
    );
  }

  /// Routes a tapped notification based on its data payload — a
  /// `matchmaking_open` payload (see `RoomManager._handleQuickplay` on the
  /// server) jumps straight into [MatchmakingScreen] for the same mode/table
  /// size instead of the generic inbox, so the player doesn't miss the table
  /// re-navigating manually. Anything else (friend invites, app updates,
  /// unrecognized/empty payloads) falls back to the inbox.
  void _handleNotificationData(Map<String, dynamic> data) {
    if (data['type'] != 'matchmaking_open') {
      _openInbox();
      return;
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      _openInbox();
      return;
    }

    final container = ProviderScope.containerOf(context);
    final gameMode = data['gameMode'] as String? ?? '';
    final joinWaitingQueue = data['joinWaitingQueue'] == 'true';
    final playerCount =
        int.tryParse(data['playerCount']?.toString() ?? '') ?? 4;

    if (gameMode == 'bust') {
      container.read(tournamentSessionProvider.notifier).setSubMode(GameSubMode.bust);
      container.read(onlineSessionProvider.notifier).setPlayerCount(10);
    } else {
      final mode = switch (gameMode) {
        'ranked' => OnlineGameMode.ranked,
        'ranked_hardcore' => OnlineGameMode.rankedHardcore,
        _ => OnlineGameMode.quickMatchCasual,
      };
      final notifier = container.read(onlineSessionProvider.notifier);
      notifier.setMode(mode);
      notifier.setQueueJoinStyle(joinWaitingQueue
          ? OnlineQueueJoinStyle.joinWaitingQueue
          : OnlineQueueJoinStyle.selectTable);
      if (!joinWaitingQueue) {
        notifier.setPlayerCount(playerCount);
      }
    }

    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
    );
  }
}
