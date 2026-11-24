import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ============================================================
// LOGIN SESSION
// ------------------------------------------------------------
// login.php returns a random session token. Private endpoints
// (messages, comments, notifications, password) check it, so the app
// sends it in the "X-Auth-Token" header.
//
// The token and the basic account details are kept in the phone's
// secure storage (Android Keystore / iOS Keychain), never the
// password. So the user stays logged in when they leave, close or
// restart the app, until they choose Log Out or the server says the
// session expired (30 days without use, or a password change).
// ============================================================

/// The logged-in account, as returned by login.php / session.php.
class SessionUser {
  const SessionUser({
    required this.userID,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.contactNo,
    required this.profilePic,
    required this.barangayID,
  });

  final String userID;
  final String firstName;
  final String lastName;
  final String email;
  final String contactNo;
  final String? profilePic;
  final String barangayID;

  bool get hasBarangay =>
      barangayID.isNotEmpty && barangayID.toLowerCase() != 'null';

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.toLowerCase() == 'null' ? '' : value;
    }

    final pic = text('profilePic');
    return SessionUser(
      userID: text('userID'),
      firstName: text('firstName'),
      lastName: text('lastName'),
      email: text('email'),
      contactNo: text('contactNo'),
      profilePic: pic.isEmpty ? null : pic,
      barangayID: text('barangayID'),
    );
  }

  Map<String, dynamic> toJson() => {
    'userID': userID,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'contactNo': contactNo,
    'profilePic': profilePic,
    'barangayID': barangayID,
  };

  SessionUser copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? contactNo,
    String? profilePic,
    String? barangayID,
  }) => SessionUser(
    userID: userID,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    contactNo: contactNo ?? this.contactNo,
    profilePic: profilePic ?? this.profilePic,
    barangayID: barangayID ?? this.barangayID,
  );
}

class AuthSession {
  AuthSession._();

  static const String _tokenKey = 'citisense_session_token';
  static const String _userKey = 'citisense_session_user';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String? _token;
  static SessionUser? _user;

  static String? get token => _token;
  static SessionUser? get user => _user;
  static bool get isLoggedIn => _token != null;

  /// Keeps the token in memory only (used before the account is known).
  static void start(String? token) {
    final value = token?.trim() ?? '';
    _token = value.isEmpty ? null : value;
  }

  /// Saves the session on the phone so the user stays logged in.
  static Future<void> save(String token, SessionUser user) async {
    start(token);
    _user = user;
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (e) {
      // The session still works until the app is closed.
      debugPrint('[SESSION] Could not save the session: $e');
    }
  }

  /// Updates the saved account details (e.g. after editing the profile).
  static Future<void> updateUser(SessionUser user) async {
    if (_token == null) return;
    _user = user;
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (e) {
      debugPrint('[SESSION] Could not update the saved account: $e');
    }
  }

  /// Reads the saved session (if any) into memory. Returns true when found.
  static Future<bool> load() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final rawUser = await _storage.read(key: _userKey);
      if (token == null || token.trim().isEmpty || rawUser == null) {
        return false;
      }

      final decoded = jsonDecode(rawUser);
      if (decoded is! Map) return false;

      final user = SessionUser.fromJson(Map<String, dynamic>.from(decoded));
      if (user.userID.isEmpty) return false;

      start(token);
      _user = user;
      return true;
    } catch (e) {
      debugPrint('[SESSION] Could not read the saved session: $e');
      return false;
    }
  }

  /// Forgets the session on this phone.
  static Future<void> clear() async {
    _token = null;
    _user = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (e) {
      debugPrint('[SESSION] Could not clear the saved session: $e');
    }
  }

  /// Headers for API calls, including the session token when logged in.
  static Map<String, String> headers({Map<String, String>? extra}) {
    return {
      'Accept': 'application/json',
      if (_token != null) 'X-Auth-Token': _token!,
      ...?extra,
    };
  }
}
