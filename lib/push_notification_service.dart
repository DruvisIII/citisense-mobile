import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_preference.dart';
import 'notification_router.dart';

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

    // Tapping a notification shown while the app was open opens what
    // it is about.
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) =>
          NotificationRouter.openPayload(response.payload),
    );

    // The app was closed and started by tapping one of those.
    try {
      final launch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        NotificationRouter.openPayload(launch?.notificationResponse?.payload);
      }
    } catch (error) {
      debugPrint('CitiSense launch notification check failed: $error');
    }

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

      // Show when it was actually sent (the server's time), not when
      // the phone happened to receive it.
      final sentAt = DateTime.tryParse(
        message.data['sentAt']?.toString() ?? '',
      );
      final when =
          (sentAt ?? message.sentTime ?? DateTime.now()).millisecondsSinceEpoch;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'citisense_updates',
          'CitiSense Updates',
          channelDescription: 'Report updates and barangay announcements',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          when: when,
          showWhen: true,
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
          payload: message.data.isEmpty ? null : jsonEncode(message.data),
        );
        debugPrint('CitiSense foreground local notification displayed.');
      } catch (error) {
        debugPrint('CitiSense local notification error: $error');
      }
    });

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      // The app was in the background.
      debugPrint('CitiSense notification opened: ${message.messageId}');
      NotificationRouter.openPushData(message.data);
    });

    // The app was closed: it waits until Home is open (NotificationRouter).
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('CitiSense launched by push: ${initialMessage.messageId}');
      NotificationRouter.openPushData(initialMessage.data);
    }

    _initialized = true;
  }
}
