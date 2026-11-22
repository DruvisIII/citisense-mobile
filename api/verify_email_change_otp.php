<?php

/*
|--------------------------------------------------------------------------
| VERIFY EMAIL CHANGE OTP
|--------------------------------------------------------------------------
| POST: userID, newEmail, otp
|
| Checks the code sent by send_email_change_otp.php. When it matches,
| the user's email is updated to the new, verified address.
*/

error_reporting(E_ALL);
ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/config.php';

function verify_email_change_response(
    bool $success,
    string $message,
    int $status = 200,
    array $extra = []
): void {
    http_response_code($status);

    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message
    ], $extra));
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    verify_email_change_response(false, 'Invalid request method.', 405);
}

$userID = trim($_POST['userID'] ?? '');
$newEmail = strtolower(trim($_POST['newEmail'] ?? ''));
$otp = trim($_POST['otp'] ?? '');

if ($userID === '' || $newEmail === '' || $otp === '') {
    verify_email_change_response(
        false,
        'User, new email, and verification code are required.',
        400
    );
}

if (!filter_var($newEmail, FILTER_VALIDATE_EMAIL)) {
    verify_email_change_response(false, 'Invalid email address.', 400);
}

if (!preg_match('/^[0-9]{6}$/', $otp)) {
    verify_email_change_response(
        false,
        'Please enter a valid six-digit verification code.',
        400
    );
}

try {

    // Latest unused code for this user and new email.
    $stmt = $conn->prepare(
        "SELECT id, otp_hash, attempts, expires_at
         FROM email_change_otps
         WHERE userID = ? AND new_email = ? AND used_at IS NULL
         ORDER BY id DESC
         LIMIT 1"
    );

    if (!$stmt) {
        verify_email_change_response(false, 'Database error.', 500);
    }

    $stmt->bind_param('ss', $userID, $newEmail);
    $stmt->execute();
    $record = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$record) {
        verify_email_change_response(
            false,
            'No pending verification code found. Please request a new one.'
        );
    }

    if (strtotime($record['expires_at']) <= time()) {
        verify_email_change_response(
            false,
            'Your verification code has expired. Please request a new one.'
        );
    }

    if ((int)$record['attempts'] >= 5) {
        verify_email_change_response(
            false,
            'Too many incorrect attempts. Please request a new code.'
        );
    }

    if (!password_verify($otp, $record['otp_hash'])) {
        $fail = $conn->prepare(
            "UPDATE email_change_otps SET attempts = attempts + 1 WHERE id = ?"
        );
        $fail->bind_param('i', $record['id']);
        $fail->execute();
        $fail->close();

        verify_email_change_response(false, 'Incorrect verification code.');
    }

    // Check again in case another account took the email meanwhile.
    $check = $conn->prepare(
        "SELECT userID FROM users
         WHERE LOWER(email) = ? AND userID <> ?
         LIMIT 1"
    );
    $check->bind_param('ss', $newEmail, $userID);
    $check->execute();
    $emailTaken = $check->get_result()->num_rows > 0;
    $check->close();

    if ($emailTaken) {
        verify_email_change_response(
            false,
            'This email address is already used by another account.',
            409,
            ['code' => 'EMAIL_TAKEN']
        );
    }

    // Update the email and close the code together.
    $conn->begin_transaction();

    $updateUser = $conn->prepare(
        "UPDATE users SET email = ? WHERE userID = ?"
    );
    $updateUser->bind_param('ss', $newEmail, $userID);

    if (!$updateUser->execute()) {
        $updateUser->close();
        $conn->rollback();
        verify_email_change_response(false, 'Failed to update your email.', 500);
    }
    $updateUser->close();

    $closeCodes = $conn->prepare(
        "UPDATE email_change_otps
         SET used_at = NOW(), attempts = attempts + 1
         WHERE userID = ? AND used_at IS NULL"
    );
    $closeCodes->bind_param('s', $userID);
    $closeCodes->execute();
    $closeCodes->close();

    $conn->commit();

    verify_email_change_response(true, 'Your new email has been verified.', 200, [
        'data' => ['email' => $newEmail]
    ]);

} catch (Throwable $e) {

    error_log('CitiSense email change verification error: ' . $e->getMessage());

    try {
        $conn->rollback();
    } catch (Throwable $ignored) {
    }

    verify_email_change_response(false, 'Something went wrong. Please try again.', 500);
}

?>
