import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/api_config.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/home.dart';
import 'package:citisense/landing.dart';
import 'package:citisense/live_updates.dart';
import 'package:citisense/login.dart';
import 'package:citisense/notification_router.dart';

/// Lets code outside widgets (push notifications, expired sessions)
/// navigate.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Result of checking the saved session when the app opens.
enum RestoreResult { loggedIn, loggedOut }

// ============================================================
// SESSION MANAGER
// ------------------------------------------------------------
// - restore(): when the app opens, reuse the saved session.
// - openHome(): Home becomes the only page, so the back button
//   never returns to Log In.
// - logout(): only from the Log Out button.
// - sessionExpired(): the server no longer accepts the token.
// ============================================================

class SessionManager {
  SessionManager._();

  static bool _handlingExpiry = false;

  /// Checks the saved session with the server.
  ///
  /// Without internet the saved session is still used (the user stays
  /// logged in); only a definite "expired" answer logs the user out.
  static Future<RestoreResult> restore() async {
    final found = await AuthSession.load();
    if (!found) return RestoreResult.loggedOut;

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/session.php'),
            headers: AuthSession.headers(),
            body: {'action': 'restore'},
          )
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        body = const {};
      }

      if (response.statusCode == 401 || body['code'] == 'SESSION_EXPIRED') {
        await AuthSession.clear();
        return RestoreResult.loggedOut;
      }

      if (response.statusCode == 200 && body['success'] == true) {
        final user = body['user'];
        if (user is Map) {
          await AuthSession.updateUser(
            SessionUser.fromJson(Map<String, dynamic>.from(user)),
          );
        }
      }
    } catch (e) {
      // Offline or the server is slow: keep the saved session.
      debugPrint('[SESSION] Restore check skipped: $e');
    }

    final user = AuthSession.user;
    if (user == null || !user.hasBarangay) {
      await AuthSession.clear();
      return RestoreResult.loggedOut;
    }
    return RestoreResult.loggedIn;
  }

  /// The Home page for the saved account.
  static Widget homeFor(SessionUser user) => HomePage(
    userID: user.userID,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    contactNo: user.contactNo,
    profilePic: user.profilePic,
    barangayID: user.barangayID,
  );

  /// Opens Home and removes every page under it (Landing, Log In, ...).
  static void openHome(BuildContext context, SessionUser user) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => homeFor(user)),
      (route) => false,
    );
  }

  /// Logs out on the server and on this phone, then shows Log In with
  /// nothing behind it, so Back cannot reopen the app's pages.
  static Future<void> logout() async {
    final token = AuthSession.token;

    LiveUpdates.instance.stop();
    NotificationRouter.detach();

    if (token != null) {
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        fcmToken = null;
      }

      try {
        await http
            .post(
              Uri.parse('$apiBaseUrl/session.php'),
              headers: AuthSession.headers(),
              body: {
                'action': 'logout',
                if (fcmToken != null && fcmToken.isNotEmpty)
                  'fcmToken': fcmToken,
              },
            )
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        // The phone forgets the session anyway; the server ends it
        // after 30 days without use.
        debugPrint('[SESSION] Server logout failed: $e');
      }
    }

    await AuthSession.clear();
    _showLogin();
  }

  /// Called when the server rejects the token (expired or revoked).
  static Future<void> sessionExpired() async {
    if (_handlingExpiry || !AuthSession.isLoggedIn) return;
    _handlingExpiry = true;
    try {
      LiveUpdates.instance.stop();
      NotificationRouter.detach();
      await AuthSession.clear();
      _showLogin();

      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your session has expired. Please log in again.'),
          ),
        );
      }
    } finally {
      _handlingExpiry = false;
    }
  }

  static void _showLogin() {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  /// First page when nobody is logged in.
  static Widget get loggedOutHome => const LandingPage();
}
