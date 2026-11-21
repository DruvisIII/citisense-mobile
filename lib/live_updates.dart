import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ============================================================
// LIVE UPDATES
// ------------------------------------------------------------
// Keeps every screen up to date without pulling to refresh.
// Uses only your existing push notifications and existing API
// endpoints (no extra server files).
//
// Screens listen to [LiveUpdates.instance.changes] and reload
// with their usual endpoint when it ticks. It ticks when:
//   - a push notification arrives (or is tapped),
//   - the app comes back to the foreground,
//   - every 20 seconds while the app is open (so new reports,
//     announcements, and replies appear even without a push).
// ============================================================

class LiveUpdates with WidgetsBindingObserver {
  LiveUpdates._();

  static final LiveUpdates instance = LiveUpdates._();

  static const Duration _interval = Duration(seconds: 20);

  /// Increases whenever screens should reload their data.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  String? _userID;
  bool _foreground = true;
  bool _observing = false;

  Timer? _timer;
  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<RemoteMessage>? _onOpened;

  bool get _pushSupported => !kIsWeb && Platform.isAndroid;

  /// Call after login (Home does this). Safe to call again.
  void start({required String userID, required String barangayID}) {
    if (userID.trim().isEmpty) return;
    if (_userID == userID && _timer != null) return;

    _stopListening();
    _userID = userID;

    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }

    _timer = Timer.periodic(_interval, (_) {
      if (_foreground) notifyChanged();
    });

    if (_pushSupported) {
      // Your existing push notifications trigger an immediate refresh.
      _onMessage = FirebaseMessaging.onMessage.listen((_) => notifyChanged());
      _onOpened = FirebaseMessaging.onMessageOpenedApp.listen(
        (_) => notifyChanged(),
      );
    }
  }

  /// Call on logout.
  Future<void> stop() async {
    _stopListening();
    _userID = null;
  }

  /// Ask every listening screen to reload now (e.g. after submitting a
  /// report).
  void notifyChanged() {
    changes.value++;
  }

  /// Kept for callers; same as [notifyChanged].
  Future<void> checkNow() async => notifyChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _userID != null) {
      // Something may have changed while the app was in the background.
      notifyChanged();
    }
  }

  void _stopListening() {
    _timer?.cancel();
    _timer = null;
    _onMessage?.cancel();
    _onOpened?.cancel();
    _onMessage = null;
    _onOpened = null;
  }
}
