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
      return ApiResult(
        success: ok,
        message: ok
            ? (body['message']?.toString() ?? '')
            : FriendlyErrors.fromResponse(response),
        body: body,
        sessionExpired:
            response.statusCode == 401 || body['code'] == 'SESSION_EXPIRED',
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

/// "Just now", "5 minutes ago", "2 hours ago", "Yesterday", "3 days ago",
/// then a date such as "Nov 23, 2026".
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final difference = current.difference(local);

  if (difference.isNegative || difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) {
    final m = difference.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }

  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final calendarDays = today.difference(day).inDays;

  if (calendarDays == 0) {
    final h = difference.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  if (calendarDays == 1) return 'Yesterday';
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
