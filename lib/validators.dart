import 'package:flutter/services.dart';

// ============================================================
// SHARED FORM RULES
// ------------------------------------------------------------
// The same rules are enforced again by the PHP API
// (api/validation.php), so these are for instant feedback only.
// ============================================================

/// Philippine mobile numbers.
///
/// The field shows a fixed "+63" and the user types the 10 digits after it
/// (9XXXXXXXXX). The database keeps the existing 09XXXXXXXXX format, which
/// the admin website also uses.
class PhilippinePhone {
  PhilippinePhone._();

  static const String countryCode = '+63';
  static const int localDigits = 10;
  static final RegExp _valid = RegExp(r'^9\d{9}$');

  /// Only digits, at most 10. A pasted "09…", "639…" or "+639…" number is
  /// trimmed to the 10 digits after +63.
  static final List<TextInputFormatter> inputFormatters = [
    _PhilippinePhoneFormatter(),
  ];

  /// The 10 digits after +63 from any stored or typed form
  /// (09XXXXXXXXX, 639XXXXXXXXX, +639XXXXXXXXX or 9XXXXXXXXX).
  static String localPart(String? value) {
    var digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length > localDigits) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0') && digits.length > localDigits - 1) {
      digits = digits.substring(1);
    }
    return digits.length > localDigits
        ? digits.substring(0, localDigits)
        : digits;
  }

  static bool isValid(String localPart) => _valid.hasMatch(localPart);

  /// Stored format: 09XXXXXXXXX.
  static String toStored(String localPart) => '0$localPart';

  /// Error text for the field, or null when it is fine.
  /// [showEmpty] makes an empty field an error (after a submit attempt).
  static String? error(String localPart, {bool showEmpty = false}) {
    if (localPart.isEmpty) {
      return showEmpty ? 'Enter your mobile number.' : null;
    }
    if (!localPart.startsWith('9')) {
      return 'Mobile numbers start with 9, e.g. 917 123 4567.';
    }
    if (localPart.length != localDigits) {
      return 'Enter all 10 digits after +63.';
    }
    return null;
  }
}

class _PhilippinePhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = PhilippinePhone.localPart(newValue.text);
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Password rules for registration, password change and recovery.
class PasswordRules {
  PasswordRules._();

  static const int minLength = 6;
  // bcrypt (PHP password_hash) only uses the first 72 bytes.
  static const int maxLength = 72;

  /// Letters, numbers and the symbols on a standard keyboard
  /// (! @ # \$ % ^ & * ( ) - _ = + [ ] { } ; : ' " , . < > / ? \ | ` ~).
  /// No spaces, emojis or other special Unicode characters.
  static final RegExp _allowed = RegExp(r'^[\x21-\x7E]*$');

  /// Error text for the field, or null when it is fine.
  static String? error(String password, {bool showEmpty = false}) {
    if (password.isEmpty) {
      return showEmpty ? 'Enter a password.' : null;
    }
    if (!_allowed.hasMatch(password)) {
      return 'Use only letters, numbers and keyboard symbols '
          '(no spaces or emojis).';
    }
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (password.length > maxLength) {
      return 'Password must be at most $maxLength characters.';
    }
    return null;
  }

  static bool isValid(String password) =>
      password.isNotEmpty && error(password) == null;
}
