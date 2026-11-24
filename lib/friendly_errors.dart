import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// ============================================================
// USER-FRIENDLY ERROR MESSAGES
// ------------------------------------------------------------
// Turns exceptions and server replies into plain language for the
// red error cards and snackbars. Technical details stay in the
// debug log only.
// ============================================================

class FriendlyErrors {
  FriendlyErrors._();

  static const String noConnection =
      'Unable to connect. Please check your internet connection.';
  static const String timeout = 'The request took too long. Please try again.';
  static const String server = 'Something went wrong. Please try again later.';
  static const String invalidInput =
      'Please check the information you entered.';
  static const String wrongLogin =
      'Incorrect email or password. Please try again.';

  /// Message for an exception thrown while talking to the server.
  static String fromException(Object error) {
    if (error is TimeoutException) return timeout;
    if (error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException) {
      return noConnection;
    }
    if (error is FormatException) return server;

    // Exceptions we threw ourselves with a readable message.
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return fromMessage(text);
  }

  /// Keeps a readable server message; replaces technical ones.
  static String fromMessage(String? message, {String fallback = server}) {
    final text = (message ?? '').trim();
    if (text.isEmpty) return fallback;

    final lower = text.toLowerCase();

    const technical = [
      'sql',
      'mysqli',
      'database',
      'exception',
      'uncaught',
      'stack trace',
      'fatal error',
      'warning:',
      'notice:',
      'undefined',
      'null check',
      'socketexception',
      'clientexception',
      'formatexception',
      'xmlhttprequest',
      'http ',
      'status code',
      'errno',
      'syntax error',
      'unexpected character',
      'json',
      'curl',
      'php',
      'token',
      '.php',
    ];
    if (technical.any(lower.contains)) {
      if (lower.contains('timeout') || lower.contains('timed out')) {
        return timeout;
      }
      if (lower.contains('socket') ||
          lower.contains('connection') ||
          lower.contains('network') ||
          lower.contains('host lookup')) {
        return noConnection;
      }
      return fallback;
    }

    // Common short technical phrases.
    if (lower.contains('network request failed') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection closed')) {
      return noConnection;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return timeout;
    }
    if (lower == 'invalid credentials' || lower.contains('invalid password')) {
      return wrongLogin;
    }
    if (lower == 'validation failed' || lower == 'invalid input') {
      return invalidInput;
    }
    if (lower == 'server error' || lower == 'internal server error') {
      return server;
    }

    return text;
  }

  /// Message for a server reply that was not successful.
  static String fromResponse(http.Response response, {String? fallback}) {
    String? message;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        message = decoded['message'].toString();
      }
    } catch (_) {
      // Not JSON (e.g. a hosting error page).
    }

    if (message != null && message.trim().isNotEmpty) {
      return fromMessage(message, fallback: fallback ?? server);
    }
    if (response.statusCode == 408 || response.statusCode == 504) {
      return timeout;
    }
    if (response.statusCode == 429) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return fallback ?? server;
  }
}
