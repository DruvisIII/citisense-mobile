<?php
// ============================================================
// SHARED INPUT RULES
// ------------------------------------------------------------
// Same rules as lib/validators.dart in the app. The app checks
// them for instant feedback; these checks are the real guard.
// ============================================================

const CITISENSE_PASSWORD_MIN = 6;
// password_hash() (bcrypt) only uses the first 72 bytes.
const CITISENSE_PASSWORD_MAX = 72;

/**
 * Returns an error message, or null when the password is acceptable.
 * Allowed: letters, numbers and standard keyboard symbols (ASCII 33-126).
 * Rejected: spaces, emojis and other special Unicode characters.
 */
function citisense_password_error(string $password): ?string
{
    if ($password === '') {
        return 'Please enter a password.';
    }
    if (!preg_match('/^[\x21-\x7E]+$/', $password)) {
        return 'Passwords can only use letters, numbers and keyboard symbols (no spaces or emojis).';
    }
    if (strlen($password) < CITISENSE_PASSWORD_MIN) {
        return 'Password must be at least ' . CITISENSE_PASSWORD_MIN . ' characters.';
    }
    if (strlen($password) > CITISENSE_PASSWORD_MAX) {
        return 'Password must be at most ' . CITISENSE_PASSWORD_MAX . ' characters.';
    }
    return null;
}

/**
 * Normalizes a Philippine mobile number to 09XXXXXXXXX.
 * Accepts 9XXXXXXXXX, 09XXXXXXXXX, 639XXXXXXXXX and +639XXXXXXXXX
 * (spaces and dashes are ignored). Returns null when invalid.
 */
function citisense_normalize_ph_mobile(string $input): ?string
{
    $trimmed = trim($input);

    // Only digits, spaces, dashes, brackets and a leading + are allowed.
    if ($trimmed === '' || !preg_match('/^\+?[0-9 ()\-]+$/', $trimmed)) {
        return null;
    }

    $digits = preg_replace('/\D/', '', $trimmed);

    if (strlen($digits) === 12 && str_starts_with($digits, '63')) {
        $digits = substr($digits, 2);
    } elseif (strlen($digits) === 11 && str_starts_with($digits, '0')) {
        $digits = substr($digits, 1);
    }

    if (!preg_match('/^9[0-9]{9}$/', $digits)) {
        return null;
    }

    return '0' . $digits;
}

const CITISENSE_PHONE_ERROR = 'Please enter a valid mobile number: 10 digits after +63, starting with 9.';
