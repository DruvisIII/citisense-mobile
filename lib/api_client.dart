import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:citisense/api_config.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/friendly_errors.dart';

/// Result of an API call: [message] is always safe to show to users.
class ApiResult {
  const ApiResult({
    required this.success,
    required this.message,
    this.body = const {},
    this.sessionExpired = false,
  });

  final bool success;
  final String message;
  final Map<String, dynamic> body;
  final bool sessionExpired;

  dynamic get data => body['data'];
}

/// Small helper for the PHP API: sends the session token, applies a
/// timeout, and turns every failure into a user-friendly message.
class ApiClient {
  ApiClient._();

  /// Called when the server says the saved session is no longer valid
  /// (set in main.dart: logs out and shows Log In).
  static void Function()? onSessionExpired;

  static Future<ApiResult> postForm(
    String endpoint,
    Map<String, String> fields, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/$endpoint'),
            headers: AuthSession.headers(),
            body: fields,
          )
          .timeout(timeout);

      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        body = const {};
      }

      final bool ok = response.statusCode == 200 && body['success'] == true;
      if (ok) ServerClock.syncFromBody(body);
      final bool expired =
          response.statusCode == 401 || body['code'] == 'SESSION_EXPIRED';
      if (expired && AuthSession.isLoggedIn) onSessionExpired?.call();

      return ApiResult(
        success: ok,
        message: ok
            ? (body['message']?.toString() ?? '')
            : FriendlyErrors.fromResponse(response),
        body: body,
        sessionExpired: expired,
      );
    } catch (e) {
      debugPrint('[API] $endpoint failed: $e');
      return ApiResult(
        success: false,
        message: FriendlyErrors.fromException(e),
      );
    }
  }
}

/// Parses an API timestamp and converts it to the phone's local time.
/// The API sends ISO 8601 with a UTC offset (e.g. 2026-11-23T10:00:00+00:00).
DateTime? parseApiTime(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

// ============================================================
// SERVER CLOCK
// ------------------------------------------------------------
// Lists from the API include "serverTime" (the database's NOW()).
// How old an item is = server time - item time, both from the same
// clock, so a phone with a wrong clock or time zone (or a database
// whose time zone was read wrong) still shows "5 minutes ago".
// ============================================================

class ServerClock {
  ServerClock._();

  /// Phone time minus server time (positive when the phone is ahead).
  static Duration _offset = Duration.zero;

  static Duration get offset => _offset;

  /// Reads "serverTime" from an API response body, if present.
  static void syncFromBody(dynamic body) {
    if (body is! Map) return;
    final server = parseApiTime(body['serverTime']);
    if (server == null) return;
    _offset = DateTime.now().difference(server);
  }

  /// "Now" on the server's clock, in the phone's time zone.
  static DateTime now() => DateTime.now().subtract(_offset);

  /// For tests.
  static void reset() => _offset = Duration.zero;
}

/// "Just now", "5 minutes ago", "3 hours ago" (anything under a day),
/// "Yesterday", "3 days ago", then a date such as "Nov 23, 2026".
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final current = now ?? ServerClock.now();
  final local = time.toLocal();
  final difference = current.difference(local);

  // A time slightly in the future (clocks a few seconds apart) is "now".
  if (difference.isNegative || difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) {
    final m = difference.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  // Under a day is always counted in hours, so something from 1 hour
  // ago is never called "Yesterday" just because midnight passed.
  if (difference.inHours < 24) {
    final h = difference.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }

  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final calendarDays = today.difference(day).inDays;

  if (calendarDays <= 1) return 'Yesterday';
  if (calendarDays < 7) return '$calendarDays days ago';

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

/// Web address of a profile picture saved in the database (e.g.
/// "uploads/profile/USR001_1764000000_ab12cd.jpg"), or null when there is
/// none. Profile pictures are loaded through the API's media.php, which also
/// finds pictures saved by the admin website (uploads/profile_pictures/...).
String? profileImageUrl(String? path) {
  final value = path?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null') return null;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  final clean = value.replaceFirst(RegExp(r'^(\.{0,2}/)+'), '');
  if (clean.startsWith('uploads/profile/') ||
      clean.startsWith('uploads/profile_pictures/')) {
    return '$apiBaseUrl/media.php?p=${Uri.encodeQueryComponent(clean)}';
  }

  return '$serverBaseUrl/$clean';
}
