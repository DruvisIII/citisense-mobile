// ============================================================
// LOGIN SESSION
// ------------------------------------------------------------
// login.php returns a session token. Private endpoints (messages,
// comments, notifications, password) check it, so the app sends it
// in the "X-Auth-Token" header. It lives only in memory: logging out
// or closing the app ends it, matching how the app already works
// (users log in each time they open it).
// ============================================================

class AuthSession {
  AuthSession._();

  static String? _token;

  static String? get token => _token;

  static void start(String? token) {
    final value = token?.trim() ?? '';
    _token = value.isEmpty ? null : value;
  }

  static void clear() => _token = null;

  /// Headers for API calls, including the session token when logged in.
  static Map<String, String> headers({Map<String, String>? extra}) {
    return {
      'Accept': 'application/json',
      if (_token != null) 'X-Auth-Token': _token!,
      ...?extra,
    };
  }
}
