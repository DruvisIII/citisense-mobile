import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_preference.dart';

class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'citisense_updates',
    'CitiSense Updates',
    description: 'Report updates and barangay announcements',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid || _initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _localNotifications.initialize(settings: initializationSettings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);

    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('CitiSense FCM permission: ${permission.authorizationStatus}');

    final token = await _messaging.getToken();
    if (token != null) {
      debugPrint('CitiSense FCM token available (length: ${token.length}).');
      // Existing login.php registration must send this token after login.
    }

    _tokenSubscription = _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('CitiSense FCM token refreshed (length: ${newToken.length}).');
      // TODO: Send refreshed token using an authenticated device-token API.
    });

    _foregroundSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) async {
      debugPrint('CitiSense foreground FCM received: ${message.messageId}');
      if (!await NotificationPreference.isEnabled()) {
        debugPrint(
          'CitiSense foreground alert suppressed by in-app preference.',
        );
        return;
      }
      final notification = message.notification;
      if (notification == null && message.data.isEmpty) return;

      final title = notification?.title ?? 'CitiSense';
      final body =
          notification?.body ?? 'You have a new update to your report.';

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'citisense_updates',
          'CitiSense Updates',
          channelDescription: 'Report updates and barangay announcements',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      );

      try {
        await _localNotifications.show(
          id:
              (message.messageId?.hashCode ??
                  DateTime.now().millisecondsSinceEpoch) &
              0x7fffffff,
          title: title,
          body: body,
          notificationDetails: details,
        );
        debugPrint('CitiSense foreground local notification displayed.');
      } catch (error) {
        debugPrint('CitiSense local notification error: $error');
      }
    });

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      debugPrint('CitiSense notification opened: ${message.messageId}');
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('CitiSense launched by push: ${initialMessage.messageId}');
    }

    _initialized = true;
  }
}
