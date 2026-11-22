<?php

/*
|--------------------------------------------------------------------------
| CANCEL EMAIL CHANGE OTP
|--------------------------------------------------------------------------
| POST: userID
|
| Called when the user leaves the "Verify Your New Email" screen without
| verifying (changed their mind, inbox inactive, forgot its password).
| Voids any unused codes so they can no longer change the email.
| The user's email is NOT changed.
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

function cancel_email_change_response(
    bool $success,
    string $message,
    int $status = 200
): void {
    http_response_code($status);
    echo json_encode([
        'success' => $success,
        'message' => $message
    ]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    cancel_email_change_response(false, 'Invalid request method.', 405);
}

$userID = trim($_POST['userID'] ?? '');

if ($userID === '') {
    cancel_email_change_response(false, 'User is required.', 400);
}

try {
    // Nothing to cancel if no code was ever requested.
    $table = $conn->query("SHOW TABLES LIKE 'email_change_otps'");

    if (!$table || $table->num_rows === 0) {
        cancel_email_change_response(true, 'Email change cancelled.');
    }

    $stmt = $conn->prepare(
        "UPDATE email_change_otps
         SET used_at = NOW()
         WHERE userID = ? AND used_at IS NULL"
    );

    if (!$stmt) {
        cancel_email_change_response(false, 'Database error.', 500);
    }

    $stmt->bind_param('s', $userID);
    $stmt->execute();
    $stmt->close();

    cancel_email_change_response(
        true,
        'Email change cancelled. Your email was not changed.'
    );

} catch (Throwable $e) {
    error_log('CitiSense cancel email change error: ' . $e->getMessage());
    cancel_email_change_response(false, 'Something went wrong.', 500);
}

?>
